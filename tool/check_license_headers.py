#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: MIT

"""校验源码、配置与生成文件的 SPDX 文件头边界。"""

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_COPYRIGHT = "SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>"
PROJECT_LICENSE = "SPDX-License-Identifier: MIT"
GENERATED_HEADER = [
    "// 此文件由 tool/export_codec_data.py 自动生成，请勿手动修改。",
    "// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>",
    "// SPDX-FileCopyrightText: 2001 Python Software Foundation",
    "// SPDX-License-Identifier: MIT AND PSF-2.0",
]
USER_DOCUMENTS = {
    "CHANGELOG.md",
    "README.md",
    "README_zh.md",
    "THIRD_PARTY_NOTICES.md",
}


def _tracked_files() -> list[str]:
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    )
    return [path.decode("utf-8") for path in output.split(b"\0") if path]


def _is_generated_source(path: str) -> bool:
    return (
        path.startswith("lib/src/generated/") and path.endswith(".dart")
    ) or (path.startswith("native/generated/") and path.endswith(".rs"))


def _is_project_source_or_config(path: str) -> bool:
    suffix = Path(path).suffix.lower()
    if suffix == ".dart":
        return not path.startswith("lib/src/generated/")
    if suffix == ".rs":
        return not path.startswith("native/generated/")
    return suffix in {".py", ".ps1", ".yml", ".yaml", ".toml"} or path in {
        ".gitignore",
        ".pubignore",
    }


def _check_project_header(path: str, lines: list[str]) -> str | None:
    start = 1 if lines and lines[0].startswith("#!") else 0
    comment = "//" if Path(path).suffix.lower() in {".dart", ".rs"} else "#"
    expected = [
        f"{comment} {PROJECT_COPYRIGHT}",
        f"{comment} {PROJECT_LICENSE}",
    ]
    if lines[start : start + 2] != expected:
        return f"{path}: 缺少或错误的 MIT SPDX 文件头"
    return None


def main() -> int:
    errors: list[str] = []
    project_count = 0
    generated_count = 0
    for path in _tracked_files():
        absolute = ROOT / path
        if _is_generated_source(path):
            generated_count += 1
            lines = absolute.read_text(encoding="utf-8").splitlines()
            if lines[: len(GENERATED_HEADER)] != GENERATED_HEADER:
                errors.append(f"{path}: 缺少或错误的生成源码 SPDX 文件头")
            continue
        if _is_project_source_or_config(path):
            project_count += 1
            lines = absolute.read_text(encoding="utf-8").splitlines()
            error = _check_project_header(path, lines)
            if error is not None:
                errors.append(error)
            continue
        if path.endswith(".json") or path in USER_DOCUMENTS:
            text = absolute.read_text(encoding="utf-8")
            if "SPDX-FileCopyrightText:" in text:
                errors.append(f"{path}: JSON 或用户文档不得嵌入 SPDX 文件头")

    if errors:
        print("\n".join(errors))
        return 1
    print(
        "License header check passed: "
        f"project={project_count}, generated={generated_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
