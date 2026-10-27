# Block manifest and signoff record

- `sky130-riscv-soc.json` — the block manifest. `evidence` cites item 6 as a
  hash-bound "not applicable" (`spec/soc.rows.json` +
  `spec/statistical-claims-na.json`; human-readable
  `spec/statistical-claims-na.md`) and item 9 (the envelope below). Edit either
  item-6 JSON and the hashes here must be refreshed in the same change. The
  `verification/records/toolchain-smoke/` records are
  toolchain evidence only and must not be cited.
- `sky130-riscv-soc.attest9.inventory.json` — the T1 item 9 inventory: every
  bench under `verification/tests/`, the cold-start command, the PDK revision
  and the tool versions.
- `sky130-riscv-soc.attest9.json` — the `klt signoff --attest 9` envelope for
  that inventory. The manifest pins its `content_hash`.
- `sky130-riscv-soc.signoff.json` — the verbatim output of `klt signoff` on
  that manifest, on the klt pinned in `scripts/setup-env.sh`
  (`PIN_KLT_SHA`, the only place the pin lives).

## Regenerate

Use a throwaway environment, never a host-wide install:

```bash
SHA="$(sed -n 's/^PIN_KLT_SHA="\([0-9a-f]\{40\}\)".*/\1/p' scripts/setup-env.sh)"
uvx --from "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@${SHA}" \
  klt signoff --manifest manifests/sky130-riscv-soc.json --format json \
  > manifests/sky130-riscv-soc.signoff.json
```

A plain render exits **3** while any T1 item is unmet. That is expected, not
an error: the tier is `null` until every item is met.

## Attest item 9

Run on a host where the cold start works (`scripts/setup-env.sh --check` ok,
`scripts/fetch-cve2.sh && scripts/convert-cve2.sh` done, cocotb and sv2v on
`PATH`). `uvx` puts its own Python first, so point the Makefile at the one
with cocotb:

```bash
PYTHON_BIN=/path/to/venv/bin/python3 \
uvx --from "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@${SHA}" \
  klt signoff --attest 9 --inventory manifests/sky130-riscv-soc.attest9.inventory.json \
  -o manifests/sky130-riscv-soc.attest9.json
```

Put the envelope's `provenance.input.content_hash` (the inventory's SHA-256 of
raw bytes) in the manifest's `evidence.9`, then regenerate the report. Any
inventory edit changes that hash: re-attest, update the manifest, regenerate.

## Check (what CI runs)

```bash
uvx --from "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@${SHA}" \
  klt signoff --manifest manifests/sky130-riscv-soc.json \
  --check manifests/sky130-riscv-soc.signoff.json
```

Exit 0 means the committed report reproduces (the `build` block is excluded
from the comparison). With `--check`, exit **3 means drift** and fails the job.

CI also re-attests item 9 with `--attest 9 --inventory … --check
manifests/sky130-riscv-soc.attest9.json`. The `cold_start` is `local_only`
(needs cocotb, sv2v and the converted CVE2), so CI re-runs the file-hash and pin
checks and carries the cold-start outcome from the committed envelope; it shows
as `[SKIP]`. The cold start itself is only re-proved by a local re-attestation.

A klt pin bump lands in the same change as a regenerated report.
