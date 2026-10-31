#!/usr/bin/env bash
# Build the SoC test ROM images (banner, echo, gpio, timer) from firmware/soc/*.S.
#
#   firmware/soc/build.sh           write firmware/soc/<name>.hex for each image
#   firmware/soc/build.sh --check   rebuild and fail if a checked-in hex differs
#
# Needs the RISC-V GCC pinned by PIN_RISCV_GCC in scripts/setup-env.sh, as
# $RISCV_PREFIX-gcc (default riscv-none-elf) on PATH. Same image format as
# firmware/boot/build.sh: one little-endian 32-bit word per line ($readmemh),
# padded to 1024 words. The hex files are generated: never edit them by hand.
# CI simulates the checked-in hex and does not install the compiler.
set -euo pipefail
cd "$(dirname "$0")"
P="${RISCV_PREFIX:-riscv-none-elf}"
command -v "$P-gcc" >/dev/null || { echo "build.sh: $P-gcc not on PATH (see scripts/setup-env.sh --check)" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
rc=0
for name in banner echo gpio timer; do
    "$P-gcc" -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -I. \
        -Wl,-T,../boot/link.ld -Wl,--no-warn-rwx-segments \
        -o "$T/$name.elf" "$name.S"
    "$P-objcopy" -O binary "$T/$name.elf" "$T/$name.bin"
    python3 -I - "$T/$name.bin" "$T/$name.hex" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
assert len(b) <= 4096, f"image {len(b)} bytes exceeds the 4 KB ROM"
b += bytes(4096 - len(b))
with open(sys.argv[2], "w") as f:
    for i in range(0, 4096, 4):
        f.write("%08x\n" % int.from_bytes(b[i:i + 4], "little"))
PY
    if [[ "${1:-}" == "--check" ]]; then
        if cmp "$T/$name.hex" "$name.hex"; then echo "$name.hex matches $name.S"; else rc=1; fi
    else
        cp "$T/$name.hex" "$name.hex"; echo "wrote firmware/soc/$name.hex"
    fi
done
exit $rc
