#!/usr/bin/bash

# Appends a local file to a remote file via the saffron agent (patch/append mode).
# Uses the server's /api/upload endpoint with patch=append. If the remote file
# does not exist, it is created with the uploaded content.

# Usage:  patch.bash hostname local_file [remote_dest_path]
# Example: patch.bash hn-wks-01 ./extra.conf /etc/apache2/apache.conf
# Example: patch.bash hn-wks-01 ./snippet.txt /tmp/log.txt
# (If remote_dest_path is omitted, the content is appended to a file with the
#  local filename in the remote agent's current directory.)

# Author: Duane Dunston

if [[ -z "${1}" || -z "${2}" ]]; then
    echo ""
    echo "Usage: patch.bash hostname local_file [remote_dest_path]"
    echo ""
    echo "Example: patch.bash hn-wks-01 ./extra.conf /etc/apache2/apache.conf"
    echo ""
    echo "Appends the local file to the remote file. Creates the remote file if it does not exist."
    echo ""
    exit 1
fi

HOSTNAME="${1}"
LOCAL_PATH="${2}"
REMOTE_PATH="${3}"

if [[ ! -f "${LOCAL_PATH}" ]]; then
    echo "Error: Local file not found: ${LOCAL_PATH}"
    exit 1
fi

COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

CURL_ARGS=(-X POST "${COMMANDLY_SERVER}/api/upload" -F "hostname=${HOSTNAME}" -F "file=@${LOCAL_PATH}" -F "patch=append")
[[ -n "${REMOTE_PATH}" ]] && CURL_ARGS+=(-F "path=${REMOTE_PATH}")

RESPONSE=$(curl -s "${CURL_ARGS[@]}")

if [[ -z "${RESPONSE}" ]]; then
    echo "Error: no response from server"
    exit 1
fi

SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

if [[ "${SUCCESS}" != "true" ]]; then
    echo "Error: patch (append) failed"
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
