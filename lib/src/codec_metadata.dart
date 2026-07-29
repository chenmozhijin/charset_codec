// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:collection';

import 'codec/resolver.dart';
import 'generated/codec_alias_data.g.dart';
import 'generated/codec_meta_data.g.dart';

/// Describes a codec resolved by this package.
///
/// Includes the canonical name, Python-compatible name, and implementation
/// category.
final class CodecInfo {
  /// Creates immutable codec metadata.
  ///
  /// Instances are normally obtained through [lookupCodecInfo]. The public
  /// constructor allows metadata to be persisted or compared.
  const CodecInfo({
    required this.canonicalName,
    required this.pythonCodecName,
    required this.isUtf,
    required this.isSingleByte,
    required this.isMultibyte,
  });

  /// The package's normalized canonical name, such as `utf_8`.
  final String canonicalName;

  /// The codec name used to align behavior with CPython.
  final String pythonCodecName;

  /// Whether this codec belongs to the Unicode UTF family.
  final bool isUtf;

  /// Whether each input byte maps independently to one character.
  final bool isSingleByte;

  /// Whether the codec uses a multibyte or stateful byte representation.
  final bool isMultibyte;
}

/// Looks up metadata for [encoding], accepting canonical names and aliases.
///
/// Returns `null` for unknown names without loading or warming the codec table.
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

/// All normalized CPython codec names supported by this package.
///
/// Returns a read-only view; callers should not depend on iteration order.
Iterable<String> get supportedPythonCodecNames => _supportedPythonCodecNames;
