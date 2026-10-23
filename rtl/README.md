# rtl

SoC integration RTL: the OBI crossbar, SRAM wrappers, boot ROM, peripherals and
the top level. The core is not copied in by hand; it is fetched at the pinned
upstream commit recorded in [`../reuse.lock.json`](../reuse.lock.json).
`verification/tools/lint_rtl.sh` lints whatever `.v`/`.sv` files appear here.

## Memory fabric (SoC RTL step 1b)

| File | Role |
|---|---|
| `obi_xbar.sv` | 2-manager (instruction, data) x 4-subordinate crossbar, address decode per `spec/soc.md` § Memory map, fixed instruction-manager priority at the boot ROM |
| `obi_err_resp.sv` | error responder: grants at once, answers with an OBI error one cycle later |
| `boot_rom.sv`, `boot_rom.hex` | 4 KB boot ROM; image is the checked-in hex source (`+rom_hex=` overrides in simulation); placeholder content until firmware lands |
| `soc_sram_i.sv`, `soc_sram_d.sv` | behavioural I-SRAM (1rw1r) and D-SRAM (1rw), 32-bit, 8-bit write mask, OpenRAM-style ports; the macro instance (spec row 8a) replaces only the bodies |
| `soc_fabric.sv` | crossbar + memories + peripheral window stub (errors on every access); the SoC top connects the core here |
| `rst_sync.sv` | two-flop reset synchroniser (async assert, sync deassert) |

Fabric conventions (not in the spec): every subordinate grants and responds
exactly one cycle after the request, so responses return in order with no id
tracking; the instruction manager is read-only, so its writes, and any data
write to the boot ROM, get an OBI error. Tests: `make -C verification xbar`.
