#!/usr/bin/bash

# Copies a local file to a remote host via the saffron agent, then runs
# checkfile.bash at the destination path to confirm the file is present.

# Usage:  copytoremote.bash hostname local_file [remote_dest_path] [checkfile_timeout_seconds]
# Example: copytoremote.bash hn-wks-01 ./myfile.txt /tmp/myfile.txt 10
# Example: copytoremote.bash hn-wks-01 ./myfile.txt /tmp/
# (If remote_dest_path is omitted, the file is written under the remote agent's
#  current directory using the local filename. If it ends with / or \, the
#  local filename is appended. checkfile_timeout_seconds defaults to 10.)

# Author: Duane Dunston

if [[ -z "${1}" || -z "${2}" ]]; then
    echo ""
    echo "Usage: copytoremote.bash hostname local_file [remote_dest_path] [checkfile_timeout_seconds]"
    echo ""
    echo 'Example: copytoremote.bash hn-wks-01 ./myfile.txt /tmp/myfile.txt 10'
    echo 'Example: copytoremote.bash hn-wks-01 ./myfile.txt /tmp/'
    echo ""
    echo "Copies the local file to the remote host, then runs checkfile.bash at the destination."
    echo ""
    exit 1
fi

HOSTNAME="${1}"
LOCAL_FILE="${2}"
REMOTE_PATH="${3}"
CHECKFILE_TIMEOUT="${4:-10}"

if [[ ! -f "${LOCAL_FILE}" ]]; then
    echo "Error: Local file not found: ${LOCAL_FILE}"
    exit 1
fi

COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Build form args: hostname and file are required; path is optional
CURL_ARGS=(-X POST "${COMMANDLY_SERVER}/api/upload" -F "hostname=${HOSTNAME}" -F "file=@${LOCAL_FILE}")
[[ -n "${REMOTE_PATH}" ]] && CURL_ARGS+=(-F "path=${REMOTE_PATH}")

RESPONSE=$(curl -s "${CURL_ARGS[@]}")

SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

if [[ "${SUCCESS}" != "true" ]]; then
    echo "Error: Upload failed"
    echo "${MESSAGE}"
    exit 1
fi

# Extract destination path from message "File uploaded successfully to <path>"
REMOTE_FILE="${MESSAGE#File uploaded successfully to }"
if [[ "${REMOTE_FILE}" == "${MESSAGE}" ]]; then
    # Fallback if message format changes: use remote path or basename
    REMOTE_FILE="${REMOTE_PATH:-$(basename "${LOCAL_FILE}")}"
else
    # Unescape JSON backslashes (e.g. Windows paths)
    REMOTE_FILE=$(echo -e "${REMOTE_FILE}")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKFILE_SCRIPT="${SCRIPT_DIR}/checkfile.bash"
if [[ ! -f "${CHECKFILE_SCRIPT}" ]]; then
    echo "Upload succeeded. Warning: checkfile.bash not found, skipping check."
    echo "${MESSAGE}"
    exit 0
fi

"${CHECKFILE_SCRIPT}" "${HOSTNAME}" "${REMOTE_FILE}" "${CHECKFILE_TIMEOUT}"
