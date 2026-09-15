# Install a pure-Python wheel from PyPI without building it. scarthgap lacks
# the pdm-backend class that fastapi needs, and for py3-none-any wheels a
# build step adds nothing: a wheel is a zip of the site-packages tree.
#
#   PYPI_WHEEL_NAME   file name on PyPI (defaults from PYPI_PACKAGE and PV)
#   PYPI_WHEEL_URL    full URL (defaults to files.pythonhosted.org/...)
PYPI_PACKAGE ?= "${@d.getVar('BPN').replace('python3-', '', 1)}"
PYPI_WHEEL_NAME ?= "${@d.getVar('PYPI_PACKAGE').replace('-', '_')}-${PV}-py3-none-any.whl"
PYPI_WHEEL_URL ?= "https://files.pythonhosted.org/packages/py3/${@d.getVar('PYPI_PACKAGE')[0]}/${PYPI_PACKAGE}/${PYPI_WHEEL_NAME}"
SRC_URI = "${PYPI_WHEEL_URL};downloadfilename=${PYPI_WHEEL_NAME};unpack=0"
S = "${WORKDIR}"
DEPENDS += "unzip-native"
inherit python3-dir python3targetconfig
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    unzip -q -o ${WORKDIR}/${PYPI_WHEEL_NAME} -d ${D}${PYTHON_SITEPACKAGES_DIR}
}
FILES:${PN} += "${PYTHON_SITEPACKAGES_DIR}"
RDEPENDS:${PN} += "python3-core"
