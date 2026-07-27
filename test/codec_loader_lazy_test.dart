// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/codec/data_loader.dart';
import 'package:charset_codec/src/codec/resolver.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:charset_codec/src/native/native_bridge.dart';
import 'package:test/test.dart';

bool _usesNativeForCodec(String encoding) {
  final ResolvedCodec? resolved = resolveCodec(encoding);
  if (resolved == null) {
    return false;
  }
  return nativeCodecBridge.supportsCodec(resolved);
}

void main() {
  setUp(() {
    CodecDataLoader.resetCachesForTesting();
  });

  test('utf-8 decode does not load multibyte tables', () {
    final String decoded = decodeBytes(const <int>[
      0x61,
      0x62,
      0x63,
    ], encoding: 'utf-8');
    expect(decoded, equals('abc'));
    expect(CodecDataLoader.isMbcsDecodeLoaded('cp932'), isFalse);
    expect(CodecDataLoader.isMbcsEncodeLoaded('cp932'), isFalse);
  });

  test('cp932 decode loads decode tables only', () {
    final List<int> sample = generatedMbcsSampleMultibyteBytesByCodec['cp932']!;
    final String decoded = decodeBytes(sample, encoding: 'cp932');
    expect(decoded, isNotEmpty);
    expect(
      CodecDataLoader.isMbcsDecodeLoaded('cp932'),
      _usesNativeForCodec('cp932') ? isFalse : isTrue,
    );
    expect(CodecDataLoader.isMbcsEncodeLoaded('cp932'), isFalse);
  });

  test('cp932 decode does not load triple table when max length is 2', () {
    expect(generatedMbcsMaxSequenceLength['cp932'], equals(2));
    final List<int> sample = generatedMbcsSampleMultibyteBytesByCodec['cp932']!;
    decodeBytes(sample, encoding: 'cp932');
    expect(
      CodecDataLoader.isMbcsSingleDecodeLoaded('cp932'),
      _usesNativeForCodec('cp932') ? isFalse : isTrue,
    );
    expect(
      CodecDataLoader.isMbcsDoubleDecodeLoaded('cp932'),
      _usesNativeForCodec('cp932') ? isFalse : isTrue,
    );
    expect(CodecDataLoader.isMbcsTripleDecodeLoaded('cp932'), isFalse);
  });

  test('euc-jp decode loads triple table when max length is 3', () {
    expect(generatedMbcsMaxSequenceLength['euc-jp'], equals(3));
    final List<int> sample =
        generatedMbcsSampleMultibyteBytesByCodec['euc-jp']!;
    decodeBytes(sample, encoding: 'euc-jp');
    final bool native = _usesNativeForCodec('euc-jp');
    expect(
      CodecDataLoader.isMbcsSingleDecodeLoaded('euc-jp'),
      native ? isFalse : isTrue,
    );
    expect(
      CodecDataLoader.isMbcsDoubleDecodeLoaded('euc-jp'),
      native ? isFalse : isTrue,
    );
    expect(
      CodecDataLoader.isMbcsTripleDecodeLoaded('euc-jp'),
      native ? isFalse : isTrue,
    );
  });

  test('cp932 encode loads encode tables lazily', () {
    final int cp = generatedMbcsSampleMultibyteScalarByCodec['cp932']!;
    final String text = String.fromCharCode(cp);
    final List<int> encoded = encodeString(text, encoding: 'cp932');
    expect(encoded, isNotEmpty);
    expect(
      CodecDataLoader.isMbcsEncodeLoaded('cp932'),
      _usesNativeForCodec('cp932') ? isFalse : isTrue,
    );
  });
}
