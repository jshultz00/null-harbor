#!/usr/bin/bash

# Interactive shell for remote hosts via saffron agent.
# Provides a terminal-like experience with history and color output.
#
# Usage: shell.bash hostname
# Example: shell.bash hn-wks-01
#
# Author: Duane Dunston

# Color codes
COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[0;33m'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNCMD_SCRIPT="${SCRIPT_DIR}/runcmd.bash"

# Check if runcmd.bash exists
if [[ ! -f "${RUNCMD_SCRIPT}" ]]; then
    echo -e "${COLOR_RED}Error: runcmd.bash not found at ${RUNCMD_SCRIPT}${COLOR_RESET}"
    exit 1
fi

# Check arguments
if [[ -z "${1}" ]]; then
    echo ""
    echo "Usage: shell.bash hostname"
    echo ""
    echo "Example: shell.bash hn-wks-01"
    echo ""
    echo "Provides an interactive shell session on the remote host."
    echo ""
    exit 1
fi

HOSTNAME="${1}"

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# History file
HISTORY_FILE="${HOME}/.shell_history_${HOSTNAME}"
HISTORY_SIZE=1000

# Load command history if it exists
if [[ -f "${HISTORY_FILE}" ]]; then
    history -r "${HISTORY_FILE}"
fi

# Function to execute command and handle output
execute_remote_command() {
    local cmd="${1}"
    
    # Execute command directly
    local output
    local exit_code
    output=$("${RUNCMD_SCRIPT}" "${HOSTNAME}" "${cmd}" 2>&1)
    exit_code=$?
    
    # Display output
    if [[ ${exit_code} -eq 0 ]]; then
        if [[ -n "${output}" ]]; then
            echo -e "${output}"
        fi
        return 0
    else
        echo -e "${COLOR_RED}${output}${COLOR_RESET}"
        return 1
    fi
}

# Display welcome message
echo -e "${COLOR_GREEN}Connected to ${HOSTNAME}${COLOR_RESET}"
echo -e "${COLOR_BLUE}Type 'exit' or 'quit' to disconnect${COLOR_RESET}"
echo -e "${COLOR_YELLOW}Note: Each command runs independently. Use 'cd /path && command' for directory-specific operations.${COLOR_RESET}"
echo ""

# Main command loop
while true; do
    # Simple prompt
    prompt="${COLOR_GREEN}${HOSTNAME}${COLOR_RESET}\$ "
    
    # Read command with readline support (enables arrow keys, history)
    read -e -p "$(echo -e ${prompt})" cmd
    
    # Handle empty input
    [[ -z "${cmd}" ]] && continue
    
    # Add to history
    history -s "${cmd}"
    
    # Handle exit commands
    if [[ "${cmd}" == "exit" || "${cmd}" == "quit" ]]; then
        echo -e "${COLOR_YELLOW}Disconnecting from ${HOSTNAME}${COLOR_RESET}"
        break
    fi
    
    # Execute command
    execute_remote_command "${cmd}"
done

# Save command history
history -w "${HISTORY_FILE}" 2>/dev/null

# Trim history file to size limit
if [[ -f "${HISTORY_FILE}" ]]; then
    tail -n ${HISTORY_SIZE} "${HISTORY_FILE}" > "${HISTORY_FILE}.tmp" 2>/dev/null && \
    mv "${HISTORY_FILE}.tmp" "${HISTORY_FILE}" 2>/dev/null
fi

echo ""
echo -e "${COLOR_GREEN}Session ended${COLOR_RESET}"
