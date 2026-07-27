// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('native build manifest validation metadata is in sync', () {
    final File manifestFile = File(
      'native/assets/generated/native_manifest.json',
    );
    expect(manifestFile.existsSync(), isTrue);

    final Object? decoded = jsonDecode(manifestFile.readAsStringSync());
    expect(decoded, isA<Map<String, Object?>>());
    final Map<String, Object?> manifest = decoded! as Map<String, Object?>;

    final Map<String, Object?> buildValidation =
        manifest['build_validation']! as Map<String, Object?>;
    final Map<String, Object?> generatorInputs =
        buildValidation['generator_inputs']! as Map<String, Object?>;
    final Map<String, Object?> requiredOutputs =
        buildValidation['required_outputs']! as Map<String, Object?>;

    expect(generatorInputs, isNotEmpty);
    expect(requiredOutputs, isNotEmpty);
    expect(generatorInputs.containsKey('tool/export_codec_data.py'), isTrue);
    expect(
      requiredOutputs.containsKey('native/generated/codec_index.rs'),
      isTrue,
    );
    expect(
      generatorInputs.values.every(
        (Object? value) =>
            (value! as Map<String, Object?>)['normalize_newlines'] == true,
      ),
      isTrue,
    );

    void verifyGroup(Map<String, Object?> entries) {
      for (final MapEntry<String, Object?> entry in entries.entries) {
        final File file = File(entry.key);
        expect(file.existsSync(), isTrue, reason: 'missing ${entry.key}');
        final Map<String, Object?> value = entry.value! as Map<String, Object?>;
        final String expectedHash = value['sha256']! as String;
        final bool normalizeNewlines =
            value['normalize_newlines'] as bool? ?? false;
        final List<int> sourceBytes = file.readAsBytesSync();
        final List<int> hashBytes = normalizeNewlines
            ? _normalizeNewlines(sourceBytes)
            : sourceBytes;
        final String actualHash = sha256.convert(hashBytes).toString();
        if (actualHash == expectedHash) {
          continue;
        }
        final String? normalizedHash = value['sha256_no_ascii_ws'] as String?;
        expect(normalizedHash, isNotNull, reason: 'stale ${entry.key}');
        final List<int> normalizedBytes = file
            .readAsBytesSync()
            .where(
              (int byte) =>
                  byte != 0x09 &&
                  byte != 0x0A &&
                  byte != 0x0C &&
                  byte != 0x0D &&
                  byte != 0x20,
            )
            .toList(growable: false);
        final String actualNormalizedHash = sha256
            .convert(normalizedBytes)
            .toString();
        expect(
          actualNormalizedHash,
          normalizedHash,
          reason: 'stale ${entry.key}',
        );
      }
    }

    verifyGroup(generatorInputs);
    verifyGroup(requiredOutputs);
  });

  test('native manifest text hashes normalize platform newlines', () {
    expect(_normalizeNewlines('a\nb\n'.codeUnits), 'a\nb\n'.codeUnits);
    expect(_normalizeNewlines('a\r\nb\r\n'.codeUnits), 'a\nb\n'.codeUnits);
    expect(_normalizeNewlines('a\rb\r'.codeUnits), 'a\nb\n'.codeUnits);
  });
}

List<int> _normalizeNewlines(List<int> bytes) {
  // 测试使用与 build hook 相同的规则，确保 LF/CRLF checkout 产生同一文本哈希。
  final List<int> normalized = <int>[];
  for (var index = 0; index < bytes.length; index += 1) {
    final int byte = bytes[index];
    if (byte != 0x0D) {
      normalized.add(byte);
      continue;
    }
    normalized.add(0x0A);
    if (index + 1 < bytes.length && bytes[index + 1] == 0x0A) {
      index += 1;
    }
  }
  return normalized;
}
