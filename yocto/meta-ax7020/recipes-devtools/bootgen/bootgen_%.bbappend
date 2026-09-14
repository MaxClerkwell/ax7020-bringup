# bootgen's C sources predate GCC 14, which turned -Wincompatible-pointer-types
# from a warning into an error:
#   utils/src/cdo-load.c:140:14: error: assignment to 'char *' from incompatible
#   pointer type 'uint32_t *'
# Debian 13 ships GCC 15, so the build stops there. Relax just that diagnostic.
#
# We do not actually use bootgen - boot.bin comes from mainline U-Boot's SPL
# (see uboot/ and the README) - but it is pulled in by meta-xilinx' dependency
# chain, so it has to compile.

CFLAGS:append = " -Wno-incompatible-pointer-types"
BUILD_CFLAGS:append = " -Wno-incompatible-pointer-types"
