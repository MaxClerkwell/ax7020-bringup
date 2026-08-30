#!/usr/bin/env python3
"""Tiny unprivileged TFTP server (RFC 1350 + blksize/tsize options, RFC 2347/2348/2349).

Serves and accepts files in ROOT on an unprivileged port so no root is needed.
U-Boot side:  setenv tftpdstp 6969   (needs CONFIG_TFTP_PORT)
              tftpboot 0x10000000 file      / tftpput 0x10000000 <size> file

    tools/tftpd.py [root-dir] [port]
"""
import os, socket, struct, sys, threading, time

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 6969
RRQ, WRQ, DATA, ACK, ERROR, OACK = 1, 2, 3, 4, 5, 6

def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)

def parse_req(pkt):
    parts = pkt[2:].split(b"\0")
    fname, mode = parts[0].decode(), parts[1].decode().lower()
    opts = {}
    kv = parts[2:]
    for i in range(0, len(kv) - 1, 2):
        if kv[i]:
            opts[kv[i].decode().lower()] = kv[i + 1].decode()
    return fname, mode, opts

def safe_path(fname):
    p = os.path.abspath(os.path.join(ROOT, fname.lstrip("/")))
    if not p.startswith(ROOT + os.sep) and p != ROOT:
        raise PermissionError(fname)
    return p

def err(sock, peer, code, msg):
    sock.sendto(struct.pack("!HH", ERROR, code) + msg.encode() + b"\0", peer)

def serve(peer, pkt):
    op = struct.unpack("!H", pkt[:2])[0]
    fname, mode, opts = parse_req(pkt)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(5)
    blksize = int(opts.get("blksize", 512))
    try:
        path = safe_path(fname)
    except PermissionError:
        err(s, peer, 2, "access violation"); return
    if op == RRQ:
        if not os.path.isfile(path):
            err(s, peer, 1, "file not found"); return
        size = os.path.getsize(path)
        log(f"RRQ {fname} ({size} bytes) -> {peer}")
        oack = {}
        if "blksize" in opts: oack["blksize"] = str(blksize)
        if "tsize" in opts: oack["tsize"] = str(size)
        with open(path, "rb") as f:
            block = 0
            if oack:
                s.sendto(struct.pack("!H", OACK) + b"".join(k.encode() + b"\0" + v.encode() + b"\0" for k, v in oack.items()), peer)
                if not wait_ack(s, peer, 0): return
            while True:
                data = f.read(blksize); block = (block + 1) & 0xFFFF
                for _ in range(5):
                    s.sendto(struct.pack("!HH", DATA, block) + data, peer)
                    if wait_ack(s, peer, block): break
                else:
                    log("timeout, abort"); return
                if len(data) < blksize: break
        log(f"RRQ {fname} done")
    elif op == WRQ:
        log(f"WRQ {fname} <- {peer}")
        oack = {}
        if "blksize" in opts: oack["blksize"] = str(blksize)
        if "tsize" in opts: oack["tsize"] = opts["tsize"]
        if oack:
            s.sendto(struct.pack("!H", OACK) + b"".join(k.encode() + b"\0" + v.encode() + b"\0" for k, v in oack.items()), peer)
        else:
            s.sendto(struct.pack("!HH", ACK, 0), peer)
        expect, total = 1, 0
        with open(path, "wb") as f:
            while True:
                try:
                    d, a = s.recvfrom(65536)
                except socket.timeout:
                    log("timeout, abort"); return
                if a != peer or struct.unpack("!H", d[:2])[0] != DATA: continue
                blk = struct.unpack("!H", d[2:4])[0]
                if blk == expect:
                    f.write(d[4:]); total += len(d) - 4; expect = (expect + 1) & 0xFFFF
                s.sendto(struct.pack("!HH", ACK, blk), peer)
                if blk == (expect - 1) & 0xFFFF and len(d) - 4 < blksize: break
        log(f"WRQ {fname} done, {total} bytes")

def wait_ack(s, peer, block):
    try:
        while True:
            d, a = s.recvfrom(1024)
            if a == peer and len(d) >= 4 and struct.unpack("!HH", d[:4]) == (ACK, block):
                return True
    except socket.timeout:
        return False

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.bind(("0.0.0.0", PORT))
    log(f"tftpd serving {ROOT} on udp/{PORT}")
    while True:
        pkt, peer = srv.recvfrom(65536)
        if len(pkt) >= 4 and struct.unpack("!H", pkt[:2])[0] in (RRQ, WRQ):
            threading.Thread(target=serve, args=(peer, pkt), daemon=True).start()

if __name__ == "__main__":
    main()
