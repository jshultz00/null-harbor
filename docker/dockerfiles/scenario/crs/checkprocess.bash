#!/usr/bin/bash

# Checks to see if a process is running on a host.
# This is used to determine if a command has completed running,
# before moving to the next command.

# Usage: checkprocess.bash HN-DC01 \"xcopy\" 10"
# The above command checks if xcopy is being executed on HN-DC01 and sleeps for 10 seconds
# and checks again until the command completes.

# Author: Duane Dunston

if [[ "${1}" == "" || "${2}" == "" || "${3}" == "" ]]; then

        echo ""
        echo "Usage: checkprocess.bash SALT_HOSTNAME \"search term\" seconds_to_sleep"
        echo ""
        echo "Example: checkprocess.bash HN-DC01 xcopy 10"
        echo ""
        echo "The command above will check if \"xcopy\" is running on HN-DC01. If so, it will sleep for 10 seconds and check again until it has completed."
        echo ""
        exit 1

fi

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Run in a loop every number of seconds specified on the commandline.
while [[ true ]]; do
        
        # Check if the process has completed executing.
        # The first variable ${1} is the hostname. ${2} is the process to search for on the host and ${3} is the time to sleep.
	# "None" will be returned if the process isn't running.
        RESPONSE=$(curl -s -X POST "${COMMANDLY_SERVER}/api/command" \
                -H "Content-Type: application/json" \
                -d "{\"hostname\":\"${1}\",\"key\":\"chkProcess\",\"value\":\"${2}\"}")
        
        # Parse JSON response to check if process is running
        # Commandly returns: {"id":"...","success":true/false,"message":"true"/"false"}
        # We need to match Salt's behavior: "None" if not running, otherwise process info
        SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
        MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        
        # If success is false or message is "false", treat as "None" (process not running)
        if [[ "${SUCCESS}" == "false" ]] || [[ "${MESSAGE}" == "false" ]]; then
        
                sleep ${3}
                echo "..."
                continue

        else 

                echo "${1} is running."
		sleep 2
                echo ""
                break
        
        fi

done
