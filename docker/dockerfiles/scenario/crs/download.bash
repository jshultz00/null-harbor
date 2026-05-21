#!/usr/bin/bash

# Copies a local file or directory to a remote host (client) via the saffron agent.
# Sends the file(s) to the agent using the server's /api/upload endpoint.

# Usage:  download.bash hostname local_path [remote_dest_path]
# Example: download.bash hn-wks-01 ./myfile.txt /tmp/myfile.txt
# Example: download.bash hn-wks-01 ./myfile.txt /tmp/
# Example: download.bash hn-wks-01 ./mydir /tmp/
# (If remote_dest_path is omitted, files go under the agent's current directory.
#  For a directory, the directory name is preserved under the remote path.)

# Author: Duane Dunston

if [[ -z "${1}" || -z "${2}" ]]; then
    echo ""
    echo "Usage: download.bash hostname local_path [remote_dest_path]"
    echo ""
    echo "Example: download.bash hn-wks-01 ./myfile.txt /tmp/myfile.txt"
    echo "Example: download.bash hn-wks-01 ./myfile.txt /tmp/"
    echo "Example: download.bash hn-wks-01 ./mydir /tmp/"
    echo ""
    echo "Copies the local file or directory to the remote host."
    echo ""
    exit 1
fi

HOSTNAME="${1}"
LOCAL_PATH="${2}"
REMOTE_PATH="${3}"

if [[ ! -f "${LOCAL_PATH}" && ! -d "${LOCAL_PATH}" ]]; then
    echo "Error: Local path not found: ${LOCAL_PATH}"
    exit 1
fi

COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

upload_one() {
    local local_file="$1"
    local remote_path="$2"
    local CURL_ARGS=(-X POST "${COMMANDLY_SERVER}/api/upload" -F "hostname=${HOSTNAME}" -F "file=@${local_file}" -F "path=${remote_path}")
    local RESPONSE
    RESPONSE=$(curl -s "${CURL_ARGS[@]}")
    if [[ -z "${RESPONSE}" ]]; then
        echo "Error: no response from server"
        return 1
    fi
    local SUCCESS
    SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
    if [[ "${SUCCESS}" != "true" ]]; then
        local MESSAGE
        MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        echo "Error: upload failed for ${local_file}"
        [[ -n "${MESSAGE}" ]] && echo -e "${MESSAGE}"
        return 1
    fi
    return 0
}

if [[ -f "${LOCAL_PATH}" ]]; then
    CURL_ARGS=(-X POST "${COMMANDLY_SERVER}/api/upload" -F "hostname=${HOSTNAME}" -F "file=@${LOCAL_PATH}")
    [[ -n "${REMOTE_PATH}" ]] && CURL_ARGS+=(-F "path=${REMOTE_PATH}")
    RESPONSE=$(curl -s "${CURL_ARGS[@]}")
    if [[ -z "${RESPONSE}" ]]; then
        echo "Error: no response from server"
        exit 1
    fi
    SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
    MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    if [[ "${SUCCESS}" != "true" ]]; then
        echo "Error: download failed"
        [[ -n "${MESSAGE}" ]] && echo -e "${MESSAGE}"
        exit 1
    fi
    [[ -n "${MESSAGE}" ]] && echo -e "${MESSAGE}"
    exit 0
fi

# Directory: upload each file, preserving structure
LOCAL_DIR="${LOCAL_PATH%/}"
DIR_BASE=$(basename "${LOCAL_DIR}")
REMOTE_BASE="${REMOTE_PATH:+${REMOTE_PATH%/}/}${DIR_BASE}"
FAILED=0
while IFS= read -r -d '' f; do
    rel="${f#"${LOCAL_DIR}/"}"
    dest="${REMOTE_BASE}/${rel}"
    if ! upload_one "$f" "$dest"; then
        FAILED=1
    fi
done < <(find "${LOCAL_DIR}" -type f -print0)
exit $FAILED
