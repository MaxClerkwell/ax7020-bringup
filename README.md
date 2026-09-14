# AX7020 Bring-up

Everything needed to put **mainline U-Boot** on an [ALINX AX7020](https://en.alinx.com)
(Zynq-7000, XC7Z020) over JTAG and Ethernet only: no Xilinx FSBL, no vendor
U-Boot fork, no serial cable — and from there a Yocto Linux in the flash, a
kexec updater, a bitstream built with an open toolchain, and a REST API that
loads it. The board ends up booting an entirely open chain out of QSPI flash by
itself, operated from the workstation over the network.

The full story, including a reproducible walkthrough with seven testable
checkpoints and the nine detours it took to get there, is on my blog:

- [Deploying Hardware Like Software: A Bitstream Pipeline for the Zynq](https://maxclerkwell.tech/posts/zynq-bitstream-deployment-concept-august-2026/) — the plan
- [ALINX AX7020 Bring-up: Mainline U-Boot Over JTAG, No FSBL, No Serial Cable](https://maxclerkwell.tech/posts/alinx-bring-up-jtag-detected-without-power-august-2026/) — Stage 1
- [ALINX AX7020, Stages 2 & 3: A Yocto Linux in QSPI Flash That Fetches Its Own Updates](https://maxclerkwell.tech/posts/alinx-ax7020-yocto-linux-qspi-august-2026/) — the Linux that now lives in the flash

## Status

| Stage | Goal | State |
|---|---|---|
| 1 | Open U-Boot via JTAG, then resident in QSPI | **done, 2026-08-30** |
| 2 | Image server on the lab network | **done, 2026-09-10** — HTTP manifest + kexec, see *Stage 2* below |
| 3 | Linux for the board | **done, 2026-08-31** — Yocto maintenance system in QSPI, key-only SSH |
| 4 | Bitstream from an open toolchain | **done, 2026-09-10** — see [`docs/walkthrough-stage4-first-load.md`](docs/walkthrough-stage4-first-load.md) |
| 5 | REST API that accepts a bitstream and loads it onto the FPGA | **runs, by hand, 2026-09-14** — see [`docs/walkthrough-stage5-manual.md`](docs/walkthrough-stage5-manual.md) and [`api/`](api/README.md) |

The four German walkthroughs under `docs/` are the session logs, detours included.

## What is deliberately not here

`ps7_init_gpl.c/.h` — the PS initialisation (PLLs, MIO muxing, DDR timing)
that Vivado generates. It is not hand-written and belongs to the board
vendor's package: extract it from
`course_s4_linux/linux_base/Vitis/design_1_wrapper.xsa` in
[alinxalinx/AX7020_2023.1](https://github.com/alinxalinx/AX7020_2023.1)
and place it at `board/xilinx/zynq/zynq-ax7020/ps7_init_gpl.{c,h}`.
Five K&R declarations need `(void)` added for GCC 15
(`-Werror=strict-prototypes`).

## Building U-Boot

```bash
make alinx_ax7020_defconfig
scripts/config --disable TOOLS_MKEFICAPSULE   # host tool wants gnutls
make olddefconfig
make -j$(nproc) CROSS_COMPILE=arm-none-eabi-
```

Products: `spl/boot.bin` (flash offset `0x000000`) and `u-boot.img`
(flash offset `0x100000`). The blog post covers the JTAG load, the
netconsole setup, backing up the factory flash and the verified flashing
procedure.

## Bring-up in one line

Board cold, boot-mode jumper on JTAG:

```bash
openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg -f openocd/load-uboot.cfg
```

Then talk to the board over Ethernet:

```bash
tools/ncsh.py <board-ip> "bdinfo" "sf probe 0 30000000 0"
```

---

# Working notes

Everything below is the engineering log behind the stages: hardware facts,
device-tree rationale, flash layout, procedures, and the gotchas that cost
the most time.

## Stage 1 result

The board powers on and boots by itself out of QSPI flash — no FSBL, no JTAG
adapter, no serial console:

```
U-Boot 2026.10-rc2-g527115ef6783-dirty (Aug 30 2026 - 20:25:52 +0200)
modeboot      = qspiboot
DRAM size     = 0x40000000        (1 GiB)
DDR frequency = 533 MHz
ARM frequency = 766 MHz
SF: Detected w25q256 with page size 256 Bytes, erase size 64 KiB, total 32 MiB
IP addr       = 192.168.77.77     (DHCP)
```

The console is U-Boot's netconsole over UDP, so the whole board is operated from
the workstation with `tools/ncsh.py`.

---

## Hardware

| | |
|---|---|
| Board | Alinx AX7020, XC7Z020-2CLG400, JTAG IDCODE `0x23727093` |
| DDR3 | 2× MT41J256M16, 32-bit bus, 533 MHz → 1 GiB |
| QSPI | Winbond W25Q256, 32 MiB, single chip select, MIO 1..6 |
| UART | PS UART1 on MIO 48/49 via CP2102 (**not used** — no serial console) |
| Ethernet | PS GEM0, RGMII on MIO 16..27, MDIO on MIO 52/53, RTL8211E-VL at PHY address 1 |
| SD | MIO 40..45, card detect MIO 47 |
| USB | ULPI on MIO 28..39, reset MIO 46 (active low) |
| Boot jumper | **J13**: left pins = SD, middle = QSPI, right = JTAG |

JTAG adapter is a bare FTDI **FT232H** (`0403:6014`) wired to the four MPSSE
pins only.

---

## Repositories and sources

### U-Boot — mainline, no vendor fork

```
https://source.denx.de/u-boot/u-boot.git
commit 527115ef6783cec49e5610c523c124b399011361   (v2026.10-rc2, 2026-08-13)
```

Checked out at `build/ax7020/uboot/u-boot/` (not committed here — 490 MB).
Xilinx's `u-boot-xlnx` fork is deliberately **not** used.

### Alinx vendor package

`AX7020_2023.1/` (2.2 GB, vendor download) is kept only as a source of board
facts. Two things were taken from it:

* `course_s4_linux/linux_base/Vitis/design_1_wrapper.xsa` → `ps7_init_gpl.c/.h`
  (the PS initialisation Vivado generates: PLLs, MIO muxing, DDR timing). The
  copy in `uboot/` is byte-identical to the one inside that XSA apart from the
  prototype fix noted below.
* `design_1.hwh` inside the same XSA, plus
  `Hardware/01_SCH/AX7020开发板原理图V2.0.pdf`, to derive every device-tree
  entry. Alinx' own `course_s6_linux/*/device_tree/system-user.dtsi` confirmed
  the PHY address.

Mainline U-Boot has **no** AX7020 support — no DTS, no defconfig, no board
directory. Everything below is new.

### Host tools

| Tool | Version used |
|---|---|
| Cross toolchain | `arm-none-eabi-gcc` 15.2.1 (Debian 15:15.2.rel1.1-3) |
| OpenOCD | 0.12.0 (`/usr/bin/openocd`, scripts in `/usr/share/openocd/scripts`) |
| Python | 3.13 (for `tools/ncsh.py`, `tools/tftpd.py`) |

---

## Repository layout

```
uboot/          U-Boot sources added to the mainline tree (mirror copies)
  zynq-ax7020.dts          -> arch/arm/dts/
  alinx_ax7020_defconfig   -> configs/
  ps7_init_gpl.{c,h}       -> board/xilinx/zynq/zynq-ax7020/  (vendor-derived, not committed)
openocd/
  ft232h.cfg               JTAG adapter definition
  load-uboot.cfg           bring-up from a cold board to a running U-Boot
tools/
  ncsh.py                  U-Boot netconsole shell
  tftpd.py                 unprivileged TFTP server
  stage4-first-load/       load a bitstream over SSH, watch it over netconsole,
                           diagnose a dead board over JTAG without halting it
bitstream/
  bit2bin.py               .bit -> .bin as the Zynq FPGA manager expects it
  blinky/                  open-toolchain demo design (Verilog, XDC, Makefile)
  empty/                   PS7-only design; loading it clears the PL
api/
  app.py                   FastAPI bitstream service (GET /state, POST/DELETE /bitstream)
docs/
  walkthrough-stage2-kexec.md        image server and kexec updater, in German
  walkthrough-stage3.md              Linux session, in German
  walkthrough-stage4-first-load.md   first bitstream load, in German
  walkthrough-stage5-manual.md       the API, run by hand, in German
tftp/                      files served to the board (boot.bin, u-boot.img)
backup/                    factory QSPI dump
yocto/
  meta-ax7020/             our Yocto layer (machine, Linux DTS, image)
  setup-build.sh           regenerates build/conf from version control
  poky/ meta-xilinx/ meta-arm/ meta-openembedded/   upstream layers (not committed)
build/ax7020/uboot/u-boot/ the U-Boot checkout (not committed)
build/nextpnr-xilinx/ build/prjxray/ build/venv/   open FPGA toolchain (not committed)
AX7020_2023.1/             Alinx vendor package (not committed)
tftp/ backup/              flash images and the factory dump (not committed)
```

---

## Changes to the U-Boot tree

Four additions and two edits:

**New — `arch/arm/dts/zynq-ax7020.dts`.** Board description; every value derived
from `design_1.hwh` and the schematic. See *Device tree notes* below.

**New — `configs/alinx_ax7020_defconfig`.** Derived from
`xilinx_zynq_virt_defconfig`. Full delta:

```
+ CONFIG_DEFAULT_DEVICE_TREE="zynq-ax7020"    (was "zynq-zc706")
+ CONFIG_NET_LEGACY=y                          (replaces CONFIG_NET_LWIP)
+ CONFIG_NETCONSOLE=y
+ CONFIG_CONSOLE_MUX=y
+ CONFIG_SYS_CONSOLE_IS_IN_ENV=y
+ CONFIG_PREBOOT="setenv autoload no; dhcp; setenv stdin serial,nc; \
                  setenv stdout serial,nc; setenv stderr serial,nc"
+ CONFIG_BOOTCOMMAND="echo AX7020 netconsole ready"
+ CONFIG_CMD_TFTPPUT=y, CONFIG_TFTP_PORT=y
+ CONFIG_CMD_MD5SUM=y, CONFIG_CMD_HASH=y, CONFIG_MD5=y
- CONFIG_SPL_LOAD_FIT, CONFIG_SPL_FIT, CONFIG_SPL_FIT_PRINT
- CONFIG_SPL_STACK_R
```

**New — `board/xilinx/zynq/zynq-ax7020/ps7_init_gpl.{c,h}`.** U-Boot picks this
directory up automatically because it matches `CONFIG_DEFAULT_DEVICE_TREE` while
`CONFIG_XILINX_PS_INIT_FILE` is empty. Five K&R declarations had to gain `(void)`
(`ps7_init()`, `ps7_post_config()`, `ps7_debug()`, `perf_reset_and_start_timer()`,
`ps7GetSiliconVersion()`) — GCC 15 builds SPL with `-Werror=strict-prototypes`.

**Edit — `arch/arm/dts/Makefile`.** Adds `zynq-ax7020.dtb` to
`dtb-$(CONFIG_ARCH_ZYNQ)`.

**Edit — `include/configs/zynq-common.h`.** Default environment gains
`ncip=255.255.255.255` and `stdin`/`stdout`/`stderr` = `serial,nc`, so netconsole
is armed before the environment is ever writable.

### Building

```bash
cd build/ax7020/uboot/u-boot
make alinx_ax7020_defconfig
scripts/config --disable TOOLS_MKEFICAPSULE     # host tool needs gnutls
make olddefconfig
make -j$(nproc) CROSS_COMPILE=arm-none-eabi-
```

Products: `spl/boot.bin` (SPL plus Xilinx boot header, 107152 B) and
`u-boot.img` (legacy uImage, 1076512 B).

---

## Device tree notes

Why each entry looks the way it does:

| Entry | Source |
|---|---|
| `compatible = "alinx,zynq-ax7020", "xlnx,zynq-7000"` | second string is what the Zynq drivers match on |
| `memory@0 { reg = <0x0 0x40000000> }` | `PCW_UIPARAM_DDR_PARTNO=MT41J256M16`, 32-bit bus, 16-bit devices → 1 GiB |
| `&clkc { ps-clk-frequency = <33333333> }` | `PCW_CRYSTAL_PERIPHERAL_FREQMHZ=33.333333`; every derived clock is computed from it |
| `serial0 = &uart1`, `stdout-path` | `PCW_UART0_PERIPHERAL_ENABLE=0`, `UART1=1` on MIO 48..49 |
| `&gem0` `phy-mode = "rgmii-id"`, `ethernet-phy@1` | MIO 16..27 + MDIO 52..53; RTL8211E-VL inserts its own delays; address 1 confirmed by Alinx' `system-user.dtsi` |
| `&qspi` `num-cs = <1>`, `w25q256` | `PCW_QSPI_GRP_SINGLE_SS_IO=MIO 1..6`, `SS1_ENABLE=0` — the ZC706 template's dual-parallel flash had to go |
| `spi-rx-bus-width = <1>` | **see gotcha 2** — quad read is broken in SPL on this board |
| `bootph-all` on `&uart1`, `&qspi`, `&sdhci0` **and `flash@0`** | marks the nodes that survive into the SPL device tree |
| `usb_phy0` `reset-gpios = <&gpio0 46 1>` | schematic `PS_MIO46 → OTG_RESETN`, `PCW_USB_RESET_POLARITY=Active Low` |

---

## QSPI layout

| Offset | Content | Size |
|---|---|---|
| `0x000000` | `spl/boot.bin` — what the BootROM loads | 107152 B |
| `0x100000` | `u-boot.img` — `CONFIG_SYS_SPI_U_BOOT_OFFS` | 1076512 B |
| `0xE00000` | environment, redundant copy at `0xE40000` | 128 KiB each |

Verified contents as flashed on 2026-08-30:

```
boot.bin     md5 5727611f523d90a91f755c80bb689b48
u-boot.img   md5 ad301e968b96af9f9c587e2f524d04bb
```

The factory flash was **blank** (all `0xFF`) — Alinx ships the demos on SD card.
Full 32 MiB dump nonetheless kept at
`backup/ax7020-qspi-factory-2026-08-30.bin` (md5 `2a40671157ec2ed6375f2ec0d36fe554`).

---

## Host setup

### JTAG

`openocd/ft232h.cfg` describes the adapter. On FTDI chips the MPSSE pin
assignment is fixed in silicon (ADBUS0 = TCK, 1 = TDI, 2 = TDO, 3 = TMS); only
the idle levels and directions have to be declared, and this board needs no
reset or buffer-enable signal:

```
adapter driver ftdi
ftdi vid_pid 0x0403 0x6014
ftdi layout_init 0x0008 0x000b    # TMS high; TCK/TDI/TMS out, TDO in
adapter speed 1000
transport select jtag
```

```bash
openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg
```

A healthy chain shows two TAPs and both cores:

```
JTAG tap: zynq_pl.bs tap/device found: 0x23727093 (Xilinx, part 0x3727)
JTAG tap: zynq.cpu   tap/device found: 0x4ba00477 (ARM Ltd)
zynq.cpu0: hardware has 6 breakpoints, 4 watchpoints
zynq.cpu1: hardware has 6 breakpoints, 4 watchpoints
```

`openocd/load-uboot.cfg` then takes a cold board to a running U-Boot: SPL into
OCM, wait for `ps7_init` to bring up DDR, DDR sanity write, U-Boot proper into
DDR at `0x4000000`, `verify_image`, jump.

### Lab network

A NetworkManager *shared* connection gives the board DHCP and keeps it off the
house network. `192.168.77.0/24` was picked because `10.42/16`, `100.66/16` and
the Docker `172.x` bridges were already taken on this workstation:

```bash
nmcli connection add type ethernet ifname enp0s20f0u6u4u2 con-name zynq-lab \
    ipv4.method shared ipv4.addresses 192.168.77.1/24 ipv6.method disabled
nmcli connection up zynq-lab
```

NetworkManager runs dnsmasq behind this (range `.10`–`.254`). The board draws a
random MAC each boot, so its address changes — find it with
`ip neigh show dev enp0s20f0u6u4u2`.

### Console

```bash
tools/ncsh.py <board-ip> "bdinfo" "sf probe 0 30000000 0"   # one-shot
tools/ncsh.py <board-ip>                                    # interactive
```

Two host-side quirks are handled inside the script and are worth knowing:

* U-Boot's netconsole re-initialises the MAC for every echoed character, so
  input has to be sent **one character per UDP packet** with a gap — exactly what
  U-Boot's own `tools/netconsole` does.
* The USB NIC driver allocates ~16 KiB per received frame, so the default 208 KiB
  socket buffer overflows after ~13 tiny packets. The script drains the socket
  from a receiver thread.

### TFTP

`tools/tftpd.py` is a small unprivileged TFTP server (RFC 1350 plus
`blksize`/`tsize`), so no root and no system service is needed:

```bash
tools/tftpd.py tftp 6969
```

On the board, `setenv tftpdstp 6969` (needs `CONFIG_TFTP_PORT`) then `tftpboot`
or `tftpput`.

---

## Procedures

### Bring-up over JTAG (board cold, J13 on JTAG)

```bash
openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg -f openocd/load-uboot.cfg
```

### Flashing

Only from a U-Boot that was JTAG-loaded onto a **freshly power-cycled** board in
**JTAG** boot mode — see gotcha 5.

```bash
tools/tftpd.py tftp 6969 &
tools/ncsh.py <ip> "setenv tftpdstp 6969" \
  "sf probe 0 30000000 0" \
  "tftpboot 0x10000000 boot.bin" \
  "tftpboot 0x11000000 u-boot.img" \
  "md5sum 0x10000000 <size_boot_bin>" \
  "md5sum 0x11000000 <size_u_boot_img>"
tools/ncsh.py <ip> "sf erase 0 0x260000" \
  "sf write 0x10000000 0 <size_boot_bin>" \
  "sf write 0x11000000 0x100000 <size_u_boot_img>"
tools/ncsh.py <ip> "sf read 0x12000000 0 <size_boot_bin>" \
  "md5sum 0x12000000 <size_boot_bin>" \
  "sf read 0x13000000 0x100000 <size_u_boot_img>" \
  "md5sum 0x13000000 <size_u_boot_img>"
```

Sizes are the file sizes in hex (`printf "%x\n" $(stat -c %s tftp/boot.bin)`).
The read-back md5 must equal the host's `md5sum` — nothing counts as flashed
until it does.

### Backing up the flash

```bash
tools/ncsh.py <ip> "sf probe 0 30000000 0" "sf read 0x10000000 0 0x2000000" \
  "md5sum 0x10000000 0x2000000" \
  "tftpput 0x10000000 0x2000000 ax7020-qspi-factory.bin"
```

---

## Stage 3 — Yocto

`yocto/` holds a Yocto setup that produces a kernel, our device tree and a root
filesystem for the AX7020. U-Boot stays out of it: the bootloader is the
mainline build from `uboot/` that already lives in QSPI.

### Release and layers

`scarthgap` (Yocto 5.0 LTS) throughout — it is the newest release branch
meta-xilinx offers, so it sets the common denominator.

| Layer | Origin | Why |
|---|---|---|
| `poky` | `https://git.yoctoproject.org/poky` | build system and core metadata |
| `meta-xilinx` | `https://github.com/Xilinx/meta-xilinx` | `zynq-generic` machine, `linux-xlnx` kernel |
| `meta-arm` | `https://git.yoctoproject.org/meta-arm` | required by meta-xilinx |
| `meta-openembedded` | `https://github.com/openembedded/meta-openembedded` | `meta-oe`, `meta-python`, `meta-networking` |
| `meta-ax7020` | this repository | machine, device tree, image |

```bash
cd yocto
for r in "https://git.yoctoproject.org/poky poky" \
         "https://github.com/Xilinx/meta-xilinx meta-xilinx" \
         "https://git.yoctoproject.org/meta-arm meta-arm" \
         "https://github.com/openembedded/meta-openembedded meta-openembedded"; do
    set -- $r; git clone --depth 1 -b scarthgap "$1" "$2"
done
```

Shallow clones are ~170 MB in total; the build itself needs roughly 50–100 GB
under `yocto/` and several hours on this six-core machine.

### Host prerequisites (Debian)

```bash
sudo apt install gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
    debianutils iputils-ping python3-git python3-jinja2 python3-subunit \
    zstd lz4 file locales libacl1
```

On this workstation only `diffstat`, `chrpath` and `lz4` were missing; bitbake
refuses to parse without them.

Note the last one: most Yocto guides still say `liblz4-tool`, a transitional
package that no longer exists in Debian 13 — the binary lives in **`lz4`**. Yocto
in turn still asks for the tool under its old name `lz4c`, which lz4 1.10 no
longer installs. `yocto/hostbin/lz4c` is a symlink covering that, and
`setup-build.sh` puts it on `PATH`, so no root is involved.

### What `meta-ax7020` contains

Everything Linux needs ships as **one artifact**: a FIT image holding kernel,
device tree and an initramfs, written to QSPI. The root filesystem lives in RAM
— the board has 1 GiB of it and only 32 MiB of flash — so there is no filesystem
in flash to corrupt, and an update is a single atomic write.

* **`conf/machine/ax7020.conf`** — `require`s meta-xilinx' `zynq-generic.conf`
  and then narrows it: `KERNEL_IMAGETYPE = "fitImage"` with
  `KERNEL_CLASSES = "kernel-fitimage"`, `INITRAMFS_IMAGE = "ax7020-initramfs"`
  and `INITRAMFS_IMAGE_BUNDLE = "0"` so the initramfs becomes its own section in
  the FIT instead of being linked into the kernel. No bootloader provider at
  all — U-Boot comes from `uboot/`.
* **`recipes-core/images/ax7020-initramfs.bb`** — `core-image-minimal` as
  `cpio.gz`, plus dropbear and `ethtool`, with overhead factor 1.0 and no
  locales.
* **`recipes-kernel/linux/files/ax7020.cfg`** — kernel config fragment, merged
  onto `xilinx_zynq_defconfig`. It enables the FPGA manager
  (`CONFIG_FPGA_MGR_ZYNQ_FPGA`, `CONFIG_OF_FPGA_REGION`, `CONFIG_OF_OVERLAY`),
  sysfs/devtmpfs, initrd support, `CONFIG_NETCONSOLE`, and MTD plus
  `CONFIG_SPI_ZYNQ_QSPI` so userspace can rewrite the boot chain. It then turns
  off DRM, framebuffer, sound, media, wireless, Bluetooth, CAN, InfiniBand, NFS,
  btrfs, XFS and IPv6 — none of which this board has or needs in 32 MiB.
* **`recipes-kernel/linux/files/zynq-ax7020.dts`** — the Linux device tree, the
  counterpart of `uboot/zynq-ax7020.dts` rather than a copy: U-Boot only needs
  the peripherals it drives itself, the kernel wants the full picture including
  the flash partition map. The single-bit `spi-rx-bus-width` is carried over
  (see gotcha 2).
* **`recipes-kernel/linux/linux-xlnx_%.bbappend`** — drops the `.dts` into
  `arch/arm/boot/dts/xilinx/`, appends it to that directory's `Makefile`, and
  adds the config fragment.

#### Why dropbear here

Earlier in this file the recommendation for a network-booted rootfs was
OpenSSH. For an image that has to live in QSPI the trade-off flips: dropbear's
roughly 1 MB against OpenSSH's several is the deciding factor. Once the rootfs
moves to SD or NFS, swap `ssh-server-dropbear` for `ssh-server-openssh` in
`ax7020-initramfs.bb`.

#### FPGA bitstream loading

`zynq-7000.dtsi` already provides `devcfg@f8007000` and an `fpga-region` node
wired to it, both enabled by default, so nothing board-specific is needed in our
DTS. With the config fragment above the kernel exposes
`/sys/class/fpga_manager/fpga0/`. Which userspace path the REST API finally uses
— a device-tree overlay through `fpga-region`, or writing the bitstream
directly — is a Stage 5 decision; the kernel side is prepared either way.

For the API itself, FastAPI is indeed out of reach: Python 3 plus uvicorn and
pydantic is tens of megabytes against a 32 MiB budget. CrowCpp is header-only,
so the cost is the C++ runtime — either `libstdc++` in the image (~1 MB) or a
statically linked binary.

### Building

```bash
source yocto/setup-build.sh      # writes conf/, enters the build environment
bitbake virtual/kernel           # builds kernel, DTB, initramfs and the FIT
```

`setup-build.sh` regenerates `build/conf/local.conf` and `build/conf/bblayers.conf`
on every run, so the configuration lives in version control rather than in a
scratch directory. `DL_DIR` and `SSTATE_DIR` sit next to it in `yocto/` and can
be deleted to reclaim space.

The FIT lands in `yocto/build/tmp/deploy/images/ax7020/` as
`fitImage-ax7020-initramfs-ax7020-ax7020` (plus symlinks). A copy ready for
flashing sits in `tftp/fitImage`.

#### First build, 2026-08-31

3953 tasks, all succeeded. Result:

| Component | Size |
|---|---|
| Kernel (linux-xlnx 6.6.40, load/entry `0x00200000`) | 3,967,656 B (3.78 MiB) |
| Device tree `zynq-ax7020.dtb` | 11,651 B |
| initramfs `cpio.gz` | 4,474,546 B (4.27 MiB) |
| **FIT total** | **8,455,980 B (8.06 MiB)**, md5 `01e01fcfcf86bea7872753417b64f8bb` |

That is **46 % of the 17.5 MiB partition** — 9.44 MiB to spare, so the earlier
estimate held and moving the U-Boot environment is not needed.

`dumpimage -l` confirms the structure: one configuration `conf-zynq-ax7020.dtb`
combining `kernel-1`, `fdt-zynq-ax7020.dtb` and `ramdisk-1`. The kernel config
carries `CONFIG_FPGA_MGR_ZYNQ_FPGA`, `CONFIG_FPGA_REGION`, `CONFIG_OF_FPGA_REGION`,
`CONFIG_OF_OVERLAY`, `CONFIG_NETCONSOLE`, `CONFIG_DEVTMPFS_MOUNT` and
`CONFIG_SPI_ZYNQ_QSPI`, with DRM, sound, WLAN and IPv6 off as intended.

#### Three build fixes this took

1. **`${UNPACKDIR}` does not exist in scarthgap** (it arrived in 5.1). The kernel
   bbappend expanded it to nothing and `do_configure` died on
   `install: cannot stat '/zynq-ax7020.dts'`. In scarthgap, SRC_URI files land in
   `${WORKDIR}`; the bbappend now falls back to it.
2. **`bootgen-native` does not build with GCC 15.** Debian 13's compiler turns
   `-Wincompatible-pointer-types` into an error and the Xilinx code trips over it
   in `utils/src/cdo-load.c`. `recipes-devtools/bootgen/bootgen_%.bbappend` relaxes
   just that diagnostic. We never use bootgen — `boot.bin` comes from mainline
   SPL — but meta-xilinx pulls it in regardless.
3. **`IMAGE_NAME_SUFFIX` must be empty for an initramfs.** scarthgap appends
   `.rootfs` to image names, while `kernel-fitimage` looks for
   `<image>-<machine>.cpio.gz` without it, so the assembly failed with
   *Could not find a valid initramfs type*. poky's own initramfs recipes clear the
   suffix for exactly this reason; `ax7020-initramfs.bb` now does too.

Operational note: run bitbake **detached** (`setsid nohup … &`). A bitbake client
killed by the terminal takes its `bitbake-server` down with it and the build
stops. Restarting is cheap — `sstate-cache` and `tmp/work` let it resume where it
left off.

### Flash layout with Linux

The U-Boot side is unchanged, so no new bootloader has to be written:

| Offset | Content | Size |
|---|---|---|
| `0x000000` | `boot.bin` | 1 MiB |
| `0x100000` | `u-boot.img` | 13 MiB (oversized, but already set) |
| `0xE00000` | environment + redundant copy | 512 KiB |
| `0xE80000` | **FIT: kernel + DTB + initramfs** | **17.5 MiB** |

This matches the partition map in the Linux DTS and ends exactly at 32 MiB.
Rough expectation: 2.5–5 MB kernel, ~20 KB DTB, 5–10 MB initramfs — so roughly
half the partition should stay free. The real numbers come out of the first
build.

If that ever gets tight, moving the environment down to `0x200000` frees almost
30 MiB for the FIT, at the cost of rebuilding U-Boot with a new
`CONFIG_ENV_OFFSET` and one more flashing round.

### Flashing and booting the FIT

Same rule as always: from a U-Boot that was JTAG-loaded onto a freshly
power-cycled board in JTAG boot mode (gotcha 5), and verified by read-back.

```
setenv tftpdstp 6969
tftpboot 0x2000000 fitImage
sf probe 0 30000000 0
sf erase 0xE80000 0x1180000
sf write 0x2000000 0xE80000 0x81072c
sf read  0x3000000 0xE80000 0x81072c
md5sum   0x3000000 0x81072c     # expect 01e01fcfcf86bea7872753417b64f8bb
```

Then make it the default boot:

```
setenv bootcmd 'sf probe 0 30000000 0; sf read 0x2000000 0xE80000 0x1180000; bootm 0x2000000'
setenv bootargs 'console=ttyPS0,115200 netconsole=6666@<board-ip>/,6666@192.168.77.1/'
saveenv
```

`bootm` on a FIT picks kernel, DTB and ramdisk out of the one image by itself.
Note that U-Boot's own FIT support is fine — what we disabled in gotcha 4 was
*SPL's* FIT loader, a different piece of code.

### First Linux boot, 2026-08-31 (from RAM, nothing written to flash)

The FIT was loaded over TFTP into DDR and started with `bootm` — no flash write,
so a failure would have cost nothing:

```
tftpboot 0x2000000 fitImage                    # 8455980 bytes, md5 matched
setenv bootargs 'console=ttyPS0,115200 ip=dhcp netconsole=6666@/eth0,6666@192.168.77.1/'
bootm 0x2000000
```

U-Boot verified all three sub-images (sha256) and handed over. It worked:

```
OF: fdt: Machine model: Alinx AX7020 board
Memory: 1008588K/1048576K available
e0001000.serial: ttyPS0 ... is a xuartps
macb e000b000.ethernet eth0: Cadence GEM rev 0x00020118 (8a:2a:9b:85:25:3b)
fpga_manager fpga0: Xilinx Zynq FPGA Manager registered
of-fpga-region fpga-region: FPGA Region probed
Freeing initrd memory: 4372K
```

Verified on the running system over SSH:

| Check | Result |
|---|---|
| `/sys/class/fpga_manager/fpga0/` | present — `name`, `state`, `status`, `firmware`, `flags`, `key` |
| FPGA manager name | `Xilinx Zynq FPGA Manager` |
| `of-fpga-region` | probed |
| `/proc/mtd` | `boot.bin` 1 MiB, `u-boot` 13 MiB, `u-boot-env` 512 KiB, `fit` 17.5 MiB — the DTS map |
| Root filesystem | 492.5 MiB in RAM, 8.8 MiB used |
| Network | eth0 up, 192.168.77.77 via `ip=dhcp` |
| Shell | dropbear on port 22, `scp` present |

Kernel: `6.6.40-xilinx`, `armv7l`, SMP.

Two things did **not** work as written:

* **`netconsole=` produced nothing.** Configured at boot it needs the target MAC
  address; without it the module cannot ARP that early and stays silent. Either
  append the host's MAC to the parameter or load the module from userspace.
* U-Boot answers ICMP while it sits in its netconsole poll loop, so **a ping is
  not proof that Linux is up**. Port 22 (or the absence of a netconsole prompt)
  is the reliable test.

### Network identity and console ownership

The board carries a fixed identity so it can be found on a shared network:

| | |
|---|---|
| MAC | `02:41:58:70:20:01` — locally administered, `41:58` is "AX", `70:20` the board number |
| Hostname | `ax7020`, sent in the DHCP request (`CONFIG_BOOTP_SEND_HOSTNAME`) |

Both live in the default environment (`include/configs/zynq-common.h`), so they
survive an erased environment. Without them U-Boot draws a random MAC on every
boot and registers no name at all.

**First caller claims the console.** Out of reset `ncip` is the broadcast
address, so the board answers anyone on the segment. The first person who types
latches `ncip` to their address; from then on the input filter in
`nc_input_packet()` rejects everyone else and output goes only to the owner.
The claim lives in the environment only, so a reboot releases it, and the owner
can hand the board back with `setenv ncip 255.255.255.255`.

The patch is `uboot/patches/netconsole-first-caller-claims.patch`, twelve lines
in `drivers/net/netconsole.c`.

Verified on the board: after the first keystroke `printenv ncip` reported the
workstation's address, and setting `ncip` to a foreign address made the board
ignore further input while JTAG confirmed it was still running normally.

**This is convenience, not security.** The netconsole has no authentication;
whoever claims the board first simply wins the race, and anyone able to send
UDP to port 6666 before that gets a full bootloader prompt — `sf write`
included. Fine on a trusted segment, not a substitute for network isolation.

### SSH access

The maintenance system accepts **key authentication only**:

* `ax7020-ssh-key` installs the operator's public key to
  `/home/root/.ssh/authorized_keys` with mode 0600 in a 0700 directory —
  dropbear rejects the file otherwise.
* A dropbear bbappend replaces `/etc/default/dropbear` with
  `DROPBEAR_EXTRA_ARGS="-s"`, which disables password logins.
* `debug-tweaks` is deliberately **not** in `EXTRA_IMAGE_FEATURES`. It would
  give root an empty password, which was fine on an isolated lab segment and
  is not once the board sits on a shared network. Root's password field is `*`.

Careful with poky's stock `dropbear.default`: it passes `-w`, which forbids
root logins outright. That must not be combined with key-based root access —
use `-s` alone.

Verified on the running board: a key login succeeds, and

```
ssh -o PubkeyAuthentication=no root@<board>
root@...: Permission denied (publickey).
```

### The console after handover

U-Boot's netconsole ends the moment Linux starts. Two things bridge the gap, and
neither is a full replacement for a serial cable:

* the **netconsole** module ships kernel messages over UDP (`netconsole=` above),
  one-way, no input — but it shows the bring-up;
* **dropbear** gives a shell over SSH once userspace and the network are up.

If the kernel dies before either — wrong device tree, no PHY link — nothing
reports it. That is the moment to finally hang a cable on the CP2102.

### Open question before the first build

`linux-xlnx` (the vendor tree) is meta-xilinx' default and what the machine
inherits. Mainline `linux-yocto` would fit the "open path" theme better — Zynq
-7000 is fully supported upstream — but needs its own `KMACHINE`/defconfig
wiring. `XILINX_RELEASE_VERSION` in `local.conf` is pinned to `v2024.2`, which
selects the `linux-xlnx` recipe version.

---

## Stage 2 — image server and the kexec updater

Reached 2026-09-10, after Stage 3 rather than before it: the maintenance
system in flash fetches kernel, device tree and initramfs from an HTTP server
and boots into them with kexec. Nothing in flash changes; a broken image costs
a power cycle, not a reflash. Session notes in
[`docs/walkthrough-stage2-kexec.md`](docs/walkthrough-stage2-kexec.md).

### Publishing an image

```bash
tools/publish-image.sh build/images        # from yocto/build/tmp/deploy/images/ax7020
cd build/images && python3 -m http.server 8080 --bind 10.42.100.20
```

`publish-image.sh` copies zImage, DTB and `cpio.gz` under a timestamp, writes
`<stamp>.manifest` and points `latest.manifest` at it:

```
kernel zImage-20260910-105035            542ef58f…
dtb    zynq-ax7020-20260910-105035.dtb   1e3fa9c7…
initrd initramfs-20260910-105035.cpio.gz fbce1304…
```

Any static web server does; file names are resolved relative to the manifest
URL, so a Nextcloud share works as well as `python3 -m http.server`.

### On the board

`/etc/ax7020-update.conf` names the manifest:

```
IMAGE_URL="http://10.42.100.20:8080/latest.manifest"
```

`ax7020-update` (recipe `recipes-support/ax7020-updater`) fetches the three
files, checks every SHA256, checks the zImage magic at offset 0x24 and the DTB
magic, then `kexec -l zImage --dtb --initrd --command-line` and `kexec -e`.
`DRY_RUN=1` stops after `kexec -l`. `CMDLINE=` overrides the kernel command
line, which is how a netconsole target with the host's MAC gets into the new
kernel:

```
CMDLINE="console=ttyPS0,115200 ip=dhcp netconsole=6666@10.42.100.134/eth0,6666@10.42.100.20/<host-mac>"
```

An init script (`rc5`, priority 99) runs the updater 15 s after boot when
`IMAGE_URL` is set, detached, output to `/dev/kmsg`. With an empty
`IMAGE_URL` the board simply stays in the maintenance system.

Measured hand-over: `kexec -e` at 13:03:22, new kernel's first line 13:03:28,
SSH back 13:03:45.

### Why not the FIT

The first version of the updater fetched the FIT and ran `kexec -l fitImage`.
kexec-tools 2.0.28 has no FIT loader on 32-bit ARM, and its zImage probe
accepts **any** file:

```c
int zImage_arm_probe(const char *UNUSED(buf), off_t UNUSED(len))
{
	/* Only zImage loading is supported. Do not check if
	 * the buffer is valid kernel image */
	return 0;
}
```

So `kexec -l` succeeded, `kexec -e` jumped into a device-tree blob, and the
board died silently. See gotcha 12. Hence three files and a manifest.

---

## Stage 4 — bitstream from an open toolchain

Reached 2026-09-10: a design synthesised, placed, routed and converted to a
bitstream without any Xilinx software, loaded into the PL through the kernel's
FPGA manager over SSH, and the board kept running. The session, including the
failure on the first attempt, is in
[`docs/walkthrough-stage4-first-load.md`](docs/walkthrough-stage4-first-load.md).

### Toolchain

Built from source under `build/`, nothing installed system-wide except Yosys
from Debian:

| Tool | Version | Where |
|---|---|---|
| Yosys | 0.66 (Debian) | `/usr/bin/yosys` |
| nextpnr-xilinx | openXC7 fork, `5f351cc2` (2026-08-29) | `build/nextpnr-xilinx/build/nextpnr-xilinx`, chipdb `xilinx/xc7z020.bin` |
| prjxray | f4pga, `c9f02d85` (2025-06-05) | `build/prjxray/build/tools/xc7frames2bit`, `utils/fasm2frames.py` |
| prjxray-db | `77e52f1` (2026-08-26) | `build/nextpnr-xilinx/xilinx/external/prjxray-db/zynq7` |
| Python venv | fasm, prjxray | `build/venv` |

### Flow

`bitstream/blinky/Makefile` chains the four steps and one conversion:

```
blinky.v  --yosys synth_xilinx-->  blinky.json
          --nextpnr-xilinx---->  blinky.fasm      (placed and routed, XDC pins)
          --fasm2frames------->  blinky.frames
          --xc7frames2bit----->  blinky.bit
          --bit2bin.py-------->  blinky.bin       (header stripped, words byte-swapped)
```

`make blinky.bin` produces everything. The `.bin` is what `zynq-fpga` in the
kernel expects — the same layout bootgen would write.

### Loading

```bash
tools/stage4-first-load/load-bitstream.sh 10.42.100.134 bitstream/blinky/blinky.bin
```

The script points the kernel log at the workstation via dynamic netconsole
(configfs), uploads the file, writes its name into
`/sys/class/fpga_manager/fpga0/firmware` from a detached shell, and reports
the outcome. Success looks like:

```
fpga_manager fpga0: writing blinky.bin to Xilinx Zynq FPGA Manager
AX7020: rc=0 state=operating
```

### The PS7 rule

A Zynq design **must instantiate the PS7 block**, even if it uses nothing of
it:

```verilog
(* keep *) PS7 ps7_i();
```

nextpnr then ties every unused PS7 input to ground. Without it the PL drives
the direct nFIQ/nIRQ lines into both Cortex-A9 cores (`IRQF2P[19:16]`, which
bypass the GIC) the moment the FPGA-manager driver enables the PL→PS level
shifters. Both cores then spin in FIQ handling forever, no panic is ever
printed, and the driver never reaches the line that releases the PL reset.
See gotcha 10.

### Diagnosing a silent board over JTAG

The AHB-AP of the Zynq DAP reads physical addresses while Linux keeps running,
so no `halt` is needed:

```bash
tools/stage4-first-load/jtag-regs.sh      # devcfg, SLCR, GEM registers
tools/stage4-first-load/jtag-logbuf.sh    # printk ring buffer straight out of DDR
tools/stage4-first-load/jtag-pc.sh        # pc/cpsr of both cores, resolved via System.map
```

A reboot without touching the power: SLCR unlock, then `PSS_RST_CTRL` = 1,
both through the AHB-AP (`zynq.dap apreg 0 ...`). Unlike gotcha 6, which was
about writes issued through the CPU, debug access survived this.

---

## Gotchas

Every one of these cost real debugging time. They are the reason Stage 1 took as
long as it did.

**1. `bootph-all` must be on the flash node, not just the QSPI controller.**
The SPL device tree is produced by filtering on that property; the filter keeps
matching nodes and their *parents*, not their *children*. Without it
`spi_get_bus_and_cs()` → `spi_find_chip_select()` finds no chip select and SPL
dies in `SPI probe failed.` The old fallback that bound a `jedec_spi_nor` without
a DT node is gone in U-Boot 2026.

**2. No quad read in SPL.** With `spi-rx-bus-width = <4>` the QSPI read comes
back **3 bytes offset** inside SPL. The image header is therefore never
recognised, SPL silently falls back to its raw-image path (`offset = 0`,
`size = 0x32000`), copies the uImage header to `TEXT_BASE` and jumps into it.
Plain single-bit `READ` is correct. U-Boot proper does **not** show the fault,
which makes this easy to misdiagnose — `sf read` + `md5sum` from the U-Boot
prompt will happily confirm a flash that SPL cannot read.

**3. Keep the SPL stack in OCM** (`# CONFIG_SPL_STACK_R is not set`). Relocating
it into DDR yielded a corrupted stack pointer (`0x1dfed5` — odd, and one address
bit off, while `r9`/`r11`/`r12` were correct) and an alignment abort on the
`push` in `spi_nor_check_op`. Plain JTAG write/read tests of that DDR region all
pass, so it does not show up as a memory fault.

**4. Legacy uImage, not FIT** (`# CONFIG_SPL_LOAD_FIT is not set`). The SPL FIT
loader placed the FDT at `TEXT_BASE`, so U-Boot executed a device tree. The
legacy path is a header parse plus one copy and is the well-trodden route on
Zynq QSPI. It also drops SPL from 131 KB to 107 KB.

**5. Flash only from a JTAG-loaded U-Boot on a freshly power-cycled board.**
Writes issued from a U-Boot that SPL had already handed the QSPI controller to
reported `Written: OK` and left the flash starting with zeros — the BootROM then
parked at `0xffffff28`. Related: after **any** QSPI-mode boot, JTAG-loading
U-Boot into DDR no longer works (it ends at `0x40`); a JTAG-mode power cycle is
mandatory first. Likewise, restarting SPL on a board whose PS is already
initialised fails early in `lowlevel_init`, because `ps7_init` is not idempotent.

**6. Never write `PSS_RST_CTRL` (`0xF8000200`) over JTAG.** It resets the debug
logic too, and cpu0 becomes unhaltable until the power is cycled.

**7. Select cpu0 explicitly.** After `halt` the current OpenOCD target is often
cpu1, and `resume <addr>` only sets the PC of the current target.

**8. Loading into DDR while a previous U-Boot is halted corrupts the image** in
32-byte chunks — that U-Boot has MMU and D-cache on. Either flush with
`zynq.cpu0 cache l1 d flush_all` around the load, or load only while SPL (caches
off) is halted. JTAG *reads* of DDR can likewise return stale cache lines and
fake a corrupted image.

**10. A Zynq bitstream without a PS7 instance hangs both cores.** Loading
succeeds (`PCFG_DONE`), then the level shifters open and the PL floods the
direct FIQ lines. Nothing is printed. Symptom over JTAG: `LVL_SHFTR_EN = 0xf`,
`FPGA_RST_CTRL = 0xf`, cpu0 in `ct_nmi_enter`, cpu1 in `vector_fiq`. Fix:
`(* keep *) PS7 ps7_i();` in the top module.

**11. The SSH host key changes on every boot.** The root filesystem lives in
RAM, so dropbear generates a fresh key each time. `ssh-keygen -R <ip>` before
connecting; `Connection refused` right after a reboot only means dropbear is
not up yet.

**12. `kexec -l` on 32-bit ARM accepts any file.** There is no FIT loader
and the zImage probe does not look at the data. Feed it a FIT and `kexec -e`
executes the blob. Always hand kexec a zImage plus `--dtb`, and check the
zImage magic (`18286f01` at offset 0x24) yourself before calling it.

**13. After a crashed kexec, a soft reset does not boot.** `PSS_RST_CTRL`
over JTAG restarts the PS, but the BootROM then parks at `0xffffff28` as if
the flash were blank. Linux had switched the 32 MiB W25Q256 into 4-byte
address mode, the PS reset does not reset the flash chip, and the BootROM
reads with 3-byte addresses. Only a power cycle clears it. A soft reset after a
*cleanly running* Linux worked, so the difference is whether the flash driver
got to restore the chip.

**9. Netconsole occasionally drops input characters.** A mangled `sf write`
becomes `Unknown command` and writes nothing. Check the echo of every
destructive command; the read-back verification is what makes this safe.

---

## Debugging technique worth keeping

Diagnosing the SPL flash path normally means moving the boot jumper and power
cycling for every attempt. Two temporary patches removed that entirely:

* In `arch/arm/mach-zynq/spl.c`, map `ZYNQ_BM_JTAG` to `BOOT_DEVICE_SPI`. SPL
  then exercises the real QSPI load path while the board is in JTAG boot mode,
  so it can be loaded and re-run over JTAG.
* In `_spl_load()` (`include/spl_load.h`), write `load_addr`, `entry_point`,
  `size`, `offset`, `image_offset`, `overhead`, the read return value, `bl_len`
  and the first words at the load address into spare DDR at `0x3f000000`.

Reading those breadcrumbs after one run is what identified gotcha 2 — they
showed `offset = 0` and `size = 0x32000`, i.e. the raw-image fallback, with the
uImage magic sitting at `load_addr + 3`.

Both patches must be reverted before building anything that gets flashed.


---

## Commercial work

I do this professionally: commercial board bring-up, custom Zynq/FPGA
boards, embedded Linux and DAQ systems as a freelancer —
[maxclerkwell.tech/hire](https://maxclerkwell.tech/hire/).

## Links

- Blog: [maxclerkwell.tech](https://maxclerkwell.tech)
- YouTube: [@MaxClerkwell](https://youtube.com/@MaxClerkwell)
- Instagram: [@_maxclerkwell](https://instagram.com/_maxclerkwell)
- Board vendor: [en.alinx.com](https://en.alinx.com) · [AX7020 vendor package](https://github.com/alinxalinx/AX7020_2023.1)

## License

GPL-2.0-or-later, matching U-Boot. See [LICENSE](LICENSE).
