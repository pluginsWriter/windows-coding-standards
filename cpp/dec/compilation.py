"""Validate an explicit scope against compile_commands without executing commands."""

from __future__ import annotations

from pathlib import Path

from .storage import InputError, contained_file, file_digest, keys, load


def manifest_files(path: Path, root: Path) -> tuple[list[Path], list[Path]]:
    manifest = keys(load(path), {"schema_version", "translation_units", "inputs"}, "manifest")
    if type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1:
        raise InputError("Unsupported manifest schema")
    units = manifest["translation_units"]
    inputs = manifest["inputs"]
    if not isinstance(units, list) or not units or not isinstance(inputs, list):
        raise InputError("Manifest requires nonempty translation_units and an inputs list")
    paths = [contained_file(root, name) for name in units]
    tracked = [contained_file(root, name) for name in inputs]
    if len(set(paths)) != len(paths) or len(set(tracked)) != len(tracked):
        raise InputError("Duplicate manifest entries (including path aliases)")
    return paths, sorted(set(paths + tracked))


def validate_database(path: Path, units: list[Path]) -> list[dict]:
    database = load(path)
    if not isinstance(database, list) or not database:
        raise InputError("Compilation database must contain at least one entry")
    selected: dict[Path, dict] = {}
    expected = set(units)
    for entry in database:
        if not isinstance(entry, dict) or not isinstance(entry.get("directory"), str):
            raise InputError("Invalid compilation database entry")
        directory = Path(entry["directory"])
        if not directory.is_absolute() or not directory.is_dir():
            raise InputError("Compilation directory must be an existing absolute path")
        file = entry.get("file")
        if not isinstance(file, str) or not file:
            raise InputError("Compilation entry is missing file")
        source = (directory / file).resolve()
        if source not in expected:
            continue
        arguments = entry.get("arguments")
        command = entry.get("command")
        if arguments is not None:
            if not isinstance(arguments, list) or not arguments or not all(
                    isinstance(arg, str) and "\0" not in arg for arg in arguments):
                raise InputError(f"Invalid arguments for {source}")
        elif not isinstance(command, str) or not command.strip() or "\0" in command:
            raise InputError(f"Missing compile command for {source}")
        if source in selected:
            raise InputError(f"Multiple build configurations for {source}; select one database per run")
        selected[source] = {**entry, "file": str(source), "directory": str(directory.resolve())}
    missing = expected - selected.keys()
    if missing:
        raise InputError("Missing translation units: " + ", ".join(str(p) for p in sorted(missing)))
    return [selected[path] for path in units]


def snapshot(root: Path, tracked: list[Path]) -> dict[str, str]:
    """Hash declared inputs; does not claim to discover all transitive dependencies."""
    try:
        return {path.relative_to(root).as_posix(): file_digest(path) for path in tracked}
    except OSError as error:
        raise InputError(f"Source snapshot failed: {error}") from error
