# AX7020 bitstream service

FastAPI app that loads a bitstream into the PL through the kernel's FPGA
manager. First run 2026-09-14, on the maintenance image, started with `uv`.

| Method | Path | Does |
|---|---|---|
| `GET` | `/state` | FPGA manager state (`unknown`, `operating`, …) and what was loaded last |
| `POST` | `/bitstream` | multipart `file=` (`.bit` or `.bin`), optional `?sha256=`; checks sync word and IDCODE, converts `.bit`, loads, answers when the PL is up |
| `DELETE` | `/bitstream` | loads `empty.bin` (PS7 only) — there is no unload, this is how the PL gets cleared |

```bash
curl -F file=@blinky.bit "http://ax7020:8000/bitstream?sha256=$(sha256sum blinky.bit | cut -d' ' -f1)"
curl http://ax7020:8000/state
curl -X DELETE http://ax7020:8000/bitstream
```

Errors come back as `{"error": "..."}` with 400 (bad input) or 500 (the FPGA
manager refused).

FastAPI serves the interactive documentation itself at `/docs` and the schema
at `/openapi.json`:

![Swagger UI of the bitstream service on the board](../docs/img/api-swagger-ax7020.png)

## Running it on the board, by hand

The maintenance image has no Python. `uv` is a static musl binary and brings
its own interpreter; the only thing the image lacks is `libgcc_s.so.1`, which
the Yocto build has lying around. Everything below lives in RAM and is gone
after a reboot; the image recipe for the real thing is the next step.

```sh
# board needs DNS and a clock for HTTPS (the RTC sits behind the PL)
printf 'nameserver 1.1.1.1\n' > /etc/resolv.conf
ntpd -n -q -p pool.ntp.org

curl -fsSL https://github.com/astral-sh/uv/releases/latest/download/uv-armv7-unknown-linux-musleabihf.tar.gz | tar xz
install -m 755 uv-armv7-unknown-linux-musleabihf/uv /usr/bin/uv
uv python install 3.12
curl -fsSL -o /lib/libgcc_s.so.1 http://<server>/libgcc_s.so.1   # from yocto/build/tmp/work/.../libgcc/13.4.0/image/lib/

mkdir -p /opt/ax7020-api /lib/firmware
curl -fsSL -o /opt/ax7020-api/app.py   http://<server>/app.py
curl -fsSL -o /lib/firmware/empty.bin  http://<server>/empty.bin
cd /opt/ax7020-api
uv run --python 3.12 --with fastapi --with uvicorn --with python-multipart \
    uvicorn app:app --host 0.0.0.0 --port 8000
```

Two things that did not work: `uv run` without `--python 3.12` fetched 3.14
on its own, and `uvicorn[standard]` needs a C compiler for `httptools`. Plain
`uvicorn` is pure Python and fine.

Footprint on the board: uv 20 MB, Python 3.12 about 110 MB, packages a few
MB. Fits the 1 GiB RAM, would never fit the 32 MiB flash — which is why the
API image is fetched over the network and not flashed.

## As an image

Since 2026-09-15 the service ships in `ax7020-api-image` (recipe
`yocto/meta-ax7020/recipes-support/ax7020-api`, unit `ax7020-api.service`),
which the maintenance system fetches from the image server and starts with
kexec. See the Stage 5 section of the top-level README. The manual setup
above remains useful for trying a change without a Yocto build.

## Not done yet

* No authentication. Anyone on the network can load a bitstream, and a
  bitstream with an AXI master can write anywhere in RAM.
* `empty.bin` is built from `bitstream/empty/`, a PS7-only design.
