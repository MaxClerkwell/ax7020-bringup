SUMMARY = "uvicorn (pure-Python wheel from PyPI)"
HOMEPAGE = "https://pypi.org/project/uvicorn/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/BSD-3-Clause;md5=550794465ba0ec5312d6919e203a55f9"
inherit pypi-wheel
PYPI_WHEEL_URL = "https://files.pythonhosted.org/packages/f5/8e/cdc7d6263db313030e4c257dd5ba3909ebc4e4fb53ad62d5f09b1a2f5458/uvicorn-0.30.6-py3-none-any.whl"
SRC_URI[sha256sum] = "65fd46fe3fda5bdc1b03b94eb634923ff18cd35b2f084813ea79d1f103f711b5"
RDEPENDS:${PN} += "python3-click python3-h11 python3-asyncio python3-logging python3-json python3-netclient python3-multiprocessing"
