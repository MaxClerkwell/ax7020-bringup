SUMMARY = "starlette (pure-Python wheel from PyPI)"
HOMEPAGE = "https://pypi.org/project/starlette/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/BSD-3-Clause;md5=550794465ba0ec5312d6919e203a55f9"
inherit pypi-wheel
PYPI_WHEEL_URL = "https://files.pythonhosted.org/packages/fd/18/31fa32ed6c68ba66220204ef0be798c349d0a20c1901f9d4a794e08c76d8/starlette-0.37.2-py3-none-any.whl"
SRC_URI[sha256sum] = "6fe59f29268538e5d0d182f2791a479a0c64638e6935d1c6989e63fb2699c6ee"
RDEPENDS:${PN} += "python3-anyio python3-typing-extensions python3-json python3-asyncio python3-netclient python3-io"
