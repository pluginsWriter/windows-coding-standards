"""Command-line entry point. Exit 0: advisory operation completed; 2: incomplete."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from .compilation import manifest_files, validate_database
from .comparison import compare
from .policy import read_policy, render
from .process import identify
from .project import inspect_project
from .runner import scan
from .storage import InputError, canonical, load, write_json


def parser() -> argparse.ArgumentParser:
    cli = argparse.ArgumentParser(description="Read-only DEC C++ advisory tooling (no automatic source edits)")
    commands = cli.add_subparsers(dest="command", required=True)
    doctor = commands.add_parser("doctor", help="Identify a real clang-tidy executable")
    doctor.add_argument("--tool", default="clang-tidy")
    doctor.add_argument("--timeout", type=float, default=30)
    config = commands.add_parser("render", help="Validate policy and create a new generated config")
    config.add_argument("--policy", type=Path, required=True)
    config.add_argument("--output", type=Path, required=True)
    inspect = commands.add_parser("inspect-vcxproj", help="Inventory declared files; does not evaluate MSBuild")
    inspect.add_argument("--project", type=Path, required=True)
    inspect.add_argument("--source-root", type=Path, required=True)
    inspect.add_argument("--output", type=Path, required=True)
    diff = commands.add_parser("compare", help="Compare compatible reports without modifying a baseline")
    diff.add_argument("--baseline", type=Path, required=True)
    diff.add_argument("--current", type=Path, required=True)
    diff.add_argument("--output", type=Path, required=True)
    for command in ("validate-db", "scan"):
        sub = commands.add_parser(command)
        sub.add_argument("--source-root", type=Path, required=True)
        sub.add_argument("--database", type=Path, required=True)
        sub.add_argument("--manifest", type=Path, required=True)
        if command == "scan":
            sub.add_argument("--policy", type=Path, required=True)
            sub.add_argument("--output", type=Path, required=True, help="A new, nonexistent report directory")
            sub.add_argument("--tool", default="clang-tidy")
            sub.add_argument("--timeout", type=float, default=120)
    return cli


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "doctor":
            result = identify(args.tool, Path.cwd(), args.timeout)
        elif args.command == "render":
            policy = read_policy(args.policy)
            if args.output.exists():
                raise InputError("Refusing to overwrite an existing configuration")
            args.output.parent.mkdir(parents=True, exist_ok=True)
            render(policy, args.output)
            result = {"status": "rendered", "output": str(args.output.resolve())}
        elif args.command == "inspect-vcxproj":
            if args.output.exists():
                raise InputError("Refusing to overwrite an existing inventory")
            result = inspect_project(args.project, args.source_root)
            write_json(args.output, result)
        elif args.command == "compare":
            if args.output.exists():
                raise InputError("Refusing to overwrite an existing comparison")
            result = compare(load(args.baseline), load(args.current))
            write_json(args.output, result)
        elif args.command == "validate-db":
            root = args.source_root.resolve(strict=True)
            units, _ = manifest_files(args.manifest, root)
            entries = validate_database(args.database, units)
            result = {"status": "database-scope-matched", "translation_units": len(entries),
                      "semantic_analysis_performed": False}
        else:
            report = scan(source_root=args.source_root, database=args.database,
                          manifest=args.manifest, policy_path=args.policy,
                          output=args.output, tool=args.tool, timeout=args.timeout)
            result = {key: report[key] for key in ("run_id", "status", "decision", "coverage", "errors")}
            result["report"] = str(args.output.resolve() / "report.json")
            print(canonical(result).decode())
            return report["exit_code"]
        print(canonical(result).decode())
        return 0
    except (InputError, OSError, ValueError) as error:
        print(f"incomplete: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
