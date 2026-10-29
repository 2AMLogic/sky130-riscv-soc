# boot: default and ISRAM_1RW=1 / 1024-word configurations (simulation)

Issue #59, the boot-level evidence that PR #58 (closes #52) landed without.
**Simulation evidence only. It says nothing about timing.**

| Run | Result |
| --- | --- |
| `make -C verification boot` (defaults: `ISRAM_AW=DSRAM_AW=11`, `ISRAM_1RW=0`) | 3/3 PASS (`boot.log.txt`) |
| `make -C verification boot-1rw` (`ISRAM_1RW=1`, `ISRAM_AW=DSRAM_AW=10`) | 3/3 PASS (`boot-1rw.log.txt`) |
| `LINT_REQUIRE_CORE=1 verification/tools/lint_rtl.sh` | `rtl lint: ok (9 files ...)` (`lint_rtl.log.txt`) |

- The parameter overrides took effect: `boot-1rw.log.txt` shows the iverilog
  command line with `-Psoc_top.ISRAM_1RW=1 -Psoc_top.ISRAM_AW=10
  -Psoc_top.DSRAM_AW=10`; `boot.log.txt` has no `-P` flags. Both runs use the same
  `test_boot.py` and `firmware/boot/boot_rom.hex`, unmodified.
- The core was converted on the run host with the pinned `sv2v` v0.0.13 from
  the CVE2 commit in `reuse.lock.json`; its sha256 is in `provenance.json`.
  cocotb was the pin (2.0.1) in a worktree-local venv; the host's 2.1.0 was
  not used.
- Not covered: the riscv-arch-test suite does not exist yet, so the arch-test
  part of #52 criterion (d) remains unmet. `boot` checks the ROM-to-SRAM fetch
  only through the firmware signature.
