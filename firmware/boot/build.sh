#!/usr/bin/env bash
# Build the boot ROM image from firmware/boot/boot.S.
#
#   firmware/boot/build.sh           write firmware/boot/boot_rom.hex
#   firmware/boot/build.sh --check   rebuild and fail if the checked-in hex differs
#
# Needs the RISC-V GCC pinned by PIN_RISCV_GCC in scripts/setup-env.sh, as
# $RISCV_PREFIX-gcc (default riscv-none-elf) on PATH. Output is one 32-bit
# little-endian word per line ($readmemh), padded to 1024 words. The hex is a
# generated file: never edit it by hand.
set -euo pipefail
cd "$(dirname "$0")"
P="${RISCV_PREFIX:-riscv-none-elf}"
command -v "$P-gcc" >/dev/null || { echo "build.sh: $P-gcc not on PATH (see scripts/setup-env.sh --check)" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
"$P-gcc" -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,--no-warn-rwx-segments \
    -o "$T/boot.elf" boot.S
"$P-objcopy" -O binary "$T/boot.elf" "$T/boot.bin"
python3 -I - "$T/boot.bin" "$T/boot_rom.hex" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
assert len(b) <= 4096, f"image {len(b)} bytes exceeds the 4 KB ROM"
b += bytes(4096 - len(b))
with open(sys.argv[2], "w") as f:
    for i in range(0, 4096, 4):
        f.write("%08x\n" % int.from_bytes(b[i:i + 4], "little"))
PY
if [[ "${1:-}" == "--check" ]]; then
    cmp "$T/boot_rom.hex" boot_rom.hex && echo "boot_rom.hex matches boot.S"
else
    cp "$T/boot_rom.hex" boot_rom.hex; echo "wrote firmware/boot/boot_rom.hex"
fi
