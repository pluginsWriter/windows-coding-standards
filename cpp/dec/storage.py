"""Strict input loading and deterministic evidence serialization."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import yaml


class InputError(ValueError):
    """An input cannot support a trustworthy analysis result."""


class UniqueLoader(yaml.SafeLoader):
    """Reject duplicate keys instead of silently keeping the last policy value."""


def _mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str):
            raise InputError("All YAML/JSON mapping keys must be strings")
        if key in result:
            raise InputError(f"Duplicate key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _mapping)


def load(path: Path):
    try:
        return yaml.load(path.read_text(encoding="utf-8-sig"), Loader=UniqueLoader)
    except (OSError, UnicodeError, yaml.YAMLError) as error:
        raise InputError(f"Cannot read {path}: {error}") from error


def canonical(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(value) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    indent=2, allow_nan=False).encode("utf-8") + b"\n")
    temporary.replace(path)


def keys(value, expected: set[str], label: str) -> dict:
    if not isinstance(value, dict) or set(value) != expected:
        actual = set(value) if isinstance(value, dict) else type(value).__name__
        raise InputError(f"{label}: expected keys {sorted(expected)}, got {actual}")
    return value


def positive_number(value, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InputError(f"{label} must be a positive finite number")
    if not math.isfinite(value) or value <= 0:
        raise InputError(f"{label} must be a positive finite number")
    return value


def contained_file(root: Path, name: str) -> Path:
    if not isinstance(name, str) or not name:
        raise InputError("Expected a nonempty file path")
    path = (root / name).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        raise InputError(f"File must exist within source root: {name}")
    return path
