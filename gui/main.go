package main

import (
	"encoding/json"
	"encoding/xml"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// Static VM catalog — OS/IP/Role are known; live state comes from virsh
// ---------------------------------------------------------------------------

type VMConfig struct {
	Name string
	OS   string
	IP   string
	Role string
}

var vmCatalog = []VMConfig{
	{Name: "attacker", OS: "Kali Linux 2026.1", IP: "10.0.0.1", Role: "Attacker"},
	{Name: "user-ubuntu24", OS: "Ubuntu 24.04 Server", IP: "10.0.0.100", Role: "Linux User"},
	{Name: "user-windows10", OS: "Windows 10 Enterprise 22H2", IP: "10.0.0.101", Role: "Windows User"},
}

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

type VMStatus struct {
	Name       string  `json:"name"`
	OS         string  `json:"os"`
	IP         string  `json:"ip"`
	Role       string  `json:"role"`
	State      string  `json:"state"`
	MaxMemMB   int     `json:"maxMemoryMB"`
	UsedMemMB  int     `json:"usedMemoryMB"`
	CPUs       int     `json:"cpus"`
	DiskPath   string  `json:"diskPath"`
	DiskSizeGB float64 `json:"diskSizeGB"`
}

type APIResponse struct {
	OK    bool   `json:"ok,omitempty"`
	Error string `json:"error,omitempty"`
}

type SnapshotList struct {
	Snapshots []string `json:"snapshots"`
}

// ---------------------------------------------------------------------------
// Global state
// ---------------------------------------------------------------------------

var (
	opMu    sync.Mutex
	webRoot string
)

// ---------------------------------------------------------------------------
// virsh helpers
// ---------------------------------------------------------------------------

func runVirsh(args ...string) (string, error) {
	cmd := exec.Command("virsh", args...)
	cmd.Env = append(os.Environ(), "LIBVIRT_DEFAULT_URI=qemu:///system")
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// parseVirshList returns map[vmName]state from "virsh list --all"
func parseVirshList() map[string]string {
	out, err := runVirsh("list", "--all")
	if err != nil {
		return map[string]string{}
	}
	result := map[string]string{}
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		// Lines look like: " 1   kali-attacker   running" or "-   ubuntu24   shut off"
		if len(fields) < 3 {
			continue
		}
		// First field is ID (number or "-"), second is name, rest is state
		name := fields[1]
		state := strings.Join(fields[2:], " ")
		result[name] = state
	}
	return result
}

// parseDominfo returns maxMemMB, usedMemMB, cpus from "virsh dominfo <name>"
func parseDominfo(name string) (maxMem, usedMem, cpus int) {
	out, err := runVirsh("dominfo", name)
	if err != nil {
		return 0, 0, 0
	}
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		switch key {
		case "Max memory":
			// Value is like "4194304 KiB"
			fields := strings.Fields(val)
			if len(fields) > 0 {
				kb, _ := strconv.Atoi(fields[0])
				maxMem = kb / 1024
			}
		case "Used memory":
			fields := strings.Fields(val)
			if len(fields) > 0 {
				kb, _ := strconv.Atoi(fields[0])
				usedMem = kb / 1024
			}
		case "CPU(s)":
			cpus, _ = strconv.Atoi(val)
		}
	}
	return
}

// parseDiskSize extracts the primary disk path from dumpxml and stats the file
type domainXML struct {
	Devices struct {
		Disks []struct {
			Device string `xml:"device,attr"`
			Source struct {
				File string `xml:"file,attr"`
			} `xml:"source"`
		} `xml:"disk"`
	} `xml:"devices"`
}

func parseDiskSize(name string) (path string, sizeGB float64) {
	out, err := runVirsh("dumpxml", name)
	if err != nil {
		return "", 0
	}
	var dom domainXML
	if err := xml.Unmarshal([]byte(out), &dom); err != nil {
		return "", 0
	}
	for _, d := range dom.Devices.Disks {
		if d.Device == "disk" && d.Source.File != "" {
			path = d.Source.File
			info, err := os.Stat(path)
			if err == nil {
				sizeGB = float64(info.Size()) / (1024 * 1024 * 1024)
			}
			return path, sizeGB
		}
	}
	return "", 0
}

// shutdownTimeout returns how long to wait for a VM to reach shut off state.
func shutdownTimeout(name string) time.Duration {
	if name == "windows10" {
		return 120 * time.Second
	}
	return 60 * time.Second
}

// waitShutOff polls until the VM reaches "shut off" state or the timeout elapses.
func waitShutOff(name string, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		time.Sleep(2 * time.Second)
		states := parseVirshList()
		if states[name] == "shut off" {
			return true
		}
	}
	return false
}

