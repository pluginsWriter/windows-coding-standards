"""Invoke explicit argv with deadlines; never execute compilation database commands."""

from __future__ import annotations

from pathlib import Path
import importlib.util
import re
import shutil
import subprocess
import sys

from .storage import InputError, file_digest, positive_number


def run(argv: list[str], cwd: Path, timeout: float) -> dict:
    positive_number(timeout, "timeout")
    try:
        result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=timeout,
                                shell=False)
        return {"argv": argv, "cwd": str(cwd), "exit_code": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr, "timed_out": False}
    except subprocess.TimeoutExpired as error:
        def text(value):
            return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value or ""
        return {"argv": argv, "cwd": str(cwd), "exit_code": None,
                "stdout": text(error.stdout), "stderr": text(error.stderr), "timed_out": True}
    except OSError as error:
        raise InputError(f"Could not launch {argv[0]}: {error}") from error


def require_success(result: dict, label: str) -> None:
    if result["timed_out"] or result["exit_code"] != 0:
        raise InputError(f"{label} failed (exit={result['exit_code']}, timeout={result['timed_out']})")


def identify(tool: str, cwd: Path, timeout: float) -> dict:
    found = shutil.which(tool)
    if found is None:
        raise InputError(f"clang-tidy executable not found: {tool}")
    executable = Path(found).resolve()
    # The pinned PyPI package installs a Python/.exe launcher. Invoke and hash
    # its actual LLVM binary so deadlines kill LLVM, not just its launcher.
    launchers = {Path(sys.prefix) / folder / name for folder in ("bin", "Scripts")
                 for name in ("clang-tidy", "clang-tidy.exe")}
    if executable in {path.resolve() for path in launchers}:
        spec = importlib.util.find_spec("clang_tidy")
        if spec is not None and spec.origin:
            binaries = [Path(spec.origin).parent / "data" / "bin" / name
                        for name in ("clang-tidy", "clang-tidy.exe")]
            executable = next((path.resolve() for path in binaries if path.is_file()), executable)
    result = run([str(executable), "--version"], cwd, timeout)
    require_success(result, "tool version")
    match = re.search(r"(?:LLVM|clang)[^\n]*version\s+(\d+\.\d+\.\d+)",
                      result["stdout"], re.IGNORECASE)
    if not match:
        raise InputError("Could not identify a complete LLVM version")
    return {"path": str(executable), "version": match.group(1),
            "sha256": file_digest(executable), "version_output": result}
