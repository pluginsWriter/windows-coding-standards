"""Read-only discovery of declared MSBuild items, not an MSBuild evaluator."""

from __future__ import annotations

from pathlib import Path
import platform
import xml.etree.ElementTree as ET

from .storage import InputError, contained_file, file_digest


def inspect_project(project: Path, root: Path) -> dict:
    root, project = root.resolve(strict=True), project.resolve(strict=True)
    if not project.is_relative_to(root):
        raise InputError("Project must be within source root")
    try:
        document = ET.parse(project).getroot()
    except ET.ParseError as error:
        raise InputError(f"Invalid vcxproj: {error}") from error
    units, inputs, unresolved = [], [], []
    for element in document.iter():
        tag = element.tag.split("}")[-1]
        include = element.get("Include")
        if tag not in ("ClCompile", "ClInclude") or include is None:
            continue
        if any(character in include for character in ("$", "%", "*", "?", ";")):
            unresolved.append(include)
            continue
        path = contained_file(root, str(project.parent / include.replace("\\", "/")))
        relative = path.relative_to(root).as_posix()
        (units if tag == "ClCompile" else inputs).append(relative)
    configurations = [element.get("Include") for element in document.iter()
                      if element.tag.split("}")[-1] == "ProjectConfiguration"]
    properties = {}
    for name in ("PlatformToolset", "WindowsTargetPlatformVersion", "LanguageStandard", "ConfigurationType"):
        properties[name] = sorted({element.text for element in document.iter()
                                   if element.tag.split("}")[-1] == name and element.text})
    return {"schema_version": 1, "project": str(project), "source_root": str(root),
            "project_sha256": file_digest(project), "host": platform.system(),
            "configurations": configurations, "declared_properties": properties,
            "unresolved_items": unresolved,
            "manifest_draft": {"schema_version": 1, "translation_units": sorted(set(units)),
                               "inputs": sorted(set(inputs + [project.relative_to(root).as_posix()]))},
            "status": "inventory-only",
            "limitations": ["Imports and MSBuild conditions were not evaluated.",
                            "Review draft scope against an actual selected Windows build.",
                            "No compilation database or Windows SDK flags were inferred."]}
