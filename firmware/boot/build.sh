#!/usr/bin/env bash
# Build the boot ROM image from firmware/boot/boot.S.
#
#   firmware/boot/build.sh           write firmware/boot/boot_rom.hex
#   firmware/boot/build.sh --check   rebuild and fail if the checked-in hex differs
#
# The boot entry point to firmware/build-image.sh, supplying only its directory
# and its source and output names; the image format, the compiler requirement
# and --check are defined there. The hex is generated: never edit it by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$ROOT/firmware/build-image.sh" "$ROOT/firmware/boot" \
    boot.S:boot_rom.hex "$@"
