# rtl

SoC integration RTL: the OBI crossbar, SRAM wrappers, boot ROM, peripherals and
the top level. The core is not copied in by hand; it is fetched at the pinned
upstream commit recorded in [`../reuse.lock.json`](../reuse.lock.json). The
tree is empty until the RTL lands; `verification/tools/lint_rtl.sh` lints
whatever `.v`/`.sv` files appear here.
