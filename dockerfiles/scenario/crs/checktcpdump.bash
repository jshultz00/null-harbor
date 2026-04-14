#!/usr/bin/bash

# Checks to see if a network connection exists on the c2 server.
# Used for scenario development to see if a RAT is connected
# before moving on to the next step in the automation of the
# attack.

# Usage:  checktcpdump.bash 1.1.1.1:38000 4 5"
# The command above will check if port 38000 listening on 1.1.1.1 has sent 4 packets to show the RAT connected every 5 seconds.

# Author: Duane Dunston

if [[ "${1}" == "" || "${2}" == "" ]]; then

        echo ""
        echo "Usage: checktcpdump IP Port Number_of_Packets seconds_to_sleep"
        echo ""
        echo "Example: checktcpdump.bash 1.1.1.1 38000 4 5"
        echo ""
        echo "The command above will check if port 38000 listening on 1.1.1.1 has sent 4 packets to show the RAT connected every 5 seconds."
        echo ""
        exit 1

fi

# Run in a loop every number of seconds specified on the commandline.
while [[ true ]]; do
        
        # Check if network connection is established with the RAT.
        
	#sudo tcpdump -n -i any | grep -E "${1}.${2}.* ack .*"
	sudo tcpdump -n -i any host ${1} and port ${2} -c ${3}

        if [[ $? -ne 0 ]]; then
        
                sleep ${4}
                echo "..."
		sudo pkill tcpdump
                continue

        else 

                echo "${1} network connection Established!"
                echo ""
                break
        
        fi

done
