SUMMARY = "uv - Python package and project manager (prebuilt static binary)"
HOMEPAGE = "https://github.com/astral-sh/uv"
LICENSE = "MIT | Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# The musl build is fully static; no Rust toolchain in the build, no runtime deps.
SRC_URI = "https://github.com/astral-sh/uv/releases/download/${PV}/uv-armv7-unknown-linux-musleabihf.tar.gz"
SRC_URI[sha256sum] = "54e2c10e4e6c18a3efbac645ea02d7e6b768ae2f975275595915a7039e802b75"
COMPATIBLE_HOST = "arm.*-linux.*"
S = "${WORKDIR}/uv-armv7-unknown-linux-musleabihf"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/uv ${S}/uvx ${D}${bindir}/
}

INSANE_SKIP:${PN} += "already-stripped ldflags file-rdeps arch"
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
