"""Instance behavior is independent of the number of warnings in a file."""

import copy
import unittest

from dec.comparison import compare
from dec.storage import InputError


def finding(identity, metric=3):
    return {"fingerprint": identity, "rule_id": "native-rule", "path": "sample.cpp",
            "line": 1, "message": "test", "metric_name": "cognitive_complexity", "metric": metric}


def report(findings):
    return {"schema_version": 1, "status": "checked", "exit_code": 0,
            "binding": {"detection_fingerprint": "same-configuration", "source_root": "same-project"},
            "coverage": {"expected": 1, "checked": 1, "failed": 0}, "findings": findings}


class Comparison(unittest.TestCase):
    def test_replacing_old_with_new_is_not_cancelled_by_equal_count(self):
        baseline = report([finding("old")])
        original = copy.deepcopy(baseline)
        result = compare(baseline, report([finding("new")]))
        self.assertEqual((result["counts"]["new"], result["counts"]["absent"]), (1, 1))
        self.assertEqual(baseline, original)

    def test_same_identity_worsening_is_visible(self):
        result = compare(report([finding("same", 3)]), report([finding("same", 6)]))
        self.assertEqual(result["counts"]["worsened"], 1)

    def test_improvement_does_not_rewrite_baseline(self):
        old = report([finding("same", 6)])
        result = compare(old, report([finding("same", 3)]))
        self.assertEqual(result["counts"]["improved"], 1)
        self.assertEqual(old["findings"][0]["metric"], 6)

    def test_line_shift_with_stable_fingerprint_stays_same(self):
        current = finding("same")
        current["line"] = 100
        self.assertEqual(compare(report([finding("same")]), report([current]))["counts"]["unchanged"], 1)

    def test_cross_tu_duplicates_collapse_but_conflicts_do_not(self):
        old = report([finding("same"), finding("same")])
        new = report([finding("same")])
        self.assertEqual(compare(old, new)["counts"]["unchanged"], 1)
        old["findings"][1]["metric"] = 99
        self.assertEqual(compare(old, new)["counts"]["ambiguous"], 1)

    def test_missing_or_changed_configuration_requires_migration(self):
        for fingerprint in (None, "different"):
            current = report([])
            current["binding"]["detection_fingerprint"] = fingerprint
            with self.subTest(fingerprint=fingerprint), self.assertRaises(InputError):
                compare(report([]), current)

    def test_partial_report_cannot_form_a_baseline(self):
        current = report([])
        current["status"] = "partial"
        with self.assertRaises(InputError):
            compare(current, report([]))

    def test_claimed_success_with_missing_coverage_is_rejected(self):
        current = report([])
        current["coverage"]["checked"] = 0
        with self.assertRaises(InputError):
            compare(report([]), current)

    def test_malformed_identity_fails_with_input_error(self):
        for field, value in (("metric_name", []), ("line", {}), ("metric", True)):
            current = report([finding("same")])
            current["findings"][0][field] = value
            with self.subTest(field=field), self.assertRaises(InputError):
                compare(report([]), current)
