// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

const String _nativeAssetName = 'src/native/charset_codec_native_bindings.dart';
const String _nativeCratePath = 'native';
const String _nativeManifestPath =
    'native/assets/generated/native_manifest.json';
const String _nativeRefreshCommand = 'python tool/export_codec_data.py';

Future<void> runCharsetCodecNativeBuild(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  final NativeBuildValidation validation = NativeBuildValidation.load(
    input.packageRoot,
  );
  validation.addBuildDependencies(output);
  validation.ensureFresh();

  final BuildOutputBuilder rustOutput = BuildOutputBuilder();
  await const RustBuilder(
    assetName: _nativeAssetName,
    cratePath: _nativeCratePath,
    buildMode: BuildMode.release,
  ).run(input: input, output: rustOutput);

  _forwardRustBuildOutput(rustOutput.build(), output);
}

void _forwardRustBuildOutput(BuildOutput built, BuildOutputBuilder output) {
  output.dependencies.addAll(
    built.dependencies.where((Uri uri) => !_isCargoDepfile(uri)),
  );
  output.assets.addEncodedAssets(built.assets.encodedAssets);
  output.assets.addEncodedAssets(
    built.assets.encodedAssetsForBuild,
    routing: const ToBuildHooks(),
  );
  for (final MapEntry<String, List<EncodedAsset>> entry
      in built.assets.encodedAssetsForLinking.entries) {
    output.assets.addEncodedAssets(entry.value, routing: ToLinkHook(entry.key));
  }
}

bool _isCargoDepfile(Uri uri) {
  final List<String> segments = uri.pathSegments;
  return segments.isNotEmpty && segments.last.toLowerCase().endsWith('.d');
}

final class NativeBuildValidation {
  NativeBuildValidation._({
    required this.packageRoot,
    required this.manifestFile,
    required Map<String, _NativeBuildHashExpectation> generatorInputs,
    required Map<String, _NativeBuildHashExpectation> requiredOutputs,
  }) : _generatorInputs = generatorInputs,
       _requiredOutputs = requiredOutputs;

  final Uri packageRoot;
  final File manifestFile;
  final Map<String, _NativeBuildHashExpectation> _generatorInputs;
  final Map<String, _NativeBuildHashExpectation> _requiredOutputs;

  static NativeBuildValidation load(Uri packageRoot) {
    final File manifestFile = File.fromUri(
      packageRoot.resolve(_nativeManifestPath),
    );
    if (!manifestFile.existsSync()) {
      throw StateError(
        'Missing native manifest at ${manifestFile.path}. '
        'Run `$_nativeRefreshCommand` before building native assets.',
      );
    }

    final Object? decoded = jsonDecode(manifestFile.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw StateError('Invalid native manifest payload: ${manifestFile.path}');
    }
    final Object? buildValidationRaw = decoded['build_validation'];
    if (buildValidationRaw is! Map<String, Object?>) {
      throw StateError(
        'Native manifest is missing build_validation metadata. '
        'Run `$_nativeRefreshCommand` to refresh generated native assets.',
      );
    }

    return NativeBuildValidation._(
      packageRoot: packageRoot,
      manifestFile: manifestFile,
      generatorInputs: _parseHashMap(
        buildValidationRaw['generator_inputs'],
        sectionName: 'generator_inputs',
      ),
      requiredOutputs: _parseHashMap(
        buildValidationRaw['required_outputs'],
        sectionName: 'required_outputs',
      ),
    );
  }

  void addBuildDependencies(BuildOutputBuilder output) {
    final Set<Uri> dependencies = <Uri>{manifestFile.uri};
    for (final String relativePath in _generatorInputs.keys) {
      dependencies.add(_resolve(relativePath).uri);
    }
    for (final String relativePath in _requiredOutputs.keys) {
      dependencies.add(_resolve(relativePath).uri);
    }
    output.dependencies.addAll(dependencies);
  }

  void ensureFresh() {
    _validateFiles(
      _generatorInputs,
      missingPrefix: 'Missing native build input',
      mismatchPrefix: 'Stale native build input',
    );
    _validateFiles(
      _requiredOutputs,
      missingPrefix: 'Missing generated native asset',
      mismatchPrefix: 'Stale generated native asset',
    );
  }

