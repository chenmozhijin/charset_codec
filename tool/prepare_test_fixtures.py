#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: MIT

"""Prepare local codec fixtures under test/.fixtures.

This script is intentionally standalone (stdlib only).
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import re
from typing import Iterable


_TXT_MAP_RE = re.compile(
    r"^\s*(?:0x)?([0-9A-Fa-f]{2,8})\s+(?:0x)?([0-9A-Fa-f]{4,8})\b"
)
_XML_A_RE = re.compile(r"<a\b[^>]*>")
_XML_U_RE = re.compile(r'\bu="([0-9A-Fa-f]{4,8})"')
_XML_B_RE = re.compile(r'\bb="([0-9A-Fa-f]{2,8})"')


@dataclass(frozen=True)
class CodeMapSpec:
    filename: str
    encoding: str
    python_codec: str
    fmt: str


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


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


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def _hex_to_bytes(token: str) -> bytes:
    t = token.strip().lower()
    if t.startswith("0x"):
        t = t[2:]
    if len(t) % 2 != 0:
        t = "0" + t
    return bytes.fromhex(t)


def _bytes_to_hex(data: bytes) -> str:
    return data.hex()


def _is_valid_scalar(cp: int) -> bool:
    return 0 <= cp <= 0x10FFFF and not (0xD800 <= cp <= 0xDFFF)


def _parse_txt_map(path: Path) -> Iterable[tuple[bytes, str]]:
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            m = _TXT_MAP_RE.match(line)
            if not m:
                continue
            b_hex, u_hex = m.group(1), m.group(2)
            cp = int(u_hex, 16)
            if not _is_valid_scalar(cp):
                continue
            try:
                encoded = _hex_to_bytes(b_hex)
            except ValueError:
                continue
            yield encoded, chr(cp)


def _parse_xml_map(path: Path) -> Iterable[tuple[bytes, str]]:
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            if not _XML_A_RE.search(raw):
                continue
            m_u = _XML_U_RE.search(raw)
            m_b = _XML_B_RE.search(raw)
            if m_u is None or m_b is None:
                continue
            cp = int(m_u.group(1), 16)
            if not _is_valid_scalar(cp):
                continue
            try:
                encoded = _hex_to_bytes(m_b.group(1))
            except ValueError:
                continue
            yield encoded, chr(cp)


def _iter_map_entries(spec: CodeMapSpec, raw_path: Path) -> Iterable[tuple[bytes, str]]:
    if spec.fmt == "txt":
        yield from _parse_txt_map(raw_path)
        return
    if spec.fmt == "xml":
        yield from _parse_xml_map(raw_path)
        return
    raise RuntimeError(f"unsupported map format: {spec.fmt}")


def _build_map_cases(specs: list[CodeMapSpec], raw_dir: Path, out_path: Path) -> tuple[int, list[str]]:
    warnings: list[str] = []
    dedupe: set[tuple[str, str, str]] = set()
    case_count = 0
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8", newline="\n") as out:
        for spec in specs:
            raw_path = raw_dir / spec.filename
            if not raw_path.exists():
                warnings.append(f"missing code map file: {raw_path}")
                continue
            for encoded, text in _iter_map_entries(spec, raw_path):
                key = (spec.encoding, _bytes_to_hex(encoded), text)
                if key in dedupe:
                    continue
                dedupe.add(key)

                try:
                    decoded = encoded.decode(spec.python_codec, errors="strict")
                except UnicodeError:
                    continue
                if decoded != text:
                    continue

                roundtrip = False
                try:
                    encoded_rt = text.encode(spec.python_codec, errors="strict")
                    roundtrip = encoded_rt == encoded
                except UnicodeError:
                    roundtrip = False

                payload = {
                    "encoding": spec.encoding,
                    "pythonCodec": spec.python_codec,
                    "bytesHex": _bytes_to_hex(encoded),
                    "text": text,
                    "source": spec.filename,
                    "roundtrip": roundtrip,
                }
                out.write(json.dumps(payload, ensure_ascii=False))
                out.write("\n")
                case_count += 1

    return case_count, warnings


def _build_codec_vectors(out_path: Path) -> int:
    vectors = [
        {
            "id": "utf7_decode_illformed_strict",
            "operation": "decode",
            "encoding": "utf-7",
            "errors": "strict",
            "inputHex": "612b4062",
            "expectError": True,
        },
        {
            "id": "utf7_decode_illformed_ignore",
            "operation": "decode",
            "encoding": "utf-7",
            "errors": "ignore",
            "inputHex": "612b4062",
            "expectedText": "ab",
        },
        {
            "id": "utf7_decode_illformed_replace",
            "operation": "decode",
            "encoding": "utf-7",
            "errors": "replace",
            "inputHex": "612b4062",
            "expectedText": "a\ufffdb",
        },
        {
            "id": "utf7_decode_illformed_backslash",
            "operation": "decode",
            "encoding": "utf-7",
            "errors": "backslashReplace",
            "inputHex": "612b4062",
            "expectedText": r"a\x2b\x40b",
        },
        {
            "id": "utf7_decode_unterminated_strict",
            "operation": "decode",
            "encoding": "utf-7",
            "errors": "strict",
            "inputHex": "612b494b",
            "expectError": True,
        },
        {
            "id": "utf7_decode_unterminated_replace",
            "operation": "decode",
            "encoding": "utf-7",
            "errors": "replace",
            "inputHex": "612b494b",
            "expectedText": "a\ufffd",
        },
        {
            "id": "utf7_decode_nonbmp",
            "operation": "decode",
            "encoding": "utf-7",
            "errors": "strict",
            "inputHex": "2b324148636f412d",
            "expectedText": "\U000104A0",
        },
        {
            "id": "utf7_encode_nonbmp",
            "operation": "encode",
            "encoding": "utf-7",
            "errors": "strict",
            "inputText": "\U000104A0",
            "expectedHex": "2b324148636f412d",
        },
        {
            "id": "utf7_encode_plus",
            "operation": "encode",
            "encoding": "utf-7",
            "errors": "strict",
            "inputText": "+",
            "expectedHex": "2b2d",
        },
        {
            "id": "ascii_encode_backslashreplace",
            "operation": "encode",
            "encoding": "ascii",
            "errors": "backslashReplace",
            "inputText": "A中B",
            "expectedHex": "415c753465326442",
        },
        {
            "id": "cp932_decode_replace",
            "operation": "decode",
            "encoding": "cp932",
            "errors": "replace",
            "inputHex": "61626381008284",
            "expectedText": "abc\ufffd\u0000\uff44",
        },
        {
            "id": "cp932_decode_ignore",
            "operation": "decode",
            "encoding": "cp932",
            "errors": "ignore",
            "inputHex": "61626381008284",
            "expectedText": "abc\u0000\uff44",
        },
        {
            "id": "cp950_decode_a145",
            "operation": "decode",
            "encoding": "cp950",
            "errors": "strict",
            "inputHex": "a145",
            "expectedText": "\u2027",
        },
        {
            "id": "big5hkscs_decode_a145",
            "operation": "decode",
            "encoding": "big5hkscs",
            "errors": "strict",
            "inputHex": "a145",
            "expectedText": "\u2022",
        },
        {
            "id": "cp950_encode_2027",
            "operation": "encode",
            "encoding": "cp950",
            "errors": "strict",
            "inputText": "\u2027",
            "expectedHex": "a145",
        },
        {
            "id": "big5hkscs_encode_2027_strict",
            "operation": "encode",
            "encoding": "big5hkscs",
            "errors": "strict",
            "inputText": "\u2027",
            "expectError": True,
        },
        {
            "id": "big5_decode_8740_strict",
            "operation": "decode",
            "encoding": "big5",
            "errors": "strict",
            "inputHex": "8740",
            "expectError": True,
        },
        {
            "id": "big5hkscs_decode_8740",
            "operation": "decode",
            "encoding": "big5hkscs",
            "errors": "strict",
            "inputHex": "8740",
            "expectedText": "\u43f0",
        },
        {
            "id": "big5_encode_00a8_strict",
            "operation": "encode",
            "encoding": "big5",
            "errors": "strict",
            "inputText": "\u00a8",
            "expectError": True,
        },
        {
            "id": "big5hkscs_encode_00a8",
            "operation": "encode",
            "encoding": "big5hkscs",
            "errors": "strict",
            "inputText": "\u00a8",
            "expectedHex": "c6d8",
        },
        {
            "id": "gbk_decode_a140_strict",
            "operation": "decode",
            "encoding": "gbk",
            "errors": "strict",
            "inputHex": "a140",
            "expectError": True,
        },
        {
            "id": "gb18030_decode_a140",
            "operation": "decode",
            "encoding": "gb18030",
            "errors": "strict",
            "inputHex": "a140",
            "expectedText": "\ue4c6",
        },
        {
            "id": "gbk_encode_0080_strict",
            "operation": "encode",
            "encoding": "gbk",
            "errors": "strict",
            "inputText": "\u0080",
            "expectError": True,
        },
        {
            "id": "gb18030_encode_0080",
            "operation": "encode",
            "encoding": "gb18030",
            "errors": "strict",
            "inputText": "\u0080",
            "expectedHex": "81308130",
        },
        {
            "id": "shift_jis_decode_5c",
            "operation": "decode",
            "encoding": "shift_jis",
            "errors": "strict",
            "inputHex": "5c",
            "expectedText": "\\",
        },
        {
            "id": "shift_jis_2004_decode_5c",
            "operation": "decode",
            "encoding": "shift_jis_2004",
            "errors": "strict",
            "inputHex": "5c",
            "expectedText": "\u00a5",
        },
        {
            "id": "shift_jis_encode_005c",
            "operation": "encode",
            "encoding": "shift_jis",
            "errors": "strict",
            "inputText": "\\",
            "expectedHex": "5c",
        },
        {
            "id": "shift_jis_2004_encode_005c",
            "operation": "encode",
            "encoding": "shift_jis_2004",
            "errors": "strict",
            "inputText": "\\",
            "expectedHex": "815f",
        },
        {
            "id": "euc_jp_decode_a2af_strict",
            "operation": "decode",
            "encoding": "euc-jp",
            "errors": "strict",
            "inputHex": "a2af",
            "expectError": True,
        },
        {
            "id": "euc_jis_2004_decode_a2af",
            "operation": "decode",
            "encoding": "euc-jis-2004",
            "errors": "strict",
            "inputHex": "a2af",
            "expectedText": "\uff07",
        },
        {
            "id": "euc_jp_encode_00a0_strict",
            "operation": "encode",
            "encoding": "euc-jp",
            "errors": "strict",
            "inputText": "\u00a0",
            "expectError": True,
        },
        {
            "id": "euc_jis_2004_encode_00a0",
            "operation": "encode",
            "encoding": "euc-jis-2004",
            "errors": "strict",
            "inputText": "\u00a0",
            "expectedHex": "a9a2",
        },
        {
            "id": "cp037_decode_9f",
            "operation": "decode",
            "encoding": "cp037",
            "errors": "strict",
            "inputHex": "9f",
            "expectedText": "\u00a4",
        },
        {
            "id": "cp037_encode_00a4",
            "operation": "encode",
            "encoding": "cp037",
            "errors": "strict",
            "inputText": "\u00a4",
            "expectedHex": "9f",
        },
        {
            "id": "iso_8859_11_decode_a0",
            "operation": "decode",
            "encoding": "iso-8859-11",
            "errors": "strict",
            "inputHex": "a0",
            "expectedText": "\u00a0",
        },
        {
            "id": "iso_8859_11_encode_a0",
            "operation": "encode",
            "encoding": "iso-8859-11",
            "errors": "strict",
            "inputText": "\u00a0",
            "expectedHex": "a0",
        },
        {
            "id": "gb2312_decode_8140_strict",
            "operation": "decode",
            "encoding": "gb2312",
            "errors": "strict",
            "inputHex": "8140",
            "expectError": True,
        },
        {
            "id": "gb2312_encode_4e02_strict",
            "operation": "encode",
            "encoding": "gb2312",
            "errors": "strict",
            "inputText": "\u4e02",
            "expectError": True,
        },
        {
            "id": "euc_jisx0213_decode_a2af",
            "operation": "decode",
            "encoding": "euc-jisx0213",
            "errors": "strict",
            "inputHex": "a2af",
            "expectedText": "\uff07",
        },
        {
            "id": "euc_jisx0213_encode_ff07",
            "operation": "encode",
            "encoding": "euc-jisx0213",
            "errors": "strict",
            "inputText": "\uff07",
            "expectedHex": "a2af",
        },
        {
            "id": "shift_jisx0213_decode_5c",
            "operation": "decode",
            "encoding": "shift-jisx0213",
            "errors": "strict",
            "inputHex": "5c",
            "expectedText": "\u00a5",
        },
        {
            "id": "shift_jisx0213_encode_005c",
            "operation": "encode",
            "encoding": "shift-jisx0213",
            "errors": "strict",
            "inputText": "\\",
            "expectedHex": "815f",
        },
        {
            "id": "iso_2022_jp_decode_3042",
            "operation": "decode",
            "encoding": "iso-2022-jp",
            "errors": "strict",
            "inputHex": "1b244224221b2842",
            "expectedText": "\u3042",
        },
        {
            "id": "iso2022_jp_1_decode_02d8",
            "operation": "decode",
            "encoding": "iso2022-jp-1",
            "errors": "strict",
            "inputHex": "1b242844222f1b2842",
            "expectedText": "\u02d8",
        },
        {
            "id": "iso2022_jp_3_decode_20089",
            "operation": "decode",
            "encoding": "iso2022-jp-3",
            "errors": "strict",
            "inputHex": "1b24285021211b2842",
            "expectedText": "\U00020089",
        },
        {
            "id": "iso_2022_jp_encode_3042",
            "operation": "encode",
            "encoding": "iso-2022-jp",
            "errors": "strict",
            "inputText": "\u3042",
            "expectedHex": "1b244224221b2842",
        },
        {
            "id": "iso2022_jp_1_encode_02d8",
            "operation": "encode",
            "encoding": "iso2022-jp-1",
            "errors": "strict",
            "inputText": "\u02d8",
            "expectedHex": "1b242844222f1b2842",
        },
        {
            "id": "iso2022_jp_3_encode_20089",
            "operation": "encode",
            "encoding": "iso2022-jp-3",
            "errors": "strict",
            "inputText": "\U00020089",
            "expectedHex": "1b24285021211b2842",
        },
        {
            "id": "gb18030_decode_valid_four_bytes",
            "operation": "decode",
            "encoding": "gb18030",
            "errors": "strict",
            "inputHex": "61626381308130646566",
            "expectedText": "abc\u0080def",
        },
        {
            "id": "gb18030_decode_invalid_strict",
            "operation": "decode",
            "encoding": "gb18030",
            "errors": "strict",
            "inputHex": "ff308130",
            "expectError": True,
        },
    ]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="\n") as f:
        for entry in vectors:
            f.write(json.dumps(entry, ensure_ascii=True))
            f.write("\n")
    return len(vectors)


def _build_manifest(
    fixtures_root: Path,
    lock_path: Path,
    lock_payload: dict,
    map_case_count: int,
    vector_count: int,
    warnings: list[str],
) -> dict:
    lock_sha = _sha256_file(lock_path)
    files = []
    for p in sorted([x for x in fixtures_root.rglob("*") if x.is_file()], key=lambda x: x.as_posix()):
        rel = p.relative_to(fixtures_root).as_posix()
        if rel in {"manifest.json", ".ready"}:
            continue
        files.append(
            {
                "path": rel,
                "size": p.stat().st_size,
                "sha256": _sha256_file(p),
            }
        )

    return {
        "schemaVersion": lock_payload["manifestSchemaVersion"],
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "lockSha256": lock_sha,
        "lockSchemaVersion": lock_payload["schemaVersion"],
        "stats": {
            "mapCaseCount": map_case_count,
            "vectorCount": vector_count,
            "fileCount": len(files),
        },
        "paths": {
            "mapCases": "codecmaps/parsed/map_cases.jsonl",
            "codecVectors": "cpython_vectors/codec_vectors.jsonl",
        },
        "warnings": warnings,
        "files": files,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare test fixtures.")
    parser.add_argument("--lock", default="tool/fixtures.lock.json")
    parser.add_argument("--fixtures-root", default=str(Path(__file__).resolve().parents[1] / "test" / ".fixtures"))
    parser.add_argument("--code-maps-root", required=True)
    args = parser.parse_args()

    lock_path = Path(args.lock).resolve()
    fixtures_root = Path(args.fixtures_root).resolve()
    code_maps_root = Path(args.code_maps_root).resolve()

    lock_payload = _read_json(lock_path)
    code_specs = [
        CodeMapSpec(
            filename=str(item["filename"]),
            encoding=str(item["encoding"]),
            python_codec=str(item["pythonCodec"]),
            fmt=str(item["format"]),
        )
        for item in lock_payload["codeMaps"]
    ]

    (fixtures_root / "codecmaps" / "parsed").mkdir(parents=True, exist_ok=True)
    (fixtures_root / "cpython_vectors").mkdir(parents=True, exist_ok=True)
    map_cases_path = fixtures_root / "codecmaps" / "parsed" / "map_cases.jsonl"
    vectors_path = fixtures_root / "cpython_vectors" / "codec_vectors.jsonl"

    map_case_count, map_warnings = _build_map_cases(
        code_specs, code_maps_root, map_cases_path
    )
    vector_count = _build_codec_vectors(vectors_path)

    warnings = [*map_warnings]
    manifest = _build_manifest(
        fixtures_root=fixtures_root,
        lock_path=lock_path,
        lock_payload=lock_payload,
        map_case_count=map_case_count,
        vector_count=vector_count,
        warnings=warnings,
    )
    _write_json(fixtures_root / "manifest.json", manifest)
    (fixtures_root / ".ready").write_text(
        "ready\n", encoding="utf-8", newline="\n"
    )

    print(
        json.dumps(
            {
                "fixturesRoot": str(fixtures_root),
                "mapCaseCount": map_case_count,
                "vectorCount": vector_count,
                "warnings": len(warnings),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
