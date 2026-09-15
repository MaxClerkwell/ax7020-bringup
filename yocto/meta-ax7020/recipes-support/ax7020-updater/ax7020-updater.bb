SUMMARY = "Fetch a Yocto image over the network and kexec into it"
DESCRIPTION = "The maintenance system stays in flash; development images are \
pulled at runtime and started with kexec, so the flash is never rewritten and \
a broken image cannot make the board unbootable. Runs once after boot when \
IMAGE_URL is set in /etc/ax7020-update.conf."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://ax7020-update file://ax7020-update.conf file://ax7020-update.init file://ax7020-update.service"

RDEPENDS:${PN} = "curl ca-certificates kexec busybox coreutils"

inherit update-rc.d systemd

SYSTEMD_SERVICE:${PN} = "ax7020-update.service"
SYSTEMD_AUTO_ENABLE = "enable"

INITSCRIPT_NAME = "ax7020-update"
INITSCRIPT_PARAMS = "start 99 5 ."

do_install() {
    install -d ${D}${bindir} ${D}${sysconfdir} ${D}${sysconfdir}/init.d ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/ax7020-update ${D}${bindir}/ax7020-update
    install -m 0644 ${WORKDIR}/ax7020-update.conf ${D}${sysconfdir}/ax7020-update.conf
    install -m 0755 ${WORKDIR}/ax7020-update.init ${D}${sysconfdir}/init.d/ax7020-update
    install -m 0644 ${WORKDIR}/ax7020-update.service ${D}${systemd_system_unitdir}/
}

CONFFILES:${PN} = "${sysconfdir}/ax7020-update.conf"
FILES:${PN} = "${bindir}/ax7020-update ${sysconfdir}/ax7020-update.conf ${sysconfdir}/init.d/ax7020-update ${systemd_system_unitdir}/ax7020-update.service"
