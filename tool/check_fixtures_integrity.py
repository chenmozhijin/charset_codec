#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: MIT

"""Validate test/.fixtures manifest integrity."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate fixture manifest.")
    parser.add_argument("--fixtures-root", default=str(Path(__file__).resolve().parents[1] / "test" / ".fixtures"))
    parser.add_argument("--lock", default="tool/fixtures.lock.json")
    args = parser.parse_args()

    fixtures_root = Path(args.fixtures_root).resolve()
    manifest_path = fixtures_root / "manifest.json"
    ready_path = fixtures_root / ".ready"
    lock_path = Path(args.lock).resolve()

    if not manifest_path.exists():
        print(f"missing manifest: {manifest_path}", file=sys.stderr)
        return 1
    if not ready_path.exists():
        print(f"missing ready marker: {ready_path}", file=sys.stderr)
        return 1

    manifest = _read_json(manifest_path)
    lock_payload = _read_json(lock_path)

    expected_schema = lock_payload.get("manifestSchemaVersion")
    actual_schema = manifest.get("schemaVersion")
    if expected_schema != actual_schema:
        print(
            f"manifest schema mismatch: expected={expected_schema}, actual={actual_schema}",
            file=sys.stderr,
        )
        return 1

    failures: list[str] = []
    for entry in manifest.get("files", []):
        rel = entry["path"]
        abs_path = fixtures_root / rel
        if not abs_path.exists():
            failures.append(f"missing file: {rel}")
            continue
        actual_sha = _sha256_file(abs_path)
        if actual_sha != entry["sha256"]:
            failures.append(
                f"sha mismatch: {rel}, expected={entry['sha256']}, actual={actual_sha}"
            )
        actual_size = abs_path.stat().st_size
        if actual_size != entry["size"]:
            failures.append(
                f"size mismatch: {rel}, expected={entry['size']}, actual={actual_size}"
            )

    paths = manifest.get("paths", {})
    for key in ("mapCases", "codecVectors"):
        rel = paths.get(key)
        if not rel:
            failures.append(f"manifest.paths missing key: {key}")
            continue
        if not (fixtures_root / rel).exists():
            failures.append(f"manifest.paths target missing: {key} -> {rel}")

    if failures:
        print("fixture integrity check failed:", file=sys.stderr)
        for line in failures:
            print(f" - {line}", file=sys.stderr)
        return 1

    print(
        json.dumps(
            {
                "fixturesRoot": str(fixtures_root),
                "filesChecked": len(manifest.get("files", [])),
                "warnings": len(manifest.get("warnings", [])),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
