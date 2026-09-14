#!/bin/sh
# Runs ON THE HOST. Sets up netconsole, uploads a .bin and loads it through the
# FPGA manager, detached so the ssh session survives a dead board.
# Usage: load-bitstream.sh <board-ip> <file.bin> [host-iface]
set -e
BOARD=$1; BIN=$2; IF=${3:-eno1}
[ -f "$BIN" ] || { echo "usage: $0 <board-ip> <file.bin> [host-iface]" >&2; exit 1; }
HERE=$(dirname "$(realpath "$0")")
NAME=$(basename "$BIN")
HOST_IP=$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1)
HOST_MAC=$(ip -br link show "$IF" | awk '{print $3}')
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 root@$BOARD"

LOG=${NETCONSOLE_LOG:-$PWD/netconsole.log}
ssh-keygen -R "$BOARD" >/dev/null 2>&1 || true        # hostkey changes every boot

# one listener per host: reuse it if port 6666 is already ours, else start one
if ss -lun | grep -q ':6666 '; then
    OLD=$(pgrep -f "nclisten.py" | head -1)
    if [ -n "$OLD" ]; then
        L=$(tr '\0' '\n' < /proc/$OLD/cmdline | tail -1)
        case "$L" in /*) LOG=$L ;; *) LOG=$(readlink /proc/$OLD/cwd)/$L ;; esac
    fi
    echo "reusing netconsole listener, log: $LOG"
else
    setsid nohup python3 "$HERE/nclisten.py" "$LOG" >/dev/null 2>&1 </dev/null &
    sleep 0.5
fi
MARK=$(wc -c < "$LOG" 2>/dev/null || echo 0)

$SSH -o StrictHostKeyChecking=accept-new 'cat > /tmp/netconsole-setup.sh; sh /tmp/netconsole-setup.sh '"$BOARD $HOST_IP $HOST_MAC" < "$HERE/netconsole-setup.sh"
sleep 1
tail -c +$((MARK+1)) "$LOG" 2>/dev/null | grep -q "netconsole test" || { echo "no netconsole packet received (log: $LOG)" >&2; exit 1; }

$SSH "mkdir -p /lib/firmware; cat > /lib/firmware/$NAME; md5sum /lib/firmware/$NAME" < "$BIN"
md5sum "$BIN"

$SSH "echo 'AX7020: loading $NAME via fpga_manager' > /dev/kmsg;
  setsid nohup sh -c 'echo $NAME > /sys/class/fpga_manager/fpga0/firmware;
  echo AX7020: rc=\$? state=\$(cat /sys/class/fpga_manager/fpga0/state) > /dev/kmsg' >/dev/null 2>&1 </dev/null &"
sleep 8
echo "--- $LOG:"; tail -c +$((MARK+1)) "$LOG"
echo "--- ping:"; ping -c 2 -W 2 "$BOARD" | tail -1
