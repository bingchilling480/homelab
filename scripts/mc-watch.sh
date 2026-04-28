#!/bin/bash
# Wait for Minecraft Java process to disappear
while true; do
    if ! docker exec crafty pgrep -f "paper.jar" > /dev/null 2>&1; then
        # MC is not running, check if it was running before
        if [ -f /tmp/mc-was-running ]; then
            rm /tmp/mc-was-running
            sleep 30  # Wait for server to fully stop
            /usr/local/bin/reset-swap.sh
        fi
    else
        touch /tmp/mc-was-running
    fi
    sleep 10
done
