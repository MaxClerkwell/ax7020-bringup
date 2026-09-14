# The board's I2C buses are routed to EMIO, so the RTC sits behind the
# programmable logic and Linux cannot read it without a bitstream. Without a
# clock every TLS certificate looks "not yet valid", so the maintenance system
# needs to fetch the time before it can fetch anything over HTTPS.
#
# busybox already ships an ntpd applet, poky just leaves it disabled.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:ax7020 = " file://ntpd.cfg"
