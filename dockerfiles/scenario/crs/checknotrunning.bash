#!/usr/bin/bash

# Script to check if a process is not running on a host.
# This is used to determine if a command has completed running,
# and only then proceed to the next step.

# Usage: checknotrunning.bash HN-DC01 "xcopy" 10
# The above command checks if xcopy is NOT being executed on HN-DC01 and sleeps for 10 seconds
# and checks again until the command has completed.

# Author: Justin Shultz

if [[ "${1}" == "" || "${2}" == "" || "${3}" == "" ]]; then
    echo ""
    echo "Usage: checknotrunning.bash SALT_HOSTNAME \"search term\" seconds_to_sleep"
    echo ""
    echo "Example: checkprocess_notrunning.bash HN-DC01 xcopy 10"
    echo ""
    echo "The command above will check if \"xcopy\" is NOT running on HN-DC01. If so, it will sleep for 10 seconds and check again until the process is no longer running."
    echo ""
    exit 1
fi

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Run in a loop every number of seconds specified on the command line.
while true; do
    # Check if the process is currently running.
    # The first variable ${1} is the hostname. ${2} is the process to search for on the host and ${3} is the time to sleep.
    # "None" will be returned if the process isn't found.
    RESPONSE=$(curl -s -X POST "${COMMANDLY_SERVER}/api/command" \
            -H "Content-Type: application/json" \
            -d "{\"hostname\":\"${1}\",\"key\":\"chkProcess\",\"value\":\"${2}\"}")
    
    # Parse JSON response to check if process is running
    # Commandly returns: {"id":"...","success":true/false,"message":"true"/"false"}
    # We need to match Salt's behavior: "None" if not running
    SUCCESS=$(echo "${RESPONSE}" | grep -o '"success":[^,}]*' | grep -o 'true\|false')
    MESSAGE=$(echo "${RESPONSE}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    
    # If success is false or message is "false", process is not running (matches "None" behavior)
    if [[ "${SUCCESS}" == "false" ]] || [[ "${MESSAGE}" == "false" ]]; then
        # Process is no longer running, exit the loop
        echo "${1}: Process \"${2}\" has completed."
        break
    else
        # Process is still running, so sleep for the specified time and check again
        echo "${1}: Process \"${2}\" is still running. Waiting for it to complete..."
        sleep ${3}
    fi
done
