"""Behavior tests for the portable regression orchestrator."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "run_all.py"


def load_module():
    spec = importlib.util.spec_from_file_location("run_all", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class RunAllTests(unittest.TestCase):
    def test_failure_is_logged_and_prevents_later_runner(self):
        run_all = load_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            marker = output / "must-not-run.txt"
            specs = [
                run_all.Runner("first", (sys.executable, "-c", "print('first ok')")),
                run_all.Runner(
                    "broken",
                    (sys.executable, "-c", "import sys; print('broken output'); sys.exit(7)"),
                ),
                run_all.Runner(
                    "later",
                    (sys.executable, "-c", f"open({str(marker)!r}, 'w').write('ran')"),
                ),
            ]

            results = run_all.run_suite(specs, output, timeout_seconds=10)

            self.assertEqual([row["status"] for row in results], ["PASS", "FAIL", "NOT_RUN"])
            self.assertEqual(results[1]["returncode"], 7)
            self.assertFalse(marker.exists())
            self.assertIn("broken output", (output / "broken.log").read_text(encoding="utf-8"))
            self.assertIn("NOT_RUN", (output / "later.log").read_text(encoding="utf-8"))
            saved = json.loads((output / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["overall_status"], "FAIL")
            self.assertEqual(saved["tests"], results)

    def test_timeout_is_a_failure_with_partial_output(self):
        run_all = load_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            orphan_marker = output / "orphan-ran.txt"
            child_code = (
                "import time; time.sleep(2); "
                f"open({os.fspath(orphan_marker)!r}, 'w').write('orphan')"
            )
            code = (
                "import subprocess, sys, time; print('before timeout', flush=True); "
                f"subprocess.Popen([sys.executable, '-c', {child_code!r}]); time.sleep(5)"
            )

            results = run_all.run_suite(
                [run_all.Runner("slow", (sys.executable, "-c", code))],
                output,
                timeout_seconds=0.1,
            )

            self.assertEqual(results[0]["status"], "FAIL")
            self.assertIsNone(results[0]["returncode"])
            self.assertIn("timed out", results[0]["reason"])
            self.assertIn("before timeout", (output / "slow.log").read_text(encoding="utf-8"))
            time.sleep(2.2)
            self.assertFalse(orphan_marker.exists(), "timeout left a child process running")

    def test_missing_optional_prerequisite_is_reported_as_skip(self):
        run_all = load_module()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            absent = output / "external-course-file"
            specs = [
                run_all.Runner(
                    "course",
                    (sys.executable, "-c", "raise SystemExit(9)"),
                    optional=True,
                    prerequisites=(absent,),
                    missing_reason="external course data is unavailable",
                )
            ]

            results = run_all.run_suite(specs, output, timeout_seconds=10)

            self.assertEqual(results[0]["status"], "SKIP")
            self.assertIsNone(results[0]["returncode"])
            self.assertIn("external course data", results[0]["reason"])
            saved = json.loads((output / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["overall_status"], "PASS_WITH_SKIPS")


if __name__ == "__main__":
    unittest.main()
