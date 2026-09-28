"""Conservative instance comparison; never mutates a baseline or authorizes a merge."""

from __future__ import annotations

from collections import defaultdict

from .storage import InputError, digest


def _instances(report: dict) -> dict:
    grouped = defaultdict(list)
    if not isinstance(report.get("findings"), list):
        raise InputError("Report lacks findings")
    for finding in report["findings"]:
        if not isinstance(finding, dict) or not all(isinstance(finding.get(key), str) and finding[key]
                                                   for key in ("fingerprint", "rule_id", "path", "message")):
            raise InputError("Invalid finding identity")
        metric = finding.get("metric")
        if metric is not None and (type(metric) is not int or metric < 0):
            raise InputError("Invalid measured metric")
        if finding.get("metric_name") is not None and not isinstance(finding["metric_name"], str):
            raise InputError("Invalid metric name")
        if finding.get("line") is not None and (type(finding["line"]) is not int or finding["line"] < 1):
            raise InputError("Invalid diagnostic line")
        grouped[finding["fingerprint"]].append(finding)
    return dict(grouped)


def compare(baseline: dict, current: dict) -> dict:
    """Count instances, not file totals. Ambiguous identities require human review."""
    for report in (baseline, current):
        if not isinstance(report, dict) or type(report.get("schema_version")) is not int or report["schema_version"] != 1:
            raise InputError("Unsupported report schema")
        if report.get("status") != "checked" or report.get("exit_code") != 0:
            raise InputError("Cannot compare incomplete reports")
        if not isinstance(report.get("binding"), dict):
            raise InputError("Report lacks binding")
        coverage = report.get("coverage", {})
        if not isinstance(coverage, dict):
            raise InputError("Report lacks coverage")
        expected = coverage.get("expected")
        if type(expected) is not int or expected < 1 or coverage.get("checked") != expected or coverage.get("failed") != 0:
            raise InputError("Report lacks complete coverage evidence")
    for key in ("detection_fingerprint", "source_root"):
        value = baseline["binding"].get(key)
        if not isinstance(value, str) or not value or value != current["binding"].get(key):
            raise InputError(f"Baseline migration required: {key} differs or is missing")
    previous, latest = _instances(baseline), _instances(current)
    result = {"schema_version": 1, "mode": "advisory-diff", "baseline_hash": digest(baseline),
              "current_hash": digest(current), "new": [], "absent": [], "unchanged": [],
              "worsened": [], "improved": [], "ambiguous": [],
              "authorization": "none; source origins are not inferred"}
    for fingerprint in sorted(previous.keys() | latest.keys()):
        old, new = previous.get(fingerprint, []), latest.get(fingerprint, [])
        item = {"fingerprint": fingerprint, "before": old, "after": new}
        # Multiple observations of exactly the same location across TUs are
        # expected; conflicting metrics/locations are not silently collapsed.
        def signatures(entries):
            return {(f["rule_id"], f["path"], f.get("line"), f.get("metric_name"), f.get("metric"))
                    for f in entries}
        if len(signatures(old)) > 1 or len(signatures(new)) > 1:
            category = "ambiguous"
        elif not old:
            category = "new"
        elif not new:
            category = "absent"
        elif old[0].get("metric_name") == new[0].get("metric_name") == "cognitive_complexity":
            before, after = old[0].get("metric"), new[0].get("metric")
            if before is None or after is None:
                category = "ambiguous"
            else:
                category = "worsened" if after > before else "improved" if after < before else "unchanged"
        elif old[0].get("metric") != new[0].get("metric"):
            category = "ambiguous"
        else:
            category = "unchanged"
        result[category].append(item)
    result["counts"] = {key: len(result[key]) for key in
                        ("new", "absent", "unchanged", "worsened", "improved", "ambiguous")}
    return result
