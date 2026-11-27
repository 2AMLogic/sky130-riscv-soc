# ACT4 simulation at `ab320f4`

The bench verified the SHA-256 digest of each flattened image before loading it into RAM.
Of the 132 selected tests, **131 passed, one failed, and zero were skipped**.
`priv/Sm/Sm_mcsr_cntr-00` reproduced case 547 from #221. Reading `timeh` yielded
`0x40001fbd` against Sail’s expected `0x0200bfb5`.

The negative test ran first from a checkout without `verification/sim_build`.
It verified the original image of `rv32i/I/I-add-00`, changed the first reference
result in memory, and observed ACT4’s failure halt. The full suite then loaded
the original images from the same build. klt returned 3 for the suite and GNU Make returned 2.

Reproduce with the pinned ACT4 toolchain from the repository root.

```sh
make -k -C verification archtest-negative archtest ARCHTEST_REPORT="$PWD/report.json"
```

`manifest.json` identifies both the flattened images and their source ELFs.
`report.json` and `archtest-negative.json` are the two klt reports. The three
files prefixed with `negative-` are the negative run’s transcripts and results.
`provenance.json` records the input hashes and tool versions. The [original
record](../20261126T222213Z-534a1a7/README.md) describes the DUT configuration and the failure.
