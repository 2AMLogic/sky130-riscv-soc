"""Print the cocotb version reported by the selected klt functional-verification runner."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def main(klt):
    # The executable can be a symlink or a launcher. Ask klt for its own
    # environment report with a zero-time test that needs no ACT4 build.
    with tempfile.TemporaryDirectory(prefix="act4-cocotb-") as tmp:
        root = Path(tmp)
        (root / "probe.sv").write_text("module probe; endmodule\n")
        (root / "probe_test.py").write_text(
            "import cocotb\n\n@cocotb.test()\nasync def ready(dut):\n    pass\n"
        )
        request = root / "request.json"
        request.write_text(json.dumps({
            "schema": "klt.functional_verification.request/1",
            "engine": "icarus",
            "hdl_toplevel": "probe",
            "sources": ["probe.sv"],
            "testbench": {"module": "probe_test"},
        }))
        result = subprocess.run(
            [klt, "functional-verification", str(request), "-o", str(root / "sim"), "--format", "json"],
            stdout=subprocess.PIPE, text=True,
        )
        if result.returncode:
            return result.returncode
        print(json.loads(result.stdout)["environment"]["cocotb_version"])
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