// shutdownIfNeeded shuts down the VM when it is running or paused, then waits
// for it to reach "shut off". Returns an error string on failure (empty = OK).
func shutdownIfNeeded(name string) string {
	states := parseVirshList()
	state := states[name]
	if state == "shut off" {
		return ""
	}
	if state != "running" && state != "paused" {
		if state == "" {
			state = "unknown"
		}
		return fmt.Sprintf("VM is in state %q — cannot auto-shutdown", state)
	}
	opMu.Lock()
	out, err := runVirsh("shutdown", name)
	opMu.Unlock()
	if err != nil {
		return "shutdown failed: " + out
	}
	if !waitShutOff(name, shutdownTimeout(name)) {
		return "VM did not shut off within timeout"
	}
	return ""
}

// parseSnapshotList returns snapshot names for a VM
func parseSnapshotList(name string) []string {
	out, err := runVirsh("snapshot-list", name, "--name")
	if err != nil {
		return []string{}
	}
	var snaps []string
	for _, line := range strings.Split(out, "\n") {
		s := strings.TrimSpace(line)
		if s != "" {
			snaps = append(snaps, s)
		}
	}
	return snaps
}

// ---------------------------------------------------------------------------
// API handlers
// ---------------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func handleVMList(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/api/vms" {
		http.NotFound(w, r)
		return
	}
	states := parseVirshList()
	var result []VMStatus
	for _, cfg := range vmCatalog {
		state := states[cfg.Name]
		if state == "" {
			state = "unknown"
		}
		maxMem, usedMem, cpus := parseDominfo(cfg.Name)
		diskPath, diskSize := parseDiskSize(cfg.Name)
		result = append(result, VMStatus{
			Name:       cfg.Name,
			OS:         cfg.OS,
			IP:         cfg.IP,
			Role:       cfg.Role,
			State:      state,
			MaxMemMB:   maxMem,
			UsedMemMB:  usedMem,
			CPUs:       cpus,
			DiskPath:   diskPath,
			DiskSizeGB: diskSize,
		})
	}
	writeJSON(w, http.StatusOK, result)
}

func handleSnapshots(w http.ResponseWriter, name string) {
	snaps := parseSnapshotList(name)
	if snaps == nil {
		snaps = []string{}
	}
	writeJSON(w, http.StatusOK, SnapshotList{Snapshots: snaps})
}

