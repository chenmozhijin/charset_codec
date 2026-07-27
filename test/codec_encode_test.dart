// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:test/test.dart';

void main() {
  test('table-backed multibyte codecs encode a known multibyte scalar', () {
    for (final String name in generatedMultibyteDecodeTableCodecs) {
      final int sampleScalar = generatedMbcsSampleMultibyteScalarByCodec[name]!;
      final List<int> sampleBytes =
          generatedMbcsSampleMultibyteBytesByCodec[name]!;
      final String text = String.fromCharCode(sampleScalar);
      final List<int> encoded = encodeString(text, encoding: name);
      expect(encoded, equals(sampleBytes), reason: 'codec=$name');
    }
  });

  test('stateful multibyte codecs encode known scalars', () {
    expect(
      encodeString(String.fromCharCode(0x80), encoding: 'gb18030'),
      equals(const <int>[0x81, 0x30, 0x81, 0x30]),
    );
    expect(
      encodeString(String.fromCharCode(0x1F600), encoding: 'gb18030'),
      equals(const <int>[0x94, 0x39, 0xFC, 0x36]),
    );

    final List<int> hz = encodeString(
      String.fromCharCode(0x554A),
      encoding: 'hz-gb-2312',
    );
    expect(hz, equals(const <int>[0x7E, 0x7B, 0x30, 0x21, 0x7E, 0x7D]));

    final List<int> iso = encodeString(
      String.fromCharCode(0xAC00),
      encoding: 'iso-2022-kr',
    );
    expect(
      iso,
      equals(const <int>[0x1B, 0x24, 0x29, 0x43, 0x0E, 0x30, 0x21, 0x0F]),
    );

    expect(
      encodeString(String.fromCharCode(0x3042), encoding: 'iso2022-jp-2'),
      equals(const <int>[0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42]),
    );
    expect(
      encodeString(String.fromCharCode(0x02D8), encoding: 'iso2022-jp-ext'),
      equals(const <int>[0x1B, 0x24, 0x28, 0x44, 0x22, 0x2F, 0x1B, 0x28, 0x42]),
    );
    expect(
      encodeString(String.fromCharCode(0x02D8), encoding: 'iso2022-jp-2004'),
      equals(const <int>[0x1B, 0x24, 0x28, 0x51, 0x2A, 0x22, 0x1B, 0x28, 0x42]),
    );
  });

  test('split compatibility aliases encode as independent codecs', () {
    expect(
      encodeString('\u00A4', encoding: 'cp037'),
      equals(const <int>[0x9F]),
    );
    expect(
      encodeString('\u20AC', encoding: 'cp1140'),
      equals(const <int>[0x9F]),
    );
    expect(
      () => encodeString('\u20AC', encoding: 'cp037'),
      throwsA(isA<CodecException>()),
    );

    expect(
      encodeString('\u00A0', encoding: 'iso-8859-11'),
      equals(const <int>[0xA0]),
    );
    expect(
      () => encodeString('\u00A0', encoding: 'tis-620'),
      throwsA(isA<CodecException>()),
    );

    expect(encodeString('丂', encoding: 'gbk'), equals(const <int>[0x81, 0x40]));
    expect(
      () => encodeString('丂', encoding: 'gb2312'),
      throwsA(isA<CodecException>()),
    );

    expect(
      encodeString('\uFF07', encoding: 'euc-jisx0213'),
      equals(const <int>[0xA2, 0xAF]),
    );
    expect(
      () => encodeString('\uFF07', encoding: 'euc-jp'),
      throwsA(isA<CodecException>()),
    );

    expect(
      encodeString('\\', encoding: 'shift_jis'),
      equals(const <int>[0x5C]),
    );
    expect(
      encodeString('\\', encoding: 'shift-jisx0213'),
      equals(const <int>[0x81, 0x5F]),
    );

    expect(
      encodeString('あ', encoding: 'iso-2022-jp'),
      equals(const <int>[0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42]),
    );
    expect(
      encodeString('\u02D8', encoding: 'iso2022-jp-1'),
      equals(const <int>[0x1B, 0x24, 0x28, 0x44, 0x22, 0x2F, 0x1B, 0x28, 0x42]),
    );
    expect(
      encodeString('\u3000', encoding: 'iso2022-jp-3'),
      equals(const <int>[0x1B, 0x24, 0x42, 0x21, 0x21, 0x1B, 0x28, 0x42]),
    );
  });

  test('all registered multibyte codecs have encode implementations', () {
    expect(generatedMultibytePendingCodecs, isEmpty);
  });
}
