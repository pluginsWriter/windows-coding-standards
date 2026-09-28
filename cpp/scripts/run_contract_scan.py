"""Produce persistent real-tool evidence for fixtures; never a project calibration."""

from pathlib import Path
import argparse
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dec.runner import scan
from dec.storage import write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tool", default="clang-tidy")
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    fixtures = Path(__file__).resolve().parents[1] / "tests" / "fixtures"
    names = ["clean.cpp", "boundary.cpp", "violation.cpp"]
    for name in names:
        shutil.copyfile(fixtures / name, root / name)
    write_json(root / "manifest.json", {"schema_version": 1, "translation_units": names, "inputs": []})
    write_json(root / "compile_commands.json", [
        {"directory": str(root), "file": name, "arguments": ["clang++", "-std=c++17", "-c", name]}
        for name in names])
    result = scan(source_root=root, database=root / "compile_commands.json", manifest=root / "manifest.json",
                  policy_path=fixtures / "contract-policy.yaml", output=root / "scan", tool=args.tool)
    print(f"Synthetic contract evidence: {root / 'scan' / 'summary.md'}")
    return result["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
