// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

final class FixtureManifestEntry {
  const FixtureManifestEntry({
    required this.path,
    required this.sha256,
    required this.size,
  });

  factory FixtureManifestEntry.fromJson(Map<String, Object?> json) {
    return FixtureManifestEntry(
      path: json['path'] as String,
      sha256: json['sha256'] as String,
      size: (json['size'] as num).toInt(),
    );
  }

  final String path;
  final String sha256;
  final int size;
}

final class CodecVectorCase {
  const CodecVectorCase({
    required this.id,
    required this.operation,
    required this.encoding,
    required this.errors,
    this.inputHex,
    this.inputText,
    this.expectedHex,
    this.expectedText,
    required this.expectError,
  });

  factory CodecVectorCase.fromJson(Map<String, Object?> json) {
    return CodecVectorCase(
      id: json['id'] as String,
      operation: json['operation'] as String,
      encoding: json['encoding'] as String,
      errors: json['errors'] as String,
      inputHex: json['inputHex'] as String?,
      inputText: json['inputText'] as String?,
      expectedHex: json['expectedHex'] as String?,
      expectedText: json['expectedText'] as String?,
      expectError: (json['expectError'] as bool?) ?? false,
    );
  }

  final String id;
  final String operation;
  final String encoding;
  final String errors;
  final String? inputHex;
  final String? inputText;
  final String? expectedHex;
  final String? expectedText;
  final bool expectError;
}

final class CodecMapCase {
  const CodecMapCase({
    required this.encoding,
    required this.pythonCodec,
    required this.bytesHex,
    required this.text,
    required this.source,
    required this.roundtrip,
  });

  factory CodecMapCase.fromJson(Map<String, Object?> json) {
    return CodecMapCase(
      encoding: json['encoding'] as String,
      pythonCodec: json['pythonCodec'] as String,
      bytesHex: json['bytesHex'] as String,
      text: json['text'] as String,
      source: json['source'] as String,
      roundtrip: (json['roundtrip'] as bool?) ?? false,
    );
  }

  final String encoding;
  final String pythonCodec;
  final String bytesHex;
  final String text;
  final String source;
  final bool roundtrip;
}

const String fixturePrepareInstruction =
    'Fixtures missing. Run: pwsh -File tool/prepare_test_fixtures.ps1';

Directory get _packageRootDirectory {
  Directory current = Directory.current.absolute;
  while (true) {
    final File pubspec = File.fromUri(current.uri.resolve('pubspec.yaml'));
    if (pubspec.existsSync()) {
      final String pubspecText = pubspec.readAsStringSync();
      if (pubspecText.contains('name: charset_codec')) {
        return current;
      }
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Unable to locate charset_codec package root from ');
    }
    current = parent;
  }
}

Directory get fixturesRootDirectory =>
    Directory.fromUri(_packageRootDirectory.uri.resolve('test/.fixtures/'));
File get fixtureManifestFile =>
    File.fromUri(fixturesRootDirectory.uri.resolve('manifest.json'));
File get fixtureReadyFile =>
    File.fromUri(fixturesRootDirectory.uri.resolve('.ready'));

String? hasFixturesOrSkipReason() {
  if (!fixturesRootDirectory.existsSync()) {
    return fixturePrepareInstruction;
  }
  if (!fixtureManifestFile.existsSync()) {
    return fixturePrepareInstruction;
  }
  if (!fixtureReadyFile.existsSync()) {
    return fixturePrepareInstruction;
  }
  return null;
}

Map<String, Object?> loadFixtureManifest() {
  final String? reason = hasFixturesOrSkipReason();
  if (reason != null) {
    throw StateError(reason);
  }
  final Object? decoded = jsonDecode(fixtureManifestFile.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw StateError('Invalid fixture manifest payload');
  }
  return decoded;
}

List<FixtureManifestEntry> loadFixtureManifestEntries() {
  final Map<String, Object?> manifest = loadFixtureManifest();
  final Object? filesRaw = manifest['files'];
  if (filesRaw is! List<Object?>) {
    return const <FixtureManifestEntry>[];
  }
  return filesRaw
      .whereType<Map<String, Object?>>()
      .map(FixtureManifestEntry.fromJson)
      .toList(growable: false);
}

File _resolveManifestPath(String key) {
  final Map<String, Object?> manifest = loadFixtureManifest();
  final Object? pathsRaw = manifest['paths'];
  if (pathsRaw is! Map<String, Object?>) {
    throw StateError('Manifest paths section missing');
  }
  final String? rel = pathsRaw[key] as String?;
  if (rel == null || rel.isEmpty) {
    throw StateError('Manifest path key missing: $key');
  }
  return File('${fixturesRootDirectory.path}/$rel');
}

List<CodecVectorCase> loadCodecVectorCases() {
  final File vectorsFile = _resolveManifestPath('codecVectors');
  if (!vectorsFile.existsSync()) {
    throw StateError('Codec vectors file missing: ${vectorsFile.path}');
  }
  final List<CodecVectorCase> out = <CodecVectorCase>[];
  for (final String line in vectorsFile.readAsLinesSync()) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final Object? decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, Object?>) {
      continue;
    }
    out.add(CodecVectorCase.fromJson(decoded));
  }
  return out;
}

List<CodecMapCase> loadCodecMapCases({int? perEncodingLimit}) {
  final File mapFile = _resolveManifestPath('mapCases');
  if (!mapFile.existsSync()) {
    throw StateError('Codec map file missing: ${mapFile.path}');
  }
  final Map<String, int> countsByEncoding = <String, int>{};
  final List<CodecMapCase> out = <CodecMapCase>[];
  for (final String line in mapFile.readAsLinesSync()) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final Object? decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, Object?>) {
      continue;
    }
    final CodecMapCase item = CodecMapCase.fromJson(decoded);
    if (perEncodingLimit != null) {
      final int used = countsByEncoding[item.encoding] ?? 0;
      if (used >= perEncodingLimit) {
        continue;
      }
      countsByEncoding[item.encoding] = used + 1;
    }
    out.add(item);
  }
  return out;
}

List<int> hexToBytes(String hex) {
  String normalized = hex.trim();
  if (normalized.isEmpty) {
    return const <int>[];
  }
  if (normalized.length.isOdd) {
    normalized = '0$normalized';
  }
  final List<int> out = <int>[];
  for (int i = 0; i < normalized.length; i += 2) {
    out.add(int.parse(normalized.substring(i, i + 2), radix: 16));
  }
  return out;
}
