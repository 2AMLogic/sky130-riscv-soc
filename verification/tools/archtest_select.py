#!/usr/bin/env python3
"""List the tests ACT4 selects for a configuration, and why it rejects the rest.

    uv run --frozen --directory <riscv-arch-test> python archtest_select.py \
        TEST_CONFIG.yaml --test-dir tests --workdir WORKDIR > selection.json

Runs inside riscv-arch-test's own Python environment (scripts/build-archtest.sh
does): it imports the framework's `act` package and calls the same functions
`act` itself uses to choose tests -- generate_test_dict, prepare_dut_outputs
and select_tests -- so the selected set printed here is the set `act` builds.
`act` only says which tests it took; for every other candidate test this tool
names each criterion of select_tests the test fails, re-derived from the
test's YAML header and the UDB configuration:

  harts          the test needs more harts than the configuration has
  privilege      privileged tests are disabled (include_priv_tests: false)
  experimental   the test needs an extension ACT treats as experimental
  forbidden      the test forbids an extension the configuration implements
  extension      the test needs an extension the configuration does not implement
  parameter      a test parameter does not match the configuration's value

The tool exits 1 if the set it finds unopposed differs from select_tests', so
the reasons can never describe a selection other than the one that ran.  The
output is JSON: the implemented extensions, the configuration parameters and
two lists, `selected` (names) and `deselected` ({name, reasons}).
"""
import json
import sys
from pathlib import Path

from ruamel.yaml import YAML

from act.config import load_config
from act.parse_test_constraints import ExtensionRequirement, TestMetadata, generate_test_dict
from act.parse_udb_config import get_config_params, get_implemented_extensions, prepare_dut_outputs
from act.select_tests import PRIV_EXTENSIONS, _compare_param, _requires_extension_from, select_tests
from act.toolchain import EXPERIMENTAL_EXTENSIONS


def describe(requirement: ExtensionRequirement) -> str:
    """One extension, or the alternatives of a requirement that accepts any of them."""
    if isinstance(requirement, str):
        return requirement
    return "(" + " or ".join(sorted(requirement)) + ")"


def met(requirement: ExtensionRequirement, implemented: frozenset[str]) -> bool:
    if isinstance(requirement, str):
        return requirement in implemented
    return not requirement.isdisjoint(implemented)


def deselect_reasons(
    metadata: TestMetadata,
    implemented: frozenset[str],
    params: dict,
    harts: int,
    *,
    include_priv_tests: bool = True,
    enable_experimental_extensions: bool = False,
) -> list[str]:
    """Every select_tests criterion `metadata` fails, most fundamental first."""
    reasons = []
    if harts < metadata.min_harts:
        reasons.append(f"harts: needs {metadata.min_harts}, the configuration has {harts}")
    if not include_priv_tests and _requires_extension_from(metadata.required_extensions, PRIV_EXTENSIONS):
        reasons.append("privilege: privileged tests are disabled")
    if not enable_experimental_extensions and _requires_extension_from(
        metadata.required_extensions, EXPERIMENTAL_EXTENSIONS
    ):
        reasons.append("experimental: needs " + ", ".join(sorted(EXPERIMENTAL_EXTENSIONS)))
    forbidden = sorted(metadata.forbidden_extensions & implemented)
    if forbidden:
        reasons.append("forbidden: the configuration implements " + ", ".join(forbidden))
    missing = [describe(r) for r in sorted(metadata.required_extensions, key=describe) if not met(r, implemented)]
    if missing:
        reasons.append("extension: needs " + ", ".join(missing) + ", which the configuration does not implement")
    for param, wanted in metadata.params.items():
        if param not in params:
            reasons.append(f"parameter: {param} is not a parameter of the configuration")
        elif not _compare_param(wanted, params[param]):
            reasons.append(f"parameter: {param} is {params[param]!r} in the configuration, the test needs {wanted!r}")
    return reasons


def main() -> int:
    args = sys.argv[1:]
    if len(args) != 5 or args[1] != "--test-dir" or args[3] != "--workdir":
        print(__doc__.split("\n\n", 1)[1].strip(), file=sys.stderr)
        return 2
    config_file, test_dir, workdir = (Path(a).absolute() for a in (args[0], args[2], args[4]))

    config = load_config(config_file)
    # prepare_dut_outputs prints its progress to stdout; keep stdout for the JSON.
    stdout = sys.stdout
    sys.stdout = sys.stderr
    try:
        prepare_dut_outputs([config], workdir, jobs=1, verbose=False)
    finally:
        sys.stdout = stdout
    implemented = get_implemented_extensions(workdir / config.name / "env" / "extensions.txt")
    params = get_config_params(config.udb_config)

    candidates = generate_test_dict(test_dir, "all")
    selected = select_tests(
        candidates,
        implemented,
        params,
        harts=config.harts,
        include_priv_tests=config.include_priv_tests,
    )
    rejected = [
        {
            "name": name,
            "reasons": deselect_reasons(
                candidates[name],
                implemented,
                params,
                config.harts,
                include_priv_tests=config.include_priv_tests,
            ),
        }
        for name in sorted(candidates)
        if name not in selected
    ]
    rejected_names = {entry["name"] for entry in rejected}
    unexplained = [entry["name"] for entry in rejected if not entry["reasons"]]
    # A test fails select_tests exactly when it fails one of its criteria: the
    # two partitions must therefore be each other's complement.
    if unexplained or set(candidates) - rejected_names != set(selected):
        print("selection and derived reasons disagree", unexplained[:5], file=sys.stderr)
        return 1

    yaml_params = YAML(typ="safe", pure=True).load(config.udb_config.read_text())["params"]
    print(
        json.dumps(
            {
                "config": config.name,
                "implemented_extensions": sorted(implemented),
                "params": {key: yaml_params[key] for key in sorted(yaml_params)},
                "selected": sorted(selected),
                "deselected": rejected,
            },
            indent=1,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
