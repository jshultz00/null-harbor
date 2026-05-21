#!/usr/bin/bash

# Checks to see if a file exists on the remote system.
# Used for scenario development to see if an artifact exists
# before moving on to the next step in the automation of the
# attack.

# Usage:  checkfile.bash hn-wks-01 "c:\Program Files\feefee.exe" 10
# The above command checks if c:\Program Files\feefee.exe exists on
# hn-wks-01 every 10 seconds before continuing to run.

# Author: Duane Dunston

if [[ -z "${1}" || -z "${2}" || -z "${3}" ]]; then
    echo ""
    echo "Usage: checkFile hostname filename seconds_to_sleep"
    echo ""
    echo 'Example: checkfile.bash hn-wks-01 "c:\Program Files\feefee.exe" 10'
    echo ""
    echo "The command above will check for the file c:\Program Files\feefee.exe on hn-wks-01 every 10 seconds."
    echo ""
    exit 1
fi

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Run in a loop every number of seconds specified on the commandline.
while true; do
    # Check if file exists on the host.
    # The first variable ${1} is the host and ${2} is the filename.
    # Use printf to properly escape JSON values
    JSON_PAYLOAD=$(printf '{"hostname":"%s","key":"file","value":"%s"}' \
            "$(printf '%s' "${1}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$(printf '%s' "${2}" | sed 's/\\/\\\\/g; s/"/\\"/g')")
    RESPONSE=$(curl -s -X POST "${COMMANDLY_SERVER}/api/command" \
            -H "Content-Type: application/json" \
            -d "${JSON_PAYLOAD}")
    
    # Parse JSON response - Salt returns "True" if file exists, commandly returns {"success":true,"message":"true"}
    SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
    MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    
    # Check if file exists (success is true and message is "true")
    if [[ "${SUCCESS}" != "true" ]] || [[ "${MESSAGE}" != "true" ]]; then
        sleep "${3}"
        echo "..."
        continue
    else
        echo "${2} Found!"
        echo ""
        break
    fi
done
