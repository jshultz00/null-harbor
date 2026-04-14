#!/usr/bin/bash

# Updates a remote config file by key: for each line in the local file, finds the
# line in the remote file with the same config key (text before the first '=')
# and replaces it, or appends the line if the key is not found. Uses the server's
# /api/upload endpoint with patch=replace. If the remote file does not exist, it
# is created with the uploaded content.

# Usage:  replace.bash hostname local_file [remote_dest_path]
# Example: replace.bash hn-wks-01 ./overrides.conf /etc/apache2/apache.conf
# Example: replace.bash hn-wks-01 ./config.ini /opt/app/config.ini
# (The local file should contain key=value lines, one per setting to update or add.
#  If remote_dest_path is omitted, the remote path is the local filename in the
#  remote agent's current directory.)

# Author: Duane Dunston

if [[ -z "${1}" || -z "${2}" ]]; then
    echo ""
    echo "Usage: replace.bash hostname local_file [remote_dest_path]"
    echo ""
    echo "Example: replace.bash hn-wks-01 ./overrides.conf /etc/apache2/apache.conf"
    echo ""
    echo "Updates the remote file by config key: matching lines are replaced, new keys are appended."
    echo "The local file should contain key=value lines (e.g. port = 8080)."
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

CURL_ARGS=(-X POST "${COMMANDLY_SERVER}/api/upload" -F "hostname=${HOSTNAME}" -F "file=@${LOCAL_PATH}" -F "patch=replace")
[[ -n "${REMOTE_PATH}" ]] && CURL_ARGS+=(-F "path=${REMOTE_PATH}")

RESPONSE=$(curl -s "${CURL_ARGS[@]}")

if [[ -z "${RESPONSE}" ]]; then
    echo "Error: no response from server"
    exit 1
fi

SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

if [[ "${SUCCESS}" != "true" ]]; then
    echo "Error: replace failed"
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
