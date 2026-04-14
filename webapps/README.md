# webapps/ — Scenario-Swappable Web Application Content

This directory contains web application content that is volume-mounted into web server containers. Scenario phase scripts can modify or replace this content to simulate web attacks without rebuilding Docker images.

---

## Structure

```
webapps/
└── web01/        # Mounted at /var/www/html in web-lin (Apache)
```

Future expansion:
```
webapps/
├── web01/        # web-lin (Linux Apache)
└── web-win/      # web-win (IIS) — served from C:\inetpub\rangeweb inside VM
```

---

## web01/ — Default Content

Default content (pre-scenario): A static "SECURE Corp Internal Portal" page. No server-side functionality by default.

Scenario phases replace this content to introduce vulnerabilities:
- A PHP file upload form with no extension validation (webshell upload target)
- A login form with SQL injection vulnerability
- A server-side RCE endpoint (`/cgi-bin/` mod_cgi handler)

### Content Swap Example (Apache Mass Defacement Scenario)

```bash
# Phase script replaces index.html with defacement page
copytoremote.bash web-lin ./attacker_files/defacement.html /var/www/html/index.html

# Scenario reset restores original content
copytoremote.bash web-lin ./attacker_files/original-index.html /var/www/html/index.html
```

Because the directory is volume-mounted (not copied into the image), changes made by Saffron survive container restarts — this is intentional, simulating a persistent compromise.

---

## Content Mount Points

| Directory | Container | Mount Target |
|-----------|-----------|-------------|
| `webapps/web01/` | web-lin | `/var/www/html` |
