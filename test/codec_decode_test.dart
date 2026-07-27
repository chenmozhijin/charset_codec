// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:test/test.dart';

void main() {
  test('table-backed multibyte codecs decode a known multibyte sequence', () {
    for (final String name in generatedMultibyteDecodeTableCodecs) {
      final int sampleScalar = generatedMbcsSampleMultibyteScalarByCodec[name]!;
      final List<int> sampleBytes =
          generatedMbcsSampleMultibyteBytesByCodec[name]!;
      final String decoded = decodeBytes(sampleBytes, encoding: name);
      expect(decoded.runes.length, equals(1), reason: 'codec=$name');
      expect(decoded.runes.single, equals(sampleScalar), reason: 'codec=$name');
    }
  });

  test('stateful multibyte codecs decode known sequences', () {
    expect(
      decodeBytes(const <int>[0x81, 0x30, 0x81, 0x30], encoding: 'gb18030'),
      equals(String.fromCharCode(0x80)),
    );
    expect(
      decodeBytes(const <int>[0x94, 0x39, 0xFC, 0x36], encoding: 'gb18030'),
      equals(String.fromCharCode(0x1F600)),
    );

    const List<int> hzBytes = <int>[0x7E, 0x7B, 0x30, 0x21, 0x7E, 0x7D];
    expect(
      decodeBytes(hzBytes, encoding: 'hz-gb-2312'),
      equals(String.fromCharCode(0x554A)),
    );

    const List<int> iso2022krBytes = <int>[
      0x1B,
      0x24,
      0x29,
      0x43,
      0x0E,
      0x30,
      0x21,
      0x0F,
    ];
    expect(
      decodeBytes(iso2022krBytes, encoding: 'iso-2022-kr'),
      equals(String.fromCharCode(0xAC00)),
    );

    expect(
      decodeBytes(const <int>[
        0x1B,
        0x24,
        0x42,
        0x24,
        0x22,
        0x1B,
        0x28,
        0x42,
      ], encoding: 'iso2022-jp-2'),
      equals(String.fromCharCode(0x3042)),
    );
    expect(
      decodeBytes(const <int>[
        0x1B,
        0x24,
        0x28,
        0x44,
        0x22,
        0x2F,
        0x1B,
        0x28,
        0x42,
      ], encoding: 'iso2022-jp-ext'),
      equals(String.fromCharCode(0x02D8)),
    );
    expect(
      decodeBytes(const <int>[
        0x1B,
        0x24,
        0x28,
        0x51,
        0x2A,
        0x22,
        0x1B,
        0x28,
        0x42,
      ], encoding: 'iso2022-jp-2004'),
      equals(String.fromCharCode(0x02D8)),
    );
  });

  test('split compatibility aliases decode as independent codecs', () {
    expect(decodeBytes(const <int>[0x9F], encoding: 'cp037'), equals('\u00A4'));
    expect(
      decodeBytes(const <int>[0x9F], encoding: 'cp1140'),
      equals('\u20AC'),
    );

    expect(
      decodeBytes(const <int>[0xA0], encoding: 'iso-8859-11'),
      equals('\u00A0'),
    );
    expect(
      () => decodeBytes(const <int>[0xA0], encoding: 'tis-620'),
      throwsA(isA<CodecException>()),
    );

    expect(decodeBytes(const <int>[0x81, 0x40], encoding: 'gbk'), equals('丂'));
    expect(
      () => decodeBytes(const <int>[0x81, 0x40], encoding: 'gb2312'),
      throwsA(isA<CodecException>()),
    );

    expect(
      decodeBytes(const <int>[0xA2, 0xAF], encoding: 'euc-jisx0213'),
      equals('\uFF07'),
    );
    expect(
      () => decodeBytes(const <int>[0xA2, 0xAF], encoding: 'euc-jp'),
      throwsA(isA<CodecException>()),
    );

    expect(decodeBytes(const <int>[0x5C], encoding: 'shift_jis'), equals('\\'));
    expect(
      decodeBytes(const <int>[0x5C], encoding: 'shift-jisx0213'),
      equals('\u00A5'),
    );

    final List<int> jp2Only = <int>[
      0x1B,
      0x24,
      0x28,
      0x43,
      0x21,
      0x21,
      0x1B,
      0x28,
      0x42,
    ];
    expect(decodeBytes(jp2Only, encoding: 'iso2022-jp-2'), equals('\u3000'));
    expect(
      () => decodeBytes(jp2Only, encoding: 'iso-2022-jp'),
      throwsA(isA<CodecException>()),
    );
    expect(
      () => decodeBytes(jp2Only, encoding: 'iso2022-jp-1'),
      throwsA(isA<CodecException>()),
    );

    final List<int> jp2004Only = <int>[
      0x1B,
      0x24,
      0x28,
      0x51,
      0x21,
      0x21,
      0x1B,
      0x28,
      0x42,
    ];
    expect(
      decodeBytes(jp2004Only, encoding: 'iso2022-jp-2004'),
      equals('\u3000'),
    );
    expect(
      () => decodeBytes(jp2004Only, encoding: 'iso2022-jp-3'),
      throwsA(isA<CodecException>()),
    );
  });

  test('all registered multibyte codecs have decode implementations', () {
    expect(generatedMultibytePendingCodecs, isEmpty);
  });
}
