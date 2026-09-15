"""Bitstream service for the AX7020: load a bitstream into the PL through the
kernel's FPGA manager, clear it again, and report the manager's state.

Run on the board with:  uv run --with fastapi --with 'uvicorn[standard]' \
    --with python-multipart uvicorn app:app --host 0.0.0.0 --port 8000
"""
import hashlib
import os
import struct
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse

FPGA = Path("/sys/class/fpga_manager/fpga0")
FIRMWARE_DIR = Path("/lib/firmware")
EMPTY_BIN = FIRMWARE_DIR / "empty.bin"       # PS7-only design, clears the PL
IDCODE = 0x23727093                           # XC7Z020, IDCODE without the
IDCODE_MASK = 0x0FFFFFFF                      # 4 revision bits
SYNC = b"\xaa\x99\x55\x66"

app = FastAPI(title="AX7020 bitstream service")


def _state() -> str:
    return (FPGA / "state").read_text().strip()


def to_bin(data: bytes) -> bytes:
    """Accept a raw .bit or an already converted .bin; return the .bin the
    Zynq FPGA manager expects: no header, every 32-bit word byte-swapped."""
    if data.find(b"\x66\x55\x99\xaa") >= 0:          # already swapped: .bin
        return data
    sync = data.find(SYNC)
    if sync < 0:
        raise HTTPException(400, "no sync word found - not a bitstream")
    start = sync
    while start >= 4 and data[start - 4:start] == b"\xff" * 4:
        start -= 4
    body = data[start:]
    if len(body) % 4:
        raise HTTPException(400, "bitstream data not word-aligned")
    return b"".join(body[i:i + 4][::-1] for i in range(0, len(body), 4))


def check_idcode(bin_data: bytes) -> int:
    """The bitstream carries a 'write IDCODE' command (type-1 packet, register
    0x0C) early in its header; the FPGA rejects the stream if it does not match.
    Reject it here instead, with a message. Works on the swapped .bin: undo the
    swap for the words we inspect."""
    words = struct.unpack(f"<{min(len(bin_data), 4096) // 4}I", bin_data[:4096 - 4096 % 4])
    for i, w in enumerate(words[:-1]):
        if w == 0x30018001:                           # type 1, write, IDCODE, 1 word
            found = words[i + 1]
            if found & IDCODE_MASK != IDCODE & IDCODE_MASK:
                raise HTTPException(400, f"bitstream is for IDCODE {found:#010x}, "
                                         f"this board is {IDCODE:#010x}")
            return found
    raise HTTPException(400, "no IDCODE command in bitstream header")


def load(name: str) -> str:
    try:
        (FPGA / "firmware").write_text(name)
    except OSError as e:
        raise HTTPException(500, f"fpga manager refused {name}: {e} (state {_state()})")
    st = _state()
    if st != "operating":
        raise HTTPException(500, f"load finished but state is {st}")
    return st


@app.get("/state")
def state():
    return {
        "state": _state(),
        "name": (FPGA / "name").read_text().strip(),
        "loaded": os.environ.get("AX7020_LOADED", None),
        "flags": (FPGA / "flags").read_text().strip() if (FPGA / "flags").exists() else None,
    }


@app.post("/bitstream")
async def put_bitstream(file: UploadFile = File(...), sha256: str | None = None):
    data = await file.read()
    digest = hashlib.sha256(data).hexdigest()
    if sha256 and sha256.lower() != digest:
        raise HTTPException(400, f"sha256 mismatch: upload is {digest}")
    bin_data = to_bin(data)
    idcode = check_idcode(bin_data)
    FIRMWARE_DIR.mkdir(parents=True, exist_ok=True)
    name = "upload-" + digest[:16] + ".bin"
    (FIRMWARE_DIR / name).write_bytes(bin_data)
    st = load(name)
    os.environ["AX7020_LOADED"] = file.filename or name
    return {"state": st, "sha256": digest, "bytes": len(bin_data),
            "idcode": f"{idcode:#010x}", "filename": file.filename}


@app.delete("/bitstream")
def clear_bitstream():
    """There is no 'unload' in the FPGA manager; the PL is cleared by loading
    a design that contains nothing but the PS7 tie-offs."""
    if not EMPTY_BIN.exists():
        raise HTTPException(500, f"{EMPTY_BIN} missing")
    st = load(EMPTY_BIN.name)
    os.environ["AX7020_LOADED"] = "empty"
    return {"state": st, "loaded": "empty"}


@app.exception_handler(HTTPException)
async def http_exc(_, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})
