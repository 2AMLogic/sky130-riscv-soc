#!/usr/bin/env bash
# Build ROM images from RISC-V assembly sources: the one definition of the
# image format. firmware/boot/build.sh and firmware/soc/build.sh are the entry
# points and supply only their directory and their SRC.S:OUT.hex names.
#
#   firmware/build-image.sh DIR SRC.S:OUT.hex [SRC.S:OUT.hex ...] [--check]
#
# Without --check each OUT.hex is written; with it each is rebuilt and compared,
# every mismatch is reported and the exit status is 1 if any differ.
#
# Needs the RISC-V GCC pinned by PIN_RISCV_GCC in scripts/setup-env.sh, as
# $RISCV_PREFIX-gcc (default riscv-none-elf) on PATH.
#
# The format is a hardware contract with rtl/boot_rom.sv (`logic [31:0]
# mem[1024]`): one 32-bit little-endian word per line ($readmemh), padded to
# ROM_WORDS words. Change ROM_WORDS and that array together. The hex files are
# generated: never edit them by hand.
set -euo pipefail

ROM_WORDS=1024                             # must match rtl/boot_rom.sv mem[] depth
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINK_LD="$ROOT/firmware/boot/link.ld"      # the one linker script, shared by all images

CHECK=0; DIR=""; IMAGES=()
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        -*)      echo "build-image.sh: unknown option '$arg'" >&2; exit 2 ;;
        *:*)     IMAGES+=("$arg") ;;
        *)       DIR="$arg" ;;
    esac
done
[[ -n "$DIR" && ${#IMAGES[@]} -gt 0 ]] ||
    { echo "usage: build-image.sh DIR SRC.S:OUT.hex ... [--check]" >&2; exit 2; }

P="${RISCV_PREFIX:-riscv-none-elf}"
command -v "$P-gcc" >/dev/null || { echo "build.sh: $P-gcc not on PATH (see scripts/setup-env.sh --check)" >&2; exit 1; }
cd "$DIR"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
rc=0
for image in "${IMAGES[@]}"; do
    src="${image%%:*}"; out="${image#*:}"
    "$P-gcc" -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -I. \
        -Wl,-T,"$LINK_LD" -Wl,--no-warn-rwx-segments -o "$T/image.elf" "$src"
    "$P-objcopy" -O binary "$T/image.elf" "$T/image.bin"
    python3 -I - "$T/image.bin" "$T/$out" "$((ROM_WORDS * 4))" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
n = int(sys.argv[3])
assert len(b) <= n, f"image {len(b)} bytes exceeds the {n // 1024} KB ROM"
b += bytes(n - len(b))
with open(sys.argv[2], "w") as f:
    for i in range(0, n, 4):
        f.write("%08x\n" % int.from_bytes(b[i:i + 4], "little"))
PY
    if [[ "$CHECK" == 1 ]]; then
        if cmp "$T/$out" "$out"; then echo "$out matches $src"; else rc=1; fi
    else
        cp "$T/$out" "$out"; echo "wrote ${DIR#"$ROOT"/}/$out"
    fi
done
exit $rc
