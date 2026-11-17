# soc_top re-attest: the 0004 record citations, netlist unchanged, 2026-11-17

Re-attest for PR #170 (issue #147): the five `rtl/soc_fabric.sv` and
`rtl/soc_sram_i.sv` sites that cite `spec/decision-records/0004-sram-macro-organization.md`
by bare record number now name the full filename. That is a comments-and-`$error`
-string-only edit, but both files are hash-bound T1 item 1 sources, so the edit
invalidated `attest/item1.json`'s `recorded` digests and CI's `signoff` job
failed with `stale_evidence` on exactly those two members. Per
`manifests/README.md` the remedy is a re-run of `scripts/synth-soc.sh`, not
`klt signoff --attest 1` alone. **Pre-route synthesis only** — no placement,
no routing, no STA, so this record makes **no Fmax or timing claim**.

## What was run

`scripts/synth-soc.sh` **once** on the merged tree (main + the citation
rewrite) with the pinned klt 0.9.1 in a throwaway venv
(`uv pip install klayout-tools==0.9.1` under `/tmp`; the host's dev build was
not used). Two recorded host gotchas were applied: `TMPDIR` unset (klt
synthesize deadlocks in Yosys' abc pass under the loom sandbox `TMPDIR`; same
note as the records this one follows) and the throwaway copy's
`DEFAULT_YOSYS_TIMEOUT_S` raised 300 -> 1800 (2AMLogic/klayout-tools#5773,
the hard-coded watchdog has no override; applied defensively, the run was not
near the limit). `synth_request.json`, `synth_result.json` and
`synth_soc_top.ys` here are the klt request, its unedited JSON output and the
Yosys script it ran.

## Result: the netlist is byte-identical to main's

sha256 `160672fe01c934855b1688b5ef3120acbfecca72446c93efa75c7658fbb9a7b6` —
the same digest recorded in `20261117T002826Z-b3be3df`, reproduced on the
first run with no baseline scratch worktree needed: main's committed netlist
**is** the baseline, and it reproduced byte-for-byte. The citation rewrite
therefore has zero netlist effect (comments and an `$error` message string do
not survive synthesis), and no area, cell-count or logic claim moves. What
changes in the attest chain is exactly the two source digests
(`soc_fabric.sv`, `soc_sram_i.sv`) and the hashes derived from them:
`attest/item1.json`'s `recorded`, `evidence/item1.json`, and the block
manifest's `evidence."1".content_hash` pin (`provenance.input.content_hash`,
the input-set digest — not the evidence envelope's own file hash, which is
what the grader's `content_hash_pin: stale` hint says).

**Gate-level sim:** not re-run. The committed golden transcript
(`soc-gate.log.txt` in `20261117T002826Z-b3be3df`) was produced from a netlist
byte-identical to this one, so it applies verbatim.

## Verification run alongside

All three `signoff.yml` legs reproduce locally with the pinned klt:
`klt signoff --manifest manifests/sky130-riscv-soc.json --check
manifests/sky130-riscv-soc.signoff.json` (match, exit 0), `klt signoff
--attest 1 --inventory attest/item1.json --check evidence/item1.json` (match,
fresh pass), and `klt signoff --attest 10 --inventory attest/item10.json
--check evidence/item10.json` (match, fresh pass — item 10's sources are
untouched by #170). `verification/tools/lint_rtl.sh` passes (9 files, soc_fabric
1024 words).

Append-only. This record **does not supersede**
`20261117T002826Z-b3be3df` — the netlist is the same one; this record only
re-binds the source digests after a comment-only edit and records that the
re-attest was done by re-synthesis, per the split decision in `dfa8476`.
