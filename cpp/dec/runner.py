"""M0 advisory scan with explicit coverage, immutable inputs and raw evidence."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import platform
import re
import uuid

from .compilation import manifest_files, snapshot, validate_database
from .diagnostics import read_diagnostics
from .policy import read_policy, render, verify_effective
from .process import identify, require_success, run
from .storage import InputError, digest, file_digest, load, positive_number, write_json


def _invoke(argv, cwd, timeout, output: Path, label: str) -> dict:
    result = run(argv, cwd, timeout)
    write_json(output / f"{label}.process.json", result)
    (output / f"{label}.stdout.txt").write_text(result["stdout"], encoding="utf-8")
    (output / f"{label}.stderr.txt").write_text(result["stderr"], encoding="utf-8")
    return result


def _check_enabled(tool: str, config: Path, policy: dict, output: Path, timeout: float) -> None:
    result = _invoke([tool, f"--config-file={config}", "--list-checks"],
                     output, timeout, output, "enabled-checks")
    require_success(result, "enabled checks")
    actual = {line.strip() for line in result["stdout"].splitlines()
              if line.startswith("    ") and line.strip()}
    if actual != set(policy["checks"]):
        raise InputError(f"Enabled checks differ: {sorted(actual)}")


def scan(*, source_root: Path, database: Path, manifest: Path, policy_path: Path,
         output: Path, tool: str, timeout: float = 120) -> dict:
    """Create a fresh report directory. All source and compilation inputs are read-only."""
    output = output.resolve()
    try:
        output.mkdir(parents=True, exist_ok=False)
    except OSError as error:
        raise InputError(f"Use a new report directory: {output}: {error}") from error
    report = {"schema_version": 1, "run_id": str(uuid.uuid4()), "mode": "advisory",
              "created_at": datetime.now(timezone.utc).isoformat(), "host": platform.system(),
              "status": "not-checked", "decision": "incomplete", "exit_code": 2,
              "scope": "explicit manifest; system headers excluded",
              "upload_status": "not-attempted", "binding": {},
              "coverage": {"expected": 0, "attempted": 0, "checked": 0, "failed": 0},
              "units": [], "findings": [], "errors": []}
    write_json(output / "report.json", report)
    try:
        positive_number(timeout, "timeout")
        root = source_root.resolve(strict=True)
        if not root.is_dir():
            raise InputError("source_root is not a directory")
        report["binding"]["source_root"] = str(root)
        manifest, policy_path = (p.resolve(strict=True) for p in (manifest, policy_path))
        policy = read_policy(policy_path)
        units, tracked = manifest_files(manifest, root)
        report["coverage"]["expected"] = len(units)
        database = database.resolve(strict=True)
        commands = validate_database(database, units)
        before = snapshot(root, tracked)
        evidence_inputs = {str(p): file_digest(p) for p in (database, manifest, policy_path)}
        report["binding"] = {
            "source_root": str(root), "source_snapshot": digest(before),
            "revision": "snapshot:" + digest(before), "tracked_inputs": before,
            "input_hashes": evidence_inputs, "policy_hash": digest(policy),
            "manifest_hash": file_digest(manifest), "database_hash": digest(commands),
        }
        analyzer = identify(tool, output, timeout)
        report["analyzer"] = analyzer
        if analyzer["version"] != policy["version"]:
            raise InputError(f"Tool version mismatch: expected {policy['version']}, got {analyzer['version']}")
        report["binding"]["detection_fingerprint"] = digest(
            [analyzer["sha256"], analyzer["version"], policy, commands])
        write_json(output / "policy.json", policy)
        write_json(output / "compile_commands.json", commands)
        config = output / "generated.clang-tidy.yaml"
        render(policy, config)
        _check_enabled(analyzer["path"], config, policy, output, timeout)
        for index, (source, command) in enumerate(zip(units, commands)):
            unit_output = output / f"tu-{index:04d}"
            unit_output.mkdir()
            unit = {"path": source.relative_to(root).as_posix(), "status": "not-checked", "errors": []}
            report["units"].append(unit)
            report["coverage"]["attempted"] += 1
            argv = [analyzer["path"], str(source), "-p", str(output), f"--config-file={config}"]
            cwd = Path(command["directory"])
            try:
                effective = _invoke(argv + ["--dump-config"], cwd, timeout, unit_output, "effective")
                require_success(effective, "effective configuration")
                effective_path = unit_output / "effective.stdout.txt"
                verify_effective(policy, load(effective_path))
                diagnostics = unit_output / "diagnostics.yaml"
                result = _invoke(argv + [f"--export-fixes={diagnostics}"],
                                 cwd, timeout, unit_output, "scan")
                if diagnostics.exists():
                    findings = read_diagnostics(diagnostics, root, cwd)
                    for finding in findings:
                        finding["translation_unit"] = unit["path"]
                    report["findings"].extend(findings)
                else:
                    # LLVM may omit export-fixes on a clean TU. Only accept that
                    # when the process succeeded and emitted no diagnostic text.
                    findings = []
                    suppressed = re.fullmatch(r"Suppressed (\d+) warnings \((\d+) NOLINT\)\.",
                                              result["stderr"].strip())
                    if suppressed and suppressed.group(1) == suppressed.group(2):
                        unit["nolint_suppressed"] = int(suppressed.group(1))
                    elif result["stdout"].strip() or result["stderr"].strip():
                        raise InputError("Tool output present without structured diagnostics")
                    if result["stdout"].strip():
                        raise InputError("Unexpected output without structured diagnostics")
                require_success(result, "analysis")
                if any(f["level"] in ("Error", "Fatal") or f["rule_id"] == "clang-diagnostic-error"
                       for f in findings):
                    raise InputError("Compiler/analysis error reported")
                unit["status"] = "checked"
                report["coverage"]["checked"] += 1
            except (InputError, OSError, ValueError) as error:
                unit["errors"].append(str(error))
                report["coverage"]["failed"] += 1
            write_json(output / "report.json", report)
        if snapshot(root, tracked) != before:
            raise InputError("Declared source inputs changed while scanning; results are stale")
        if any(file_digest(Path(path)) != checksum for path, checksum in evidence_inputs.items()):
            raise InputError("Policy, manifest or compilation database changed while scanning")
        if file_digest(Path(analyzer["path"])) != analyzer["sha256"]:
            raise InputError("Analyzer executable changed while scanning")
        if report["coverage"]["failed"]:
            raise InputError("One or more translation units were not checked successfully")
        report.update(status="checked", decision="advisory", exit_code=0)
    except (InputError, OSError, ValueError) as error:
        report["errors"].append(str(error))
        report["status"] = "partial" if report["coverage"]["checked"] else "not-checked"
    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    write_json(output / "report.json", report)
    write_summary(output, report)
    return report


def write_summary(output: Path, report: dict) -> None:
    coverage = report["coverage"]
    lines = ["# DEC M0 advisory scan", "", f"Status: **{report['status']}**",
             f"Decision: **{report['decision']}** (exit {report['exit_code']})",
             f"Run: `{report['run_id']}`", f"Host: {report['host']}",
             f"Coverage: {coverage['checked']}/{coverage['expected']} declared translation units",
             f"Raw diagnostic occurrences: {len(report['findings'])}",
             "Upload: not attempted by this local runner", "",
             "This report does not prove Windows compatibility, DEC calibration, source origin,",
             "merge authorization, or coverage of undeclared inputs/build configurations.", "",
             "## Diagnostics", ""]
    for item in report["findings"]:
        lines.append(f"- `{item['rule_id']}` at `{item['path']}:{item['line']}`: " +
                     item["message"].replace("\n", " "))
    errors = report["errors"] + [error for unit in report["units"] for error in unit["errors"]]
    if errors:
        lines += ["", "## Incomplete checks", ""] + [f"- {error}" for error in errors]
    (output / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
