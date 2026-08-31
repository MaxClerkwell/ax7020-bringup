# AX7020 Bring-up

Everything needed to put **mainline U-Boot** on an [ALINX AX7020](https://en.alinx.com)
(Zynq-7000, XC7Z020) over JTAG and Ethernet only: no Xilinx FSBL, no vendor
U-Boot fork, no serial cable. The board ends up booting an entirely open
chain out of QSPI flash by itself, operated from the workstation through
U-Boot's netconsole over UDP.

The full story, including a reproducible walkthrough with seven testable
checkpoints and the nine detours it took to get there, is on my blog:

- [Deploying Hardware Like Software: A Bitstream Pipeline for the Zynq](https://maxclerkwell.tech/posts/zynq-bitstream-deployment-concept-august-2026/) — the plan
- [ALINX AX7020 Bring-up: Mainline U-Boot Over JTAG, No FSBL, No Serial Cable](https://maxclerkwell.tech/posts/alinx-bring-up-jtag-detected-without-power-august-2026/) — Stage 1, which this repository accompanies
- [ALINX AX7020, Stages 2 & 3: A Yocto Linux in QSPI Flash That Fetches Its Own Updates](https://maxclerkwell.tech/posts/alinx-ax7020-yocto-linux-qspi-august-2026/) — the Linux that now lives in the flash

## Contents

```
openocd/
  ft232h.cfg               JTAG adapter definition (bare FT232H, 0403:6014)
  load-uboot.cfg           cold board -> running U-Boot over JTAG
tools/
  ncsh.py                  U-Boot netconsole shell (plain Python, no deps)
  tftpd.py                 unprivileged TFTP server (no root, no service)
uboot/
  zynq-ax7020.dts          board device tree -> arch/arm/dts/
  alinx_ax7020_defconfig   build config      -> configs/
```

The U-Boot files go into a mainline checkout
(`https://source.denx.de/u-boot/u-boot.git`, tested at v2026.10-rc2,
commit `527115ef6783`); add `zynq-ax7020.dtb` to the
`dtb-$(CONFIG_ARCH_ZYNQ)` list in `arch/arm/dts/Makefile`.

## What is deliberately not here

`ps7_init_gpl.c/.h` — the PS initialisation (PLLs, MIO muxing, DDR timing)
that Vivado generates. It is not hand-written and belongs to the board
vendor's package: extract it from
`course_s4_linux/linux_base/Vitis/design_1_wrapper.xsa` in
[alinxalinx/AX7020_2023.1](https://github.com/alinxalinx/AX7020_2023.1)
and place it at `board/xilinx/zynq/zynq-ax7020/ps7_init_gpl.{c,h}`.
Five K&R declarations need `(void)` added for GCC 15
(`-Werror=strict-prototypes`).

## Build

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
