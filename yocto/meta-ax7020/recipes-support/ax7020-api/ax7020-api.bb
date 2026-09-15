SUMMARY = "REST API that loads bitstreams into the PL through the FPGA manager"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://app.py file://empty.bin file://ax7020-api.service"

RDEPENDS:${PN} = "python3-core python3-fastapi python3-uvicorn python3-python-multipart"

inherit systemd
SYSTEMD_SERVICE:${PN} = "ax7020-api.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}/opt/ax7020-api ${D}${nonarch_base_libdir}/firmware ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/app.py ${D}/opt/ax7020-api/app.py
    # PS7-only design; DELETE /bitstream loads it to clear the PL
    install -m 0644 ${WORKDIR}/empty.bin ${D}${nonarch_base_libdir}/firmware/empty.bin
    install -m 0644 ${WORKDIR}/ax7020-api.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "/opt/ax7020-api ${nonarch_base_libdir}/firmware/empty.bin ${systemd_system_unitdir}/ax7020-api.service"