func handleStart(w http.ResponseWriter, name string) {
	opMu.Lock()
	defer opMu.Unlock()
	out, err := runVirsh("start", name)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: out})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleShutdown(w http.ResponseWriter, name string) {
	opMu.Lock()
	defer opMu.Unlock()
	out, err := runVirsh("shutdown", name)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: out})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleDestroy(w http.ResponseWriter, name string) {
	opMu.Lock()
	defer opMu.Unlock()
	out, err := runVirsh("destroy", name)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: out})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleSnapshotRevert(w http.ResponseWriter, r *http.Request, name string) {
	var body struct {
		Snapshot string `json:"snapshot"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Snapshot == "" {
		writeJSON(w, http.StatusBadRequest, APIResponse{Error: "snapshot name required"})
		return
	}
	if errMsg := shutdownIfNeeded(name); errMsg != "" {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: errMsg})
		return
	}
	opMu.Lock()
	defer opMu.Unlock()
	out, err := runVirsh("snapshot-revert", name, body.Snapshot)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: out})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleSnapshotCreate(w http.ResponseWriter, r *http.Request, name string) {
	var body struct {
		Name string `json:"name"`
		Desc string `json:"desc"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Name == "" {
		writeJSON(w, http.StatusBadRequest, APIResponse{Error: "snapshot name required"})
		return
	}
	// Guard: VM must be shut off (caller must have already shut down the VM)
	states := parseVirshList()
	state := states[name]
	if state == "" {
		state = "unknown"
	}
	if state != "shut off" {
		writeJSON(w, http.StatusConflict, APIResponse{Error: "VM must be shut off before taking a snapshot (current state: " + state + ")"})
		return
	}
	opMu.Lock()
	defer opMu.Unlock()
	desc := body.Desc
	if desc == "" {
		desc = fmt.Sprintf("Snapshot created %s", time.Now().Format("2006-01-02 15:04:05"))
	}
	out, err := runVirsh("snapshot-create-as", name, body.Name, desc)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: out})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleSnapshotDelete(w http.ResponseWriter, r *http.Request, name string) {
	var body struct {
		Snapshot string `json:"snapshot"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Snapshot == "" {
		writeJSON(w, http.StatusBadRequest, APIResponse{Error: "snapshot name required"})
		return
	}
	opMu.Lock()
	defer opMu.Unlock()
	out, err := runVirsh("snapshot-delete", name, body.Snapshot)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: out})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleRevertAll(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Snapshot string `json:"snapshot"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Snapshot == "" {
		writeJSON(w, http.StatusBadRequest, APIResponse{Error: "snapshot name required"})
		return
	}

	// Phase 1: Issue shutdown to all running/paused VMs simultaneously
	states := parseVirshList()
	for _, cfg := range vmCatalog {
		s := states[cfg.Name]
		if s == "running" || s == "paused" {
			opMu.Lock()
			runVirsh("shutdown", cfg.Name)
			opMu.Unlock()
		}
	}

	// Phase 2: Wait for all VMs to reach shut off (use the longest timeout)
	deadline := time.Now().Add(150 * time.Second)
	for time.Now().Before(deadline) {
		states = parseVirshList()
		allOff := true
		for _, cfg := range vmCatalog {
			s := states[cfg.Name]
			if s != "shut off" && s != "" && s != "unknown" {
				allOff = false
				break
			}
		}
		if allOff {
			break
		}
		time.Sleep(2 * time.Second)
	}

	// Phase 3: Revert each VM; collect any errors
	opMu.Lock()
	defer opMu.Unlock()
	var errs []string
	for _, cfg := range vmCatalog {
		out, err := runVirsh("snapshot-revert", cfg.Name, body.Snapshot)
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %s", cfg.Name, strings.TrimSpace(out)))
		}
	}
	if len(errs) > 0 {
		writeJSON(w, http.StatusInternalServerError, APIResponse{Error: strings.Join(errs, " | ")})
		return
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleStartAll(w http.ResponseWriter, r *http.Request) {
	opMu.Lock()
	defer opMu.Unlock()
	for _, cfg := range vmCatalog {
		runVirsh("start", cfg.Name) //nolint — already-running VMs return error, that's fine
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

func handleStopAll(w http.ResponseWriter, r *http.Request) {
	opMu.Lock()
	defer opMu.Unlock()
	for _, cfg := range vmCatalog {
		runVirsh("shutdown", cfg.Name)
	}
	writeJSON(w, http.StatusOK, APIResponse{OK: true})
}

// handleVMDispatch handles /api/vm/{name}/... routes
func handleVMDispatch(w http.ResponseWriter, r *http.Request) {
	// Path: /api/vm/{name}/{action...}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/vm/"), "/")
	if len(parts) < 2 {
		http.NotFound(w, r)
		return
	}
	name := parts[0]

	// Validate VM name
	valid := false
	for _, cfg := range vmCatalog {
		if cfg.Name == name {
			valid = true
			break
		}
	}
	if !valid {
		writeJSON(w, http.StatusNotFound, APIResponse{Error: "unknown VM: " + name})
		return
	}

	action := strings.Join(parts[1:], "/")

	switch action {
	case "snapshots":
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handleSnapshots(w, name)
	case "start":
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handleStart(w, name)
	case "shutdown":
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handleShutdown(w, name)
	case "destroy":
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handleDestroy(w, name)
	case "snapshot/revert":
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handleSnapshotRevert(w, r, name)
	case "snapshot/create":
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handleSnapshotCreate(w, r, name)
	case "snapshot/delete":
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handleSnapshotDelete(w, r, name)
	default:
		http.NotFound(w, r)
	}
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	port := flag.Int("port", 8082, "port to listen on")
	web := flag.String("web", "./web", "path to web/ directory containing index.html")
	flag.Parse()

	webRoot = *web

	mux := http.NewServeMux()

	// Bulk VM actions (must be registered before /api/vm/ catch-all)
	mux.HandleFunc("/api/vms/start-all", handleStartAll)
	mux.HandleFunc("/api/vms/stop-all", handleStopAll)
	mux.HandleFunc("/api/vms/revert-all", handleRevertAll)

	// VM list
	mux.HandleFunc("/api/vms", handleVMList)

	// Per-VM actions
	mux.HandleFunc("/api/vm/", handleVMDispatch)

	// Health
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Static files (CSS, JS) — serve from web/ directory
	mux.HandleFunc("/network_map.css", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, filepath.Join(webRoot, "network_map.css"))
	})
	mux.HandleFunc("/network_map.js", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, filepath.Join(webRoot, "network_map.js"))
	})

	// Frontend — serve index.html for all other paths
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, filepath.Join(webRoot, "index.html"))
	})

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Null Harbor GUI listening on http://localhost%s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
