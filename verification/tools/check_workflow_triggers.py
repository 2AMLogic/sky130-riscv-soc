#!/usr/bin/env python3
"""Fail if the workflow triggers drift from the merge-queue contract.

    python3 -I verification/tools/check_workflow_triggers.py [WORKFLOWS_DIR]

For every workflow in .github/workflows (default), asserts the merge-queue
contract (.loom/docs/ci-principles.md §2): merge_group is a declared trigger
with no filters, no trigger is path-filtered, and the concurrency block matches
the canonical contract form exactly — one `group:` expression per workflow
prefix (the pull_request arm, the merge_group arm keyed on
github.event.merge_group.head_sha, and the push/main fallback) and one
`cancel-in-progress:` expression, the pull_request-only form, which is false on
merge_group so a started queue run is never cancelled. Exact match,
fail-closed: any other expression is rejected, since GitHub-expression
semantics cannot be judged by substring inspection. Stdlib only. Exit 1 on any
violation.
"""
import re
import sys
from pathlib import Path

TRIGGER = re.compile(r"^  ([\w-]+):")
FILTER = re.compile(r"^\s+(paths|paths-ignore|branches-ignore):")


def canonical_concurrency(prefix):
    """The exact group and cancel-in-progress expressions accepted for prefix."""
    group = ("${{ github.event_name == 'pull_request' && "
             f"format('{prefix}-pr-{{0}}', github.event.pull_request.number) || "
             "github.event_name == 'merge_group' && "
             f"format('{prefix}-mq-{{0}}', github.event.merge_group.head_sha) || "
             f"'{prefix}-main' }}}}")
    return group, "${{ github.event_name == 'pull_request' }}"


def block(text, key):
    """The lines of a top-level `key:` block: indented children and inner blanks."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.rstrip() == f"{key}:":
            out = []
            for line in lines[i + 1:]:
                if line.strip() and not line[0].isspace():
                    break
                out.append(line)
            while out and not out[-1].strip():
                out.pop()
            return out
    return None


def trigger_errors(path, text):
    errs = []
    on = block(text, "on")
    if on is None:
        return [f"{path.name}: no top-level `on:` block"]
    current = None
    seen_merge_group = False
    for line in on:
        m = TRIGGER.match(line)
        if m:
            current = m.group(1)
            if current == "merge_group":
                seen_merge_group = True
            continue
        if not line.strip():
            continue
        if FILTER.match(line):
            errs.append(f"{path.name}: path filter in the `on:` block: {line.strip()}")
        elif current == "merge_group" and not line.strip().startswith("types:"):
            errs.append(f"{path.name}: merge_group trigger declares a filter: {line.strip()}")
    if not seen_merge_group:
        errs.append(f"{path.name}: merge_group is not a declared trigger")
    return errs


def concurrency_errors(path, text):
    errs = []
    conc = block(text, "concurrency")
    if conc is None:
        return [f"{path.name}: no top-level `concurrency:` block"]
    group = cancel = None
    for line in conc:
        stripped = line.strip()
        if stripped.startswith("group:"):
            group = stripped[len("group:"):].strip()
        elif stripped.startswith("cancel-in-progress:"):
            cancel = stripped[len("cancel-in-progress:"):].strip()
    if not group or not cancel:
        errs.append(f"{path.name}: concurrency is missing group or cancel-in-progress")
        return errs

    prefix = path.stem
    want_group, want_cancel = canonical_concurrency(prefix)
    # Exact match against the canonical contract form: substring inspection of
    # the arms cannot rule out reordered, always-truthy or inverted-polarity
    # drift, so anything that is not exactly this shape is rejected.
    if group != want_group:
        errs.append(f"{path.name}: concurrency.group ({group}) is not the canonical "
                    f"contract form; the only accepted expression is {want_group}")
    if cancel != want_cancel:
        errs.append(f"{path.name}: cancel-in-progress ({cancel}) is not the canonical form "
                    f"({want_cancel}); only the pull_request-only expression is accepted, "
                    f"so a started merge_group run is never cancelled")
    return errs


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".github/workflows")
    workflows = sorted(root.glob("*.yml")) + sorted(root.glob("*.yaml"))
    errs = [f"{root}: no workflows found"] if not workflows else []
    for path in workflows:
        text = path.read_text()
        errs += trigger_errors(path, text)
        errs += concurrency_errors(path, text)
    for err in errs:
        print(err, file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
