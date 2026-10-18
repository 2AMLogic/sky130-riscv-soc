# records

Append-only evidence. A record is never edited after it lands; a later record
supersedes it.

```
records/<kind>/<timestamp>-<sha>/
    provenance.json     required
    ...                 requests, results, logs, a README explaining them
```

- `<kind>`: what was measured, e.g. `toolchain-smoke`, `synthesis`.
- `<timestamp>`: UTC, `YYYYMMDDTHHMMSSZ`. `<sha>`: 7-40 hex chars of the commit
  the run used.
- `provenance.json` is a JSON object with non-empty values for:
  `commit` (full SHA), `pdk_revision` (open_pdks revision), `tool_versions`
  (object, tool name to version, from `scripts/setup-env.sh`'s pins) and
  `command` (the exact command that produced the record).

Records from before this layout (`toolchain-smoke/2026-10-17/`,
`toolchain-smoke/2026-10-18/`) are named `YYYY-MM-DD` and carry a `README.md`
instead; the linter accepts that form only for them, and they are not migrated.
New records use the layout above.

Check with `python3 -I verification/tools/lint_records.py` (also `npm run lint`).
