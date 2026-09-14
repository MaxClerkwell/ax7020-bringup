# Add the AX7020 device tree to the kernel tree.
#
# KERNEL_DEVICETREE names xilinx/zynq-ax7020.dtb, so the .dts has to sit in
# arch/arm/boot/dts/xilinx/ and be listed in that directory's Makefile.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:ax7020 = " file://zynq-ax7020.dts file://ax7020.cfg"

do_configure:prepend:ax7020() {
    dtsdir="${S}/arch/arm/boot/dts/xilinx"
    [ -d "$dtsdir" ] || dtsdir="${S}/arch/arm/boot/dts"

    # scarthgap unpacks into WORKDIR; UNPACKDIR only exists from 5.1 on
    src="${UNPACKDIR}/zynq-ax7020.dts"
    [ -f "$src" ] || src="${WORKDIR}/zynq-ax7020.dts"
    install -m 0644 "$src" "$dtsdir/zynq-ax7020.dts"

    if ! grep -q 'zynq-ax7020.dtb' "$dtsdir/Makefile"; then
        echo 'dtb-$(CONFIG_ARCH_ZYNQ) += zynq-ax7020.dtb' >> "$dtsdir/Makefile"
    fi
}
