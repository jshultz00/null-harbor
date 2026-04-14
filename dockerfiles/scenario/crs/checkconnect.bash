#!/usr/bin/bash

# Checks to see if a network connection exists from a range
# VM to another host on the range
# Used for scenario development to see if an internal host
# before moving on to the next step in the automation of the
# attack.

# Usage:  checkconnect.bash 192.168.100.120:38000 10"
# The abvoe command checks if port 38000 has an established
# connection to 192.168.100.120 on port 38000 every 10 seconds

# Author: Duane Dunston

if [[ "${1}" == "" || "${2}" == "" || "${3}" == "" ]]; then

        echo ""
        echo "Usage: checkconnect.bash HOSTNAME IP:Port seconds_to_sleep"
        echo ""
        echo "Example: checkconnect.bash hn-wks-01 192.168.100.120:38000 10"
        echo ""
        echo "The command above will check if hn-wks-01 is connected to 192.168.100.120 port 38000 ESTABLISHED every 10 seconds"
        echo ""
        exit 1

fi

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Parse IP:Port from ${2}
IFS=':' read -r REMOTE_IP REMOTE_PORT <<< "${2}"

# Run in a loop every number of seconds specified on the commandline.
while [[ true ]]; do
        
        # Check if network connection is established to the range host.
        # The first variable ${1} is the host to check on. ${2} is the remote IP:Port the host must be connected to. ${3} is the number of seconds to sleep between checks.
        RESPONSE=$(curl -s -X POST "${COMMANDLY_SERVER}/api/command" \
                -H "Content-Type: application/json" \
                -d "{\"hostname\":\"${1}\",\"key\":\"clientConn\",\"host\":\"${REMOTE_IP}\",\"port\":\"${REMOTE_PORT}\"}")
        
        # Parse JSON response - commandly returns {"success":true/false,"message":"true"/"false"}
        SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
        MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        
        # Check if connection exists (success is true and message is "true")
        if [[ "${SUCCESS}" != "true" ]] || [[ "${MESSAGE}" != "true" ]]; then
        
                sleep ${3}
                echo "..."
                continue

        else 

                echo "${1} connected to ${2}!"
                echo ""
                break
        
        fi

done
