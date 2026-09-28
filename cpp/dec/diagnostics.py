"""Read native export-fixes diagnostics; replacement edits are never applied."""

from __future__ import annotations

from pathlib import Path
import re

from .storage import InputError, digest, load


def read_diagnostics(path: Path, root: Path, cwd: Path) -> list[dict]:
    document = load(path)
    if not isinstance(document, dict) or not isinstance(document.get("Diagnostics"), list):
        raise InputError(f"Missing structured diagnostics: {path}")
    findings = []
    for diagnostic in document["Diagnostics"]:
        if not isinstance(diagnostic, dict):
            raise InputError("Invalid diagnostic entry")
        name = diagnostic.get("DiagnosticName")
        message = diagnostic.get("DiagnosticMessage", {})
        if not isinstance(name, str) or not isinstance(message, dict):
            raise InputError("Diagnostic lacks rule or message")
        text = message.get("Message")
        filename = message.get("FilePath", "")
        offset = message.get("FileOffset", 0)
        if not isinstance(text, str) or not isinstance(filename, str) or type(offset) is not int or offset < 0:
            raise InputError("Invalid diagnostic message or offset")
        source = (cwd / filename).resolve() if filename else None
        line, column, context, location = None, None, "", filename
        if source is not None and source.is_file():
            data = source.read_bytes()
            if offset > len(data):
                raise InputError(f"Diagnostic offset is outside {source}")
            line = data[:offset].count(b"\n") + 1
            column = offset - data.rfind(b"\n", 0, offset)
            lines = data.decode("utf-8", errors="replace").splitlines()
            context = "\n".join(lines[max(0, line - 2):line + 1])
            location = source.relative_to(root).as_posix() if source.is_relative_to(root) else str(source)
        # Changing an actual measurement should not by itself change identity.
        normalized_message = re.sub(r"\d+", "#", text)
        fingerprint = digest([name, location, context, normalized_message])
        metric = re.search(r"has cognitive complexity of (\d+)", text)
        findings.append({
            "rule_id": name, "message": text, "level": diagnostic.get("Level", "Warning"),
            "path": location, "line": line, "column": column, "offset": offset,
            "fingerprint": fingerprint,
            "metric": int(metric.group(1)) if metric else None,
            "metric_name": "cognitive_complexity" if metric else None,
            "origin": "unknown", "source_modified": False,
        })
    return findings
