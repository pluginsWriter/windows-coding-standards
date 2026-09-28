"""Synthetic contracts exercise orchestration; real-tool tests are a separate suite."""

from __future__ import annotations

import copy
from pathlib import Path
import sys
import tempfile
import unittest

from dec.compilation import manifest_files, snapshot, validate_database
from dec.policy import clang_config, read_policy, verify_effective
from dec.process import require_success, run
from dec.project import inspect_project
from dec.runner import scan
from dec.storage import InputError, load, write_json


FIXTURES = Path(__file__).parent / "fixtures"


class Contracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dec space 中文 ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "example.cpp"
        self.source.write_text("int sample() { return 0; }\n")
        self.manifest = self.root / "manifest.json"
        write_json(self.manifest, {"schema_version": 1, "translation_units": ["example.cpp"], "inputs": []})
        self.database = self.root / "compile_commands.json"
        self.entries = [{"directory": str(self.root), "file": "example.cpp",
                         "arguments": ["clang++", "-std=c++17", "-c", "example.cpp"]}]
        write_json(self.database, self.entries)

    def test_database_accepts_explicit_scope_with_spaces(self):
        units, tracked = manifest_files(self.manifest, self.root)
        entries = validate_database(self.database, units)
        self.assertEqual(entries[0]["file"], str(self.source))
        self.assertEqual(set(snapshot(self.root, tracked)), {"example.cpp"})

    def test_missing_translation_unit_is_not_zero_findings(self):
        self.entries[0]["file"] = "other.cpp"
        write_json(self.database, self.entries)
        with self.assertRaisesRegex(InputError, "Missing translation units"):
            validate_database(self.database, [self.source])

    def test_multiple_configurations_require_explicit_selection(self):
        write_json(self.database, self.entries * 2)
        with self.assertRaisesRegex(InputError, "Multiple build configurations"):
            validate_database(self.database, [self.source])

    def test_empty_database_fails(self):
        write_json(self.database, [])
        with self.assertRaises(InputError):
            validate_database(self.database, [self.source])

    def test_manifest_alias_duplicates_fail(self):
        write_json(self.manifest, {"schema_version": 1,
                                   "translation_units": ["example.cpp", "./example.cpp"], "inputs": []})
        with self.assertRaisesRegex(InputError, "Duplicate"):
            manifest_files(self.manifest, self.root)

    def test_manifest_escape_fails(self):
        write_json(self.manifest, {"schema_version": 1,
                                   "translation_units": ["../outside.cpp"], "inputs": []})
        with self.assertRaises(InputError):
            manifest_files(self.manifest, self.root)

    def test_duplicate_yaml_keys_fail(self):
        path = self.root / "duplicate.yaml"
        path.write_text("mode: advisory\nmode: blocking\n")
        with self.assertRaisesRegex(InputError, "Duplicate"):
            load(path)

    def test_policy_rejects_unsafe_yaml(self):
        path = self.root / "unsafe.yaml"
        path.write_text("!!python/object/apply:os.system ['echo never']")
        with self.assertRaises(InputError):
            load(path)

    def test_policy_rejects_unknown_fields_and_enforcement(self):
        source = read_policy(FIXTURES / "contract-policy.yaml")
        for field, value in (("mode", "blocking"), ("extra", True), ("schema_version", True)):
            policy = {**source, field: value}
            path = self.root / "bad.yaml"
            write_json(path, policy)
            with self.subTest(field=field), self.assertRaises(InputError):
                read_policy(path)

    def test_policy_rejects_wrong_threshold_types(self):
        source = read_policy(FIXTURES / "contract-policy.yaml")
        for value in (None, True, -1, "10", 1.5):
            policy = copy.deepcopy(source)
            policy["checks"]["readability-function-cognitive-complexity"]["Threshold"] = value
            path = self.root / "bad.yaml"
            write_json(path, policy)
            with self.subTest(value=value), self.assertRaises(InputError):
                read_policy(path)

    def test_effective_drift_is_rejected(self):
        policy = read_policy(FIXTURES / "contract-policy.yaml")
        actual = clang_config(policy)
        verify_effective(policy, actual)
        actual["CheckOptions"]["readability-function-cognitive-complexity.Threshold"] = 999
        with self.assertRaisesRegex(InputError, "Effective option differs"):
            verify_effective(policy, actual)

    def test_compilation_command_is_data_not_a_shell_invocation(self):
        marker = self.root / "must-not-exist"
        self.entries[0] = {"directory": str(self.root), "file": "example.cpp",
                           "command": f"clang++ example.cpp; touch {marker}"}
        write_json(self.database, self.entries)
        validate_database(self.database, [self.source])
        self.assertFalse(marker.exists())

    def test_process_timeout_preserves_failure(self):
        result = run([sys.executable, "-c", "import time; time.sleep(5)"], self.root, 0.05)
        self.assertTrue(result["timed_out"])
        with self.assertRaises(InputError):
            require_success(result, "test")

    def test_missing_tool_writes_incomplete_evidence(self):
        report = scan(source_root=self.root, database=self.database, manifest=self.manifest,
                      policy_path=FIXTURES / "contract-policy.yaml", output=self.root / "report",
                      tool="dec-missing-executable-328987")
        self.assertEqual((report["status"], report["exit_code"]), ("not-checked", 2))
        self.assertEqual(load(self.root / "report/report.json")["decision"], "incomplete")

    def test_missing_database_writes_incomplete_evidence(self):
        self.database.unlink()
        report = scan(source_root=self.root, database=self.database, manifest=self.manifest,
                      policy_path=FIXTURES / "contract-policy.yaml", output=self.root / "report",
                      tool="unused")
        self.assertEqual(report["exit_code"], 2)
        self.assertEqual(report["coverage"]["expected"], 1)

    def test_existing_report_directory_is_never_overwritten(self):
        output = self.root / "report"
        output.mkdir()
        sentinel = output / "keep.txt"
        sentinel.write_text("keep")
        with self.assertRaises(InputError):
            scan(source_root=self.root, database=self.database, manifest=self.manifest,
                 policy_path=FIXTURES / "contract-policy.yaml", output=output, tool="unused")
        self.assertEqual(sentinel.read_text(), "keep")

    def test_project_inventory_does_not_invent_compile_commands(self):
        project = self.root / "sample.vcxproj"
        project.write_text('<Project><ItemGroup><ClCompile Include="example.cpp"/>'
                           '<ClCompile Include="$(Generated)/file.cpp"/></ItemGroup></Project>')
        result = inspect_project(project, self.root)
        self.assertEqual(result["status"], "inventory-only")
        self.assertEqual(result["manifest_draft"]["translation_units"], ["example.cpp"])
        self.assertEqual(result["unresolved_items"], ["$(Generated)/file.cpp"])


if __name__ == "__main__":
    unittest.main()
