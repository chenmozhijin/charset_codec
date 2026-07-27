// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/src/codec/resolver.dart';
import 'package:charset_codec/src/generated/codec_alias_data.g.dart';
import 'package:charset_codec/src/generated/native_codec_matrix.g.dart';
import 'package:charset_codec/src/native/native_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('generated native route matrix covers every canonical codec', () {
    expect(
      generatedNativeCodecSupportedById,
      hasLength(generatedCanonicalNames.length),
    );
    expect(generatedNativeCodecSupportedById, everyElement(isTrue));
  });

  test('active native bridge follows the generated route matrix', () {
    for (int codecId = 0; codecId < generatedCanonicalNames.length; codecId++) {
      final ResolvedCodec resolved = ResolvedCodec(codecId);
      expect(
        nativeCodecBridge.supportsCodec(resolved),
        nativeCodecBridge.isAvailable &&
            generatedNativeCodecSupportedById[codecId],
        reason: resolved.canonicalName,
      );
    }
  });
}
