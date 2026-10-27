# Block manifest and signoff record

- `sky130-riscv-soc.json` — the block manifest. `evidence` cites T1 item 10
  (`evidence/item10.json`, produced from `attest/item10.json`) and item 6 as a
  hash-bound "not applicable" (`spec/soc.rows.json` +
  `spec/statistical-claims-na.json`; human-readable
  `spec/statistical-claims-na.md`). Edit either JSON and the hashes here must
  be refreshed in the same change. The `verification/records/toolchain-smoke/` records are
  toolchain evidence only and must not be cited.
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
an error: the tier is `null` until evidence is cited.

## Check (what CI runs)

```bash
uvx --from "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@${SHA}" \
  klt signoff --manifest manifests/sky130-riscv-soc.json \
  --check manifests/sky130-riscv-soc.signoff.json
```

Exit 0 means the committed report reproduces (the `build` block is excluded
from the comparison). With `--check`, exit **3 means drift** and fails the job.

The `signoff` workflow also re-attests item 10 with
`klt signoff --attest 10 --inventory attest/item10.json --check evidence/item10.json`
(exit 3 = drift, e.g. after editing `README.md` or a workflow without
re-attesting). `local_only` checks are skipped there and run by `ci.yml`.

A klt pin bump lands in the same change as a regenerated report.
