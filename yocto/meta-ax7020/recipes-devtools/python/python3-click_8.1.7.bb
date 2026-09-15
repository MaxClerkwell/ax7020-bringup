SUMMARY = "click (pure-Python wheel from PyPI)"
HOMEPAGE = "https://pypi.org/project/click/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/BSD-3-Clause;md5=550794465ba0ec5312d6919e203a55f9"
inherit pypi-wheel
PYPI_WHEEL_URL = "https://files.pythonhosted.org/packages/00/2e/d53fa4befbf2cfa713304affc7ca780ce4fc1fd8710527771b58311a3229/click-8.1.7-py3-none-any.whl"
SRC_URI[sha256sum] = "ae74fb96c20a0277a1d615f1e4d73c8414f5a98db8b799a7931d1582f3390c28"
RDEPENDS:${PN} += "python3-io python3-threading python3-terminal"
