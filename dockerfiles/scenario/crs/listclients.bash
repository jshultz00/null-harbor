#!/usr/bin/bash

# Lists all connected clients from the saffron server.
# Used to see which hosts are currently available for commands.

# Usage:  listclients.bash
# This will display all connected client hostnames.

# Author: Duane Dunston

# Get commandly server address from environment or use default
COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.100.100.47:50200}"

# Get the list of connected clients
RESPONSE=$(curl -s -X GET "${COMMANDLY_SERVER}/api/clients")

# Check if we got a response
if [[ -z "${RESPONSE}" ]]; then
    echo "Error: No response from server"
    exit 1
fi

# Parse and display the client list
# The response is a JSON array with objects containing "hostname" field
echo "Connected Clients:"
echo "${RESPONSE}" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4 | nl
