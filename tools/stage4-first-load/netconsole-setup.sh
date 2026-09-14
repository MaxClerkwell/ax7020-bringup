#!/bin/sh
# Runs ON THE BOARD. Points the kernel log at a host via dynamic netconsole.
# Usage: netconsole-setup.sh <board-ip> <host-ip> <host-mac>
set -e
BOARD_IP=$1; HOST_IP=$2; HOST_MAC=$3
[ -n "$HOST_MAC" ] || { echo "usage: $0 <board-ip> <host-ip> <host-mac>" >&2; exit 1; }
T=/sys/kernel/config/netconsole/host
mkdir -p "$T"; cd "$T"
# a target that is already enabled refuses field writes: disable it first
[ "$(cat enabled)" = 1 ] && echo 0 > enabled
# order matters: all fields first, enabled last
echo eth0       > dev_name
echo 6666       > local_port
echo 6666       > remote_port
echo "$BOARD_IP" > local_ip
echo "$HOST_IP"  > remote_ip
echo "$HOST_MAC" > remote_mac
echo 1          > enabled
echo "AX7020: netconsole test" > /dev/kmsg
