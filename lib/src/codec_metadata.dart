// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:collection';

import 'codec/resolver.dart';
import 'generated/codec_alias_data.g.dart';
import 'generated/codec_meta_data.g.dart';

final class CodecInfo {
  const CodecInfo({
    required this.canonicalName,
    required this.pythonCodecName,
    required this.isUtf,
    required this.isSingleByte,
    required this.isMultibyte,
  });

  final String canonicalName;
  final String pythonCodecName;
  final bool isUtf;
  final bool isSingleByte;
  final bool isMultibyte;
}

CodecInfo? lookupCodecInfo(String encoding) {
  final int? codecId = resolveCodecId(encoding);
  if (codecId == null) {
    return null;
  }
  return CodecInfo(
    canonicalName: generatedCanonicalNames[codecId],
    pythonCodecName: generatedPythonCodecNames[codecId],
    isUtf: isUtfCodecId(codecId),
    isSingleByte: isSingleByteCodecId(codecId),
    isMultibyte: isMultibyteCodecId(codecId),
  );
}

final Set<String> _supportedPythonCodecNames = UnmodifiableSetView<String>(
  generatedPythonCodecNames.map((String value) => value.toLowerCase()).toSet(),
);

Iterable<String> get supportedPythonCodecNames => _supportedPythonCodecNames;
