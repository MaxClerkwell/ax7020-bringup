SUMMARY = "python-multipart (pure-Python wheel from PyPI)"
HOMEPAGE = "https://pypi.org/project/python-multipart/"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"
inherit pypi-wheel
PYPI_WHEEL_URL = "https://files.pythonhosted.org/packages/3d/47/444768600d9e0ebc82f8e347775d24aef8f6348cf00e9fa0e81910814e6d/python_multipart-0.0.9-py3-none-any.whl"
SRC_URI[sha256sum] = "97ca7b8ea7b05f977dc3849c3ba99d51689822fab725c3703af7c866a0c2b215"
RDEPENDS:${PN} += "python3-io"
