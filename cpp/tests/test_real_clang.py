"""Real clang-tidy contracts. Synthetic C++ is never project calibration data."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from dec.policy import read_policy
from dec.runner import scan
from dec.storage import file_digest, write_json


FIXTURES = Path(__file__).parent / "fixtures"
TOOL = os.environ.get("DEC_CLANG_TIDY", "clang-tidy")


@unittest.skipUnless(shutil.which(TOOL), "real clang-tidy not installed; not an integration pass")
class RealClang(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dec actual space 中文 ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.policy = FIXTURES / "contract-policy.yaml"

    def execute(self, names, output="report", tool=TOOL):
        entries = []
        for name in names:
            shutil.copyfile(FIXTURES / name, self.root / name)
            entries.append({"directory": str(self.root), "file": name,
                            "arguments": ["clang++", "-std=c++17", "-c", name]})
        write_json(self.root / "compile_commands.json", entries)
        write_json(self.root / "manifest.json", {"schema_version": 1, "translation_units": names, "inputs": []})
        before = {name: file_digest(self.root / name) for name in names}
        report = scan(source_root=self.root, database=self.root / "compile_commands.json",
                      manifest=self.root / "manifest.json", policy_path=self.policy,
                      output=self.root / output, tool=tool)
        after = {name: file_digest(self.root / name) for name in names}
        self.assertEqual(before, after, "Analysis must never rewrite source")
        return report

    def test_clean_source_is_checked(self):
        report = self.execute(["clean.cpp"])
        self.assertEqual(report["status"], "checked", report)
        self.assertEqual(report["exit_code"], 0)
        self.assertFalse(report["findings"])

    def test_violation_is_advisory_and_has_metric(self):
        report = self.execute(["violation.cpp"])
        self.assertEqual(report["status"], "checked", report)
        self.assertEqual(report["exit_code"], 0)
        matches = [f for f in report["findings"] if f["rule_id"] == "readability-function-cognitive-complexity"]
        self.assertEqual(len(matches), 1)
        self.assertGreater(matches[0]["metric"], 1)
        self.assertEqual(matches[0]["origin"], "unknown")

    def test_exact_threshold_is_not_exceeded(self):
        report = self.execute(["boundary.cpp"])
        self.assertEqual(report["status"], "checked", report)
        self.assertFalse(report["findings"])

    def test_valid_next_line_suppression(self):
        policy = read_policy(self.policy)
        policy["checks"]["readability-function-cognitive-complexity"]["Threshold"] = 0
        self.policy = self.root / "suppression-policy.json"
        write_json(self.policy, policy)
        report = self.execute(["suppressed.cpp"])
        self.assertEqual(report["status"], "checked", report)
        self.assertFalse(report["findings"])

    def test_parser_error_is_incomplete_not_a_style_violation(self):
        report = self.execute(["broken.cpp"])
        self.assertEqual(report["exit_code"], 2, report)
        self.assertEqual(report["status"], "not-checked")
        self.assertEqual(report["decision"], "incomplete")
        self.assertTrue(any(f["rule_id"] == "clang-diagnostic-error" for f in report["findings"]))

    def test_partial_scan_keeps_success_and_failure_separate(self):
        report = self.execute(["clean.cpp", "broken.cpp"])
        self.assertEqual(report["status"], "partial", report)
        self.assertEqual(report["coverage"]["checked"], 1)
        self.assertEqual(report["coverage"]["failed"], 1)

    def test_version_mismatch_fails_before_analysis(self):
        policy = read_policy(self.policy)
        policy["version"] = "0.0.1"
        self.policy = self.root / "wrong-policy.json"
        write_json(self.policy, policy)
        report = self.execute(["clean.cpp"])
        self.assertEqual(report["exit_code"], 2)
        self.assertEqual(report["coverage"]["attempted"], 0)

    def test_stale_input_is_not_a_clean_report(self):
        from dec.compilation import snapshot
        calls = 0

        def changed(root, tracked):
            nonlocal calls
            calls += 1
            result = snapshot(root, tracked)
            if calls == 2:
                result["clean.cpp"] = "changed-after-scan"
            return result

        with patch("dec.runner.snapshot", side_effect=changed):
            report = self.execute(["clean.cpp"])
        self.assertEqual(report["exit_code"], 2)
        self.assertTrue(any("changed while scanning" in e for e in report["errors"]))


if __name__ == "__main__":
    unittest.main()
