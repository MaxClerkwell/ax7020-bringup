# U-Boot sources for the Alinx AX7020

Mirror copies of the files added to the mainline U-Boot tree
(`https://source.denx.de/u-boot/u-boot.git`, commit `527115ef6783`, v2026.10-rc2),
which lives at `build/ax7020/uboot/u-boot/`.

| file | destination in the U-Boot tree |
|---|---|
| `zynq-ax7020.dts` | `arch/arm/dts/` (plus an entry in `arch/arm/dts/Makefile`) |
| `alinx_ax7020_defconfig` | `configs/` |
| `ps7_init_gpl.{c,h}` | `board/xilinx/zynq/zynq-ax7020/` |

`ps7_init_gpl.*` comes from the Alinx package
(`AX7020_2023.1/course_s4_linux/linux_base/Vitis/design_1_wrapper.xsa`), with five
K&R declarations changed to `(void)` for GCC 15.

Build:

```bash
cd build/ax7020/uboot/u-boot
make alinx_ax7020_defconfig
scripts/config --disable TOOLS_MKEFICAPSULE
make olddefconfig
make -j$(nproc) CROSS_COMPILE=arm-none-eabi-
```

**The full story — hardware facts, device-tree rationale, QSPI layout, host
setup, flashing procedure and the gotchas that cost the most time — is in the
[top-level README](../README.md).**
