#!/bin/bash
swapoff /dev/zram0
echo 1 > /sys/block/zram0/reset
# Let zram-generator reinitialize it
systemctl restart systemd-zram-setup@zram0.service
