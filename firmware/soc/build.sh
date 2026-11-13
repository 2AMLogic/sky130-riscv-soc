#!/usr/bin/env bash
# Build the SoC test ROM images (banner, echo, gpio, timer) from firmware/soc/*.S.
#
#   firmware/soc/build.sh           write firmware/soc/<name>.hex for each image
#   firmware/soc/build.sh --check   rebuild and fail if a checked-in hex differs
#
# The SoC entry point to firmware/build-image.sh, supplying only its directory
# and its source and output names; the image format, the compiler requirement
# and --check are defined there. CI simulates the checked-in hex and does not
# install the compiler. The hex files are generated: never edit them by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$ROOT/firmware/build-image.sh" "$ROOT/firmware/soc" \
    banner.S:banner.hex \
    echo.S:echo.hex \
    gpio.S:gpio.hex \
    timer.S:timer.hex "$@"
