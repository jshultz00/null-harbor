#!/usr/bin/bash

# Checks to see if a network connection exists on the c2 server.
# Used for scenario development to see if a RAT is connected
# before moving on to the next step in the automation of the
# attack.

# Usage:  checknet.bash 1.1.1.1:38000 10"
# The abvoe command checks if port 38000 has an established
# connection on the c2 server.
# hn-wks-01 every 10 seconds before continuing to run.

# Author: Duane Dunston

if [[ "${1}" == "" || "${2}" == "" ]]; then

        echo ""
        echo "Usage: checknet IP:Port seconds_to_sleep"
        echo ""
        echo "Example: checknet.bash 1.1.1.1:38000 10"
        echo ""
        echo "The command above will check if port 38000 listening on 1.1.1.1 is ESTABLISHED every 10 seconds"
        echo ""
        exit 1

fi

# Run in a loop every number of seconds specified on the commandline.
while [[ true ]]; do
        
        # Check if network connection is established with the RAT.
        # The first variable ${1} is the IP and Port and ${2} is the number of seconds to sleep
        netstat -an |grep -E "${1}.*ESTABLISHED"
        
        if [[ $? -ne 0 ]]; then
        
                sleep ${2}
                echo "..."
                continue

        else 

                echo "${1} network connection Established!"
                echo ""
                break
        
        fi

done