  void _validateFiles(
    Map<String, _NativeBuildHashExpectation> expectedHashes, {
    required String missingPrefix,
    required String mismatchPrefix,
  }) {
    for (final MapEntry<String, _NativeBuildHashExpectation> entry
        in expectedHashes.entries) {
      final File file = _resolve(entry.key);
      if (!file.existsSync()) {
        throw StateError(
          '$missingPrefix: ${entry.key}. '
          'Run `$_nativeRefreshCommand` before building native assets.',
        );
      }
      final String actualHash = entry.value.normalizeNewlines
          ? _sha256WithNormalizedNewlines(file)
          : _sha256(file);
      if (entry.value.matches(file, precomputedSha256: actualHash)) {
        continue;
      }
      if (actualHash != entry.value.sha256) {
        throw StateError(
          '$mismatchPrefix: ${entry.key}. '
          'Expected ${entry.value.sha256}, got $actualHash. '
          'Run `$_nativeRefreshCommand` before building native assets.',
        );
      }
    }
  }

  File _resolve(String relativePath) =>
      File.fromUri(packageRoot.resolve(relativePath));
}

Map<String, _NativeBuildHashExpectation> _parseHashMap(
  Object? raw, {
  required String sectionName,
}) {
  if (raw is! Map<String, Object?>) {
    throw StateError('Invalid native manifest $sectionName section.');
  }
  final Map<String, _NativeBuildHashExpectation> out =
      <String, _NativeBuildHashExpectation>{};
  for (final MapEntry<String, Object?> entry in raw.entries) {
    final Object? value = entry.value;
    if (value is! Map<String, Object?>) {
      throw StateError('Invalid native manifest entry for ${entry.key}.');
    }
    final Object? sha256Value = value['sha256'];
    if (sha256Value is! String || sha256Value.isEmpty) {
      throw StateError(
        'Missing sha256 for native manifest entry ${entry.key}.',
      );
    }
    final Object? normalizedValue = value['sha256_no_ascii_ws'];
    if (normalizedValue != null &&
        (normalizedValue is! String || normalizedValue.isEmpty)) {
      throw StateError(
        'Invalid sha256_no_ascii_ws for native manifest entry ${entry.key}.',
      );
    }
    final Object? normalizeNewlinesValue = value['normalize_newlines'];
    if (normalizeNewlinesValue != null && normalizeNewlinesValue is! bool) {
      throw StateError(
        'Invalid normalize_newlines for native manifest entry ${entry.key}.',
      );
    }
    out[entry.key] = _NativeBuildHashExpectation(
      sha256: sha256Value,
      sha256NoAsciiWhitespace: normalizedValue as String?,
      normalizeNewlines: normalizeNewlinesValue as bool? ?? false,
    );
  }
  return out;
}

String _sha256(File file) {
  final Digest digest = sha256.convert(file.readAsBytesSync());
  return digest.toString();
}

String _sha256WithNormalizedNewlines(File file) {
  final List<int> bytes = file.readAsBytesSync();
  if (!bytes.contains(0x0D)) {
    return sha256.convert(bytes).toString();
  }

  // Git may check out CRLF on some platforms. Normalize text line endings
  // without relaxing validation for any other bytes.
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
  return sha256.convert(normalized).toString();
}

String _sha256NoAsciiWhitespace(File file) {
  final List<int> bytes = file
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
  final Digest digest = sha256.convert(bytes);
  return digest.toString();
}

final class _NativeBuildHashExpectation {
  const _NativeBuildHashExpectation({
    required this.sha256,
    this.sha256NoAsciiWhitespace,
    this.normalizeNewlines = false,
  });

  final String sha256;
  final String? sha256NoAsciiWhitespace;
  final bool normalizeNewlines;

  bool matches(File file, {String? precomputedSha256}) {
    final String exactHash =
        precomputedSha256 ??
        (normalizeNewlines
            ? _sha256WithNormalizedNewlines(file)
            : _sha256(file));
    if (exactHash == sha256) {
      return true;
    }
    final String? normalizedHash = sha256NoAsciiWhitespace;
    if (normalizedHash == null) {
      return false;
    }
    return _sha256NoAsciiWhitespace(file) == normalizedHash;
  }
}
