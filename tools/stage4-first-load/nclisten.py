import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("0.0.0.0", 6666))
with open(sys.argv[1], "ab", buffering=0) as f:
    while True:
        d, a = s.recvfrom(65535)
        f.write(f"[{time.strftime('%H:%M:%S')} {a[0]}] ".encode() + d)
        if not d.endswith(b"\n"): f.write(b"\n")
