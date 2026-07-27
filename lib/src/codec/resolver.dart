// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import '../generated/codec_alias_data.g.dart';
import '../generated/codec_meta_data.g.dart';

const int codecFlagUtf = 0x1;
const int codecFlagSingleByte = 0x2;
const int codecFlagMultibyte = 0x4;

final class ResolvedCodec {
  const ResolvedCodec(this.codecId);

  final int codecId;

  String get canonicalName => generatedCanonicalNames[codecId];
  String get pythonCodec => generatedPythonCodecNames[codecId];
  bool get isUtf => isUtfCodecId(codecId);
  bool get isSingleByte => isSingleByteCodecId(codecId);
  bool get isMultibyte => isMultibyteCodecId(codecId);
}

final List<ResolvedCodec> _resolvedCodecs = List<ResolvedCodec>.generate(
  generatedCanonicalNames.length,
  (int index) => ResolvedCodec(index),
  growable: false,
);

String canonicalNameForCodecId(int codecId) => generatedCanonicalNames[codecId];

String pythonCodecNameForCodecId(int codecId) =>
    generatedPythonCodecNames[codecId];

bool isUtfCodecId(int codecId) =>
    (generatedCodecFlags[codecId] & codecFlagUtf) != 0;

bool isSingleByteCodecId(int codecId) =>
    (generatedCodecFlags[codecId] & codecFlagSingleByte) != 0;

bool isMultibyteCodecId(int codecId) =>
    (generatedCodecFlags[codecId] & codecFlagMultibyte) != 0;

String normalizeCodecAlias(String name) {
  return _normalizeCodecAlias(_trimAsciiWhitespace(name));
}

int? resolveCodecId(String name) {
  final String trimmed = _trimAsciiWhitespace(name);
  if (trimmed.isEmpty) {
    return null;
  }

  final String exactKey = _lowerAscii(trimmed);
  final int exactIndex = _binarySearchString(
    generatedCodecExactAliases,
    exactKey,
  );
  if (exactIndex >= 0) {
    return generatedCodecExactAliasCodecIds[exactIndex];
  }

  final String normalizedKey = _normalizeCodecAlias(trimmed);
  if (normalizedKey.isEmpty) {
    return null;
  }
  final int normalizedIndex = _binarySearchString(
    generatedCodecNormalizedAliases,
    normalizedKey,
  );
  if (normalizedIndex < 0) {
    return null;
  }
  return generatedCodecNormalizedAliasCodecIds[normalizedIndex];
}

ResolvedCodec? resolveCodec(String name) {
  final int? codecId = resolveCodecId(name);
  if (codecId == null) {
    return null;
  }
  return _resolvedCodecs[codecId];
}

String _trimAsciiWhitespace(String input) {
  int start = 0;
  int end = input.length;
  while (start < end && _isAsciiWhitespace(input.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isAsciiWhitespace(input.codeUnitAt(end - 1))) {
    end--;
  }
  if (start == 0 && end == input.length) {
    return input;
  }
  return input.substring(start, end);
}

String _lowerAscii(String input) {
  final StringBuffer buffer = StringBuffer();
  bool changed = false;
  for (int i = 0; i < input.length; i++) {
    int code = input.codeUnitAt(i);
    if (code >= 0x41 && code <= 0x5A) {
      code += 0x20;
      changed = true;
    }
    buffer.writeCharCode(code);
  }
  if (!changed) {
    return input;
  }
  return buffer.toString();
}

String _normalizeCodecAlias(String input) {
  final StringBuffer buffer = StringBuffer();
  bool lastUnderscore = false;
  for (int i = 0; i < input.length; i++) {
    int code = input.codeUnitAt(i);
    if (code >= 0x41 && code <= 0x5A) {
      code += 0x20;
    }
    final bool isAlphaNum =
        (code >= 0x61 && code <= 0x7A) || (code >= 0x30 && code <= 0x39);
    if (isAlphaNum) {
      buffer.writeCharCode(code);
      lastUnderscore = false;
      continue;
    }
    if (!lastUnderscore && buffer.length > 0) {
      buffer.writeCharCode(0x5F);
      lastUnderscore = true;
    }
  }
  String normalized = buffer.toString();
  if (normalized.endsWith('_')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _isAsciiWhitespace(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0x0C;
}

int _binarySearchString(List<String> values, String target) {
  int low = 0;
  int high = values.length - 1;
  while (low <= high) {
    final int mid = (low + high) >>> 1;
    final int relation = values[mid].compareTo(target);
    if (relation == 0) {
      return mid;
    }
    if (relation < 0) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}
