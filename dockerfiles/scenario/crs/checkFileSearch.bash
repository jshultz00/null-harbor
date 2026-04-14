#!/usr/bin/bash

# Checks to see if a file contains a string.
# Used for scenario development to see if a string exists in a file
# before moving on to the next step in the automation of the attack.

# Usage:  checkFileSearch.bash web03 /etc/passwd bash 10"
# The above command checks if the file /etc/passwd contains the strings "bash"
# on web03 every 10 seconds before continuing to run.

# Author: Duane Dunston

if [[ "${1}" == "" || "${2}" == "" || "${3}" == "" || "${4}" == "" ]]; then

        echo ""
        echo "Usage: checkFileSearch.bash hostname filename string seconds_to_sleep"
        echo ""
	echo "Example:  checkFileSearch.bash web03 /etc/passwd bash 10"
        echo ""
	echo "The above command checks if the file /etc/passwd contains the strings \"bash\""
	echo "on web03 every 10 seconds before continuing to run."
        exit 1

fi

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Run in a loop every number of seconds specified on the commandline.
while [[ true ]]; do
        
        # Check if file contains the string on the host.
        # The first variable ${1} is the host, ${2} is the filename, and ${3} is the search string.
        # Use printf to properly escape JSON values
        JSON_PAYLOAD=$(printf '{"hostname":"%s","key":"fSearch","value":"%s","pattern":"%s"}' \
                "$(printf '%s' "${1}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
                "$(printf '%s' "${2}" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
                "$(printf '%s' "${3}" | sed 's/\\/\\\\/g; s/"/\\"/g')")
        RESPONSE=$(curl -s -X POST "${COMMANDLY_SERVER}/api/command" \
                -H "Content-Type: application/json" \
                -d "${JSON_PAYLOAD}")
        
        # Parse JSON response - Salt returns "True" if found, commandly returns {"success":true,"message":"true"}
        SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
        MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        
        # Check if pattern was found (success is true and message is "true")
        if [[ "${SUCCESS}" != "true" ]] || [[ "${MESSAGE}" != "true" ]]; then
        
                sleep ${4}
                echo "..."
                continue

        else 

                echo "${3} Found!"
                echo ""
                break
        
        fi

done
