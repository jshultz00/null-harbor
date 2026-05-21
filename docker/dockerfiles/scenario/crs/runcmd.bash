#!/usr/bin/bash

# Executes a command on the remote system via the saffron agent.
# Used for scenario development to run commands on remote hosts.

# Usage:  runcmd.bash hn-wks-01 "ls -la /tmp"
# The above command executes "ls -la /tmp" on hn-wks-01 and returns the output.

# Author: Duane Dunston

if [[ -z "${1}" || -z "${2}" ]]; then
    echo ""
    echo "Usage: runcmd.bash hostname command [runAsUser] [runAsPassword] [runAsDomain]"
    echo ""
    echo 'Example: runcmd.bash hn-wks-01 "ls -la /tmp"'
    echo 'Example with run-as: runcmd.bash hn-wks-01 "whoami" myuser mypassword'
    echo ""
    echo "The command above will execute on hn-wks-01. Optional run-as args run the command as another user (Windows: use CreateProcessWithLogonW; Linux: setuid)."
    echo ""
    exit 1
fi

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Optional run-as: runAsUser (3), runAsPassword (4), runAsDomain (5)
RUNAS_JSON=""
if [[ -n "${3}" ]]; then
    RUNAS_ESCAPED=$(printf '%s' "${3}" | sed 's/\\/\\\\/g; s/"/\\"/g')
    RUNAS_JSON=",\"runAsUser\":\"${RUNAS_ESCAPED}\""
    if [[ -n "${4}" ]]; then
        PASS_ESCAPED=$(printf '%s' "${4}" | sed 's/\\/\\\\/g; s/"/\\"/g')
        RUNAS_JSON="${RUNAS_JSON},\"runAsPassword\":\"${PASS_ESCAPED}\""
    fi
    if [[ -n "${5}" ]]; then
        DOMAIN_ESCAPED=$(printf '%s' "${5}" | sed 's/\\/\\\\/g; s/"/\\"/g')
        RUNAS_JSON="${RUNAS_JSON},\"runAsDomain\":\"${DOMAIN_ESCAPED}\""
    fi
fi

# Execute the command on the host.
# The first variable ${1} is the host and ${2} is the command.
# Use printf to properly escape JSON values
JSON_PAYLOAD=$(printf '{"hostname":"%s","key":"cmd","value":"%s","debug":"true"%s}' \
        "$(printf '%s' "${1}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
        "$(printf '%s' "${2}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
        "${RUNAS_JSON}")
RESPONSE=$(curl -s -X POST "${COMMANDLY_SERVER}/api/command" \
        --max-time 0 \
        -H "Content-Type: application/json" \
        -d "${JSON_PAYLOAD}")

# Parse JSON response
SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

# Check if command executed successfully
if [[ "${SUCCESS}" != "true" ]]; then
    echo "Error executing command on ${1}"
    echo "Response: ${RESPONSE}"
    exit 1
else
    # Decode escaped characters in the message
    echo -e "${MESSAGE}"
    exit 0
fi
