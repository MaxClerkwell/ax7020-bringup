#!/usr/bin/env python3
"""Minimal U-Boot netconsole shell.

U-Boot's netconsole re-initialises the Ethernet MAC for every echoed
character, so anything that arrives during that window is lost. Like
U-Boot's own tools/netconsole, this sends ONE character per UDP packet
with a short gap. Output (sent by U-Boot as broadcast to ncip) is
collected on UDP 6666.

A receiver thread drains the socket continuously: the host NIC driver may
allocate ~16 KiB per received frame, so the default 208 KiB socket buffer
overflows after ~13 tiny packets (UdpRcvbufErrors) if we only read after
sending.

    tools/ncsh.py <board-ip> [command ...]      # run commands, print output
    tools/ncsh.py <board-ip>                    # interactive line mode
"""
import queue, re, socket, sys, threading, time

PORT, GAP = 6666, 0.4
ESC = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    board = (sys.argv[1], PORT)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)  # capped by rmem_max
    s.bind(("0.0.0.0", PORT)); s.settimeout(0.2)
    q = queue.Queue()

    def rx():
        while True:
            try:
                d, _ = s.recvfrom(4096); q.put(d)
            except socket.timeout:
                pass
    threading.Thread(target=rx, daemon=True).start()

    def drain(t=8.0):
        got, end = b"", time.time() + t
        while time.time() < end:
            try:
                got += q.get(timeout=0.2); end = min(end, time.time() + 1.5)
            except queue.Empty:
                pass
        return ESC.sub("", got.decode(errors="replace"))

    def run(cmd):
        for c in cmd + "\n":
            s.sendto(c.encode(), board); time.sleep(GAP)
        return drain()

    cmds = sys.argv[2:]
    if cmds:
        for c in cmds:
            sys.stdout.write(run(c)); sys.stdout.flush()
        return
    try:
        while True:
            sys.stdout.write(run(input("nc> "))); sys.stdout.flush()
    except (EOFError, KeyboardInterrupt):
        print()

if __name__ == "__main__":
    main()
