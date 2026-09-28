"""Render the supported native checks from one explicit advisory policy."""

from __future__ import annotations

from pathlib import Path
import re

import yaml

from .storage import InputError, keys, load


# Option types are tool contracts, not project thresholds. Values live in YAML.
OPTIONS = {
    "readability-function-cognitive-complexity": {
        "Threshold": int, "DescribeBasicIncrements": bool, "IgnoreMacros": bool,
    },
    "readability-function-size": {
        "LineThreshold": int, "StatementThreshold": int, "BranchThreshold": int,
        "ParameterThreshold": int, "NestingThreshold": int,
        "VariableThreshold": int,
    },
}


def read_policy(path: Path) -> dict:
    policy = keys(load(path), {"schema_version", "mode", "analyzer", "version",
                              "parameter_basis", "checks"}, "policy")
    if type(policy["schema_version"]) is not int or policy["schema_version"] != 1:
        raise InputError("Unsupported policy schema_version")
    if policy["mode"] != "advisory" or policy["analyzer"] != "clang-tidy":
        raise InputError("This implementation supports advisory clang-tidy only")
    if not isinstance(policy["version"], str) or not re.fullmatch(r"\d+\.\d+\.\d+", policy["version"]):
        raise InputError("Pin a complete clang-tidy version, e.g. major.minor.patch")
    if not isinstance(policy["parameter_basis"], str) or not policy["parameter_basis"].strip():
        raise InputError("parameter_basis must explain where trial values came from")
    checks = policy["checks"]
    if not isinstance(checks, dict) or not checks:
        raise InputError("At least one check must be explicitly enabled")
    for name, options in checks.items():
        if name not in OPTIONS or not isinstance(options, dict) or not options:
            raise InputError(f"Unsupported or empty check: {name}")
        for option, value in options.items():
            expected = OPTIONS[name].get(option)
            if expected is None or type(value) is not expected:
                raise InputError(f"Unsupported option or type: {name}.{option}")
            if expected is int and value < 0:
                raise InputError(f"Negative threshold: {name}.{option}")
    return policy


def clang_config(policy: dict) -> dict:
    return {
        "Checks": "-*," + ",".join(sorted(policy["checks"])),
        "WarningsAsErrors": "", "HeaderFilterRegex": ".*",
        "SystemHeaders": False, "InheritParentConfig": False,
        "CheckOptions": {f"{name}.{option}": value
                         for name, options in policy["checks"].items()
                         for option, value in options.items()},
    }


def render(policy: dict, path: Path) -> None:
    path.write_text("# Generated; edit the source policy, not this file.\n" +
                    yaml.safe_dump(clang_config(policy), sort_keys=True), encoding="utf-8")


def _scalar(value) -> str:
    return str(value).lower() if isinstance(value, bool) else str(value)


def verify_effective(policy: dict, actual: dict) -> None:
    if not isinstance(actual, dict):
        raise InputError("clang-tidy did not return an effective configuration")
    expected = clang_config(policy)
    # LLVM prepends built-in defaults even with an explicit config. The final
    # -* resets them; compare the operative suffix, not the textual prefix.
    checks = actual.get("Checks")
    if not isinstance(checks, str) or "-*" not in checks.split(","):
        raise InputError("Effective configuration lacks the explicit check reset")
    tokens = checks.split(",")
    suffix = tokens[len(tokens) - 1 - tokens[::-1].index("-*") + 1:]
    if suffix != sorted(policy["checks"]):
        raise InputError("Effective configuration differs: Checks")
    for name in ("WarningsAsErrors", "HeaderFilterRegex", "SystemHeaders"):
        if _scalar(actual.get(name)) != _scalar(expected[name]):
            raise InputError(f"Effective configuration differs: {name}")
    options = actual.get("CheckOptions", {})
    if not isinstance(options, dict):
        raise InputError("Unsupported clang-tidy CheckOptions output")
    for name, value in expected["CheckOptions"].items():
        if _scalar(options.get(name)) != _scalar(value):
            raise InputError(f"Effective option differs: {name}")
