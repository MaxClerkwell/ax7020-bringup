SUMMARY = "fastapi (pure-Python wheel from PyPI)"
HOMEPAGE = "https://pypi.org/project/fastapi/"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
inherit pypi-wheel
PYPI_WHEEL_URL = "https://files.pythonhosted.org/packages/a4/d4/eb78f7c2648a3585095623f207d7e4b85a1be30347e01e0fdcd1d7d167a9/fastapi-0.111.1-py3-none-any.whl"
SRC_URI[sha256sum] = "4f51cfa25d72f9fbc3280832e84b32494cf186f50158d364a8765aabf22587bf"
RDEPENDS:${PN} += "python3-starlette python3-pydantic python3-typing-extensions python3-python-multipart"
