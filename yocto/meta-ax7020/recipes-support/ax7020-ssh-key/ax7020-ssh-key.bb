SUMMARY = "Authorised SSH key for the AX7020 maintenance system"
DESCRIPTION = "Installs the operator's public key so the board can be reached \
without a password. Paired with dropbear's -s flag this makes key authentication \
the only way in."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://authorized_keys"

do_install() {
    # dropbear refuses the file if the directory or the file is writable by
    # anyone but the owner.
    install -d -m 0700 ${D}/home/root/.ssh
    install -m 0600 ${WORKDIR}/authorized_keys ${D}/home/root/.ssh/authorized_keys
}

FILES:${PN} = "/home/root/.ssh /home/root/.ssh/authorized_keys"
