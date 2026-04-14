#!/usr/bin/bash

# Tells the agent to upload a file or directory from the client to the server.
# The agent reads the path locally (file or directory), packages directories as .zip,
# and POSTs to the server. Uses the uploadFromClient command.

# Usage:  upload.bash hostname path_on_client path_on_server
# Example: upload.bash hn-wks-01 /tmp/report.txt reports
# Example: upload.bash hn-wks-01 /var/log/myapp reports/2024

# Author: Duane Dunston

if [[ -z "${1}" || -z "${2}" || -z "${3}" ]]; then
    echo ""
    echo "Usage: upload.bash hostname path_on_client path_on_server"
    echo ""
    echo "Example: upload.bash hn-wks-01 /tmp/report.txt reports"
    echo "Example: upload.bash hn-wks-01 /var/log/myapp reports/2024"
    echo ""
    echo "  path_on_client  - path to file or directory on the agent"
    echo "  path_on_server  - subdir under server uploads/<hostname>/ (e.g. reports or reports/2024)"
    echo ""
    exit 1
fi

COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"
HOSTNAME="${1}"
PATH_ON_CLIENT="${2}"
PATH_ON_SERVER="${3}"

# Escape for JSON: backslash and double quote
PATH_ESCAPED=$(printf '%s' "${PATH_ON_CLIENT}" | sed 's/\\/\\\\/g; s/"/\\"/g')
PATH_SERVER_ESCAPED=$(printf '%s' "${PATH_ON_SERVER}" | sed 's/\\/\\\\/g; s/"/\\"/g')
JSON_PAYLOAD=$(printf '{"hostname":"%s","key":"uploadFromClient","value":"%s","filePath":"%s"}' "${HOSTNAME}" "${PATH_ESCAPED}" "${PATH_SERVER_ESCAPED}")

RESPONSE=$(curl -s -X POST "${COMMANDLY_SERVER}/api/command" \
    -H "Content-Type: application/json" \
    -d "${JSON_PAYLOAD}")

if [[ -z "${RESPONSE}" ]]; then
    echo "Error: no response from server"
    exit 1
fi

SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

if [[ "${SUCCESS}" != "true" ]]; then
    echo "Error: upload failed"
    if [[ -n "${MESSAGE}" ]]; then
        echo -e "${MESSAGE}"
    else
        echo "${RESPONSE}"
    fi
    exit 1
fi

if [[ -n "${MESSAGE}" ]]; then
    echo -e "${MESSAGE}"
fi
exit 0
