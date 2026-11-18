"""Test for check_workflow_triggers.py: the committed workflows pass, contract drift fails.

    python3 -I verification/tools/tests/test_check_workflow_triggers.py
"""
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHECK = HERE.parent / "check_workflow_triggers.py"
WORKFLOWS = HERE.parents[2] / ".github" / "workflows"

GROUP_LINE = ("  group: ${{ github.event_name == 'pull_request' && "
              "format('ci-pr-{0}', github.event.pull_request.number) || "
              "github.event_name == 'merge_group' && "
              "format('ci-mq-{0}', github.event.merge_group.head_sha) || 'ci-main' }}\n")

CANCEL_LINE = "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}\n"

GOOD = (
    "name: ci\n"
    "on:\n"
    "  pull_request:\n"
    "  merge_group:\n"
    "  push:\n"
    "    branches: [main]\n"
    "\n"
    "concurrency:\n"
    + GROUP_LINE +
    CANCEL_LINE
)

SHARED_GROUP = (
    "  group: ${{ github.event_name == 'pull_request' && "
    "format('ci-pr-{0}', github.event.pull_request.number) || 'ci-main' }}\n"
)

EMPTY_GROUP = (
    "  group: ${{ github.event_name == 'pull_request' && "
    "format('ci-pr-{0}', github.event.pull_request.number) || "
    "github.event_name == 'merge_group' && "
    "format('ci-mq-{0}', github.event.merge_group.head_sha) }}\n"
)

TRUTHY_ARM_GROUP = (
    "  group: ${{ 'ci-main' || github.event_name == 'pull_request' && "
    "format('ci-pr-{0}', github.event.pull_request.number) || "
    "github.event_name == 'merge_group' && "
    "format('ci-mq-{0}', github.event.merge_group.head_sha) }}\n"
)


def run(workflows):
    return subprocess.run([sys.executable, "-I", str(CHECK), str(workflows)],
                          capture_output=True, text=True)


@contextmanager
def workflows_dir(files):
    with tempfile.TemporaryDirectory() as d:
        for name, text in files.items():
            (Path(d) / name).write_text(text)
        yield d


class CheckWorkflowTriggers(unittest.TestCase):
    def check_rejected(self, text, want):
        with workflows_dir({"ci.yml": text}) as d:
            r = run(d)
            self.assertEqual(r.returncode, 1, r.stderr)
            self.assertIn(want, r.stderr)

    def test_committed_workflows_pass(self):
        self.assertEqual(run(WORKFLOWS).returncode, 0, run(WORKFLOWS).stderr)

    def test_good_fixture_passes(self):
        with workflows_dir({"ci.yml": GOOD, "signoff.yml": GOOD.replace("ci-", "signoff-")}) as d:
            self.assertEqual(run(d).returncode, 0, run(d).stderr)

    def test_missing_merge_group_rejected(self):
        self.check_rejected(GOOD.replace("  merge_group:\n", "", 1),
                            "merge_group is not a declared trigger")

    def test_pull_request_path_filter_rejected(self):
        self.check_rejected(
            GOOD.replace("  pull_request:\n",
                         "  pull_request:\n    paths:\n      - 'rtl/**'\n", 1),
            "path filter in the `on:` block")

    def test_merge_group_filter_rejected(self):
        self.check_rejected(
            GOOD.replace("  merge_group:\n",
                         "  merge_group:\n    branches:\n      - main\n", 1),
            "merge_group trigger declares a filter")

    def test_group_shared_with_push_rejected(self):
        self.check_rejected(GOOD.replace(GROUP_LINE, SHARED_GROUP),
                            "is not the canonical contract form")

    def test_group_empty_without_fallback_rejected(self):
        self.check_rejected(GOOD.replace(GROUP_LINE, EMPTY_GROUP),
                            "is not the canonical contract form")

    def test_group_always_truthy_first_arm_rejected(self):
        # 'ci-main' is a truthy first arm of ||, so every event — PR, queue
        # entry and push — would share the ci-main group.
        self.check_rejected(GOOD.replace(GROUP_LINE, TRUTHY_ARM_GROUP),
                            "is not the canonical contract form")

    def test_cancel_literal_true_rejected(self):
        self.check_rejected(GOOD.replace(CANCEL_LINE, "  cancel-in-progress: true\n"),
                            "is not the canonical form")

    def test_cancel_true_on_push_rejected(self):
        # inverted polarity: true exactly on merge_group, where a started queue
        # run would be cancelled. Rejected by exact match, not by a keyword.
        self.check_rejected(
            GOOD.replace(CANCEL_LINE,
                         "  cancel-in-progress: ${{ github.event_name != 'pull_request' }}\n"),
            "is not the canonical form")

    def test_cancel_or_main_ref_rejected(self):
        # same polarity family: true on pull_request and on every other event
        self.check_rejected(
            GOOD.replace(
                CANCEL_LINE,
                "  cancel-in-progress: ${{ github.event_name == 'pull_request' "
                "|| github.ref != 'refs/heads/main' }}\n"),
            "is not the canonical form")

    def test_cancel_literal_false_rejected(self):
        # fail-closed: even the safe literal false is not the canonical form
        self.check_rejected(GOOD.replace(CANCEL_LINE, "  cancel-in-progress: false\n"),
                            "is not the canonical form")

    def test_group_prefix_not_workflow_name_rejected(self):
        with workflows_dir({"other.yml": GOOD}) as d:
            r = run(d)
            self.assertEqual(r.returncode, 1, r.stderr)
            self.assertIn("is not the canonical contract form", r.stderr)

    def check_passes(self, text):
        with workflows_dir({"ci.yml": text}) as d:
            self.assertEqual(run(d).returncode, 0, run(d).stderr)


if __name__ == "__main__":
    unittest.main()
