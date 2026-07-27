// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:test/test.dart';

String _pickTableBackedCodec() {
  if (generatedMultibyteDecodeTableCodecs.contains('cp932')) {
    return 'cp932';
  }
  return generatedMultibyteDecodeTableCodecs.first;
}

String _sampleTextForEncoding(String encoding) {
  if (encoding == 'ascii') {
    return 'Hello';
  }
  if (encoding == 'utf-7') {
    return 'A\u2262\u0391.';
  }
  if (encoding == _pickTableBackedCodec()) {
    final int cp = generatedMbcsSampleMultibyteScalarByCodec[encoding]!;
    return String.fromCharCode(cp);
  }
  return 'abc';
}

void main() {
  final String mbcs = _pickTableBackedCodec();
  final List<String> encodings = <String>[
    'ascii',
    'utf-8',
    'utf-16',
    'utf-32',
    'utf-7',
    mbcs,
  ];

  test('incremental decoder matches one-shot across codec families', () {
    for (final String encoding in encodings) {
      final String text = _sampleTextForEncoding(encoding);
      final List<int> bytes = encodeString(text, encoding: encoding);
      final String oneShot = decodeBytes(bytes, encoding: encoding);
      final int cut = bytes.length ~/ 2;

      final IncrementalDecoder dec = codec(encoding).newDecoder();
      final String out1 = dec.feed(bytes.sublist(0, cut));
      final String out2 = dec.feed(bytes.sublist(cut), finalChunk: true);
      final String out3 = dec.close();
      expect('$out1$out2$out3', equals(oneShot), reason: 'encoding=$encoding');
    }
  });

  test('incremental decoder state restore preserves behavior', () {
    for (final String encoding in encodings) {
      final String text = _sampleTextForEncoding(encoding);
      final List<int> bytes = encodeString(text, encoding: encoding);
      final String oneShot = decodeBytes(bytes, encoding: encoding);
      final int cut = bytes.length ~/ 2;

      final IncrementalDecoder source = codec(encoding).newDecoder();
      final String prefix = source.feed(bytes.sublist(0, cut));
      final Object state = source.getState();

      final IncrementalDecoder restored = codec(encoding).newDecoder();
      restored.setState(state);
      final String suffix =
          restored.feed(bytes.sublist(cut), finalChunk: true) +
          restored.close();
      expect('$prefix$suffix', equals(oneShot), reason: 'encoding=$encoding');
    }
  });

  test('incremental encoder matches one-shot across codec families', () {
    for (final String encoding in encodings) {
      final String text = _sampleTextForEncoding(encoding);
      final List<int> oneShot = encodeString(text, encoding: encoding);
      final int cut = text.length ~/ 2;

      final IncrementalEncoder enc = codec(encoding).newEncoder();
      final List<int> out1 = enc.feed(text.substring(0, cut));
      final List<int> out2 = enc.feed(text.substring(cut), finalChunk: true);
      final List<int> out3 = enc.close();
      expect(
        <int>[...out1, ...out2, ...out3],
        equals(oneShot),
        reason: 'encoding=$encoding',
      );
    }
  });

  test('incremental encoder state restore preserves behavior', () {
    for (final String encoding in encodings) {
      final String text = _sampleTextForEncoding(encoding);
      final List<int> oneShot = encodeString(text, encoding: encoding);
      final int cut = text.length ~/ 2;

      final IncrementalEncoder source = codec(encoding).newEncoder();
      final List<int> prefix = source.feed(text.substring(0, cut));
      final Object state = source.getState();

      final IncrementalEncoder restored = codec(encoding).newEncoder();
      restored.setState(state);
      final List<int> suffix = <int>[
        ...restored.feed(text.substring(cut), finalChunk: true),
        ...restored.close(),
      ];
      expect(
        <int>[...prefix, ...suffix],
        equals(oneShot),
        reason: 'encoding=$encoding',
      );
    }
  });

  test('incremental decoder reset clears pending state', () {
    final String encoding = 'utf-7';
    final List<int> bytes = encodeString('A\u2262\u0391.', encoding: encoding);
    final IncrementalDecoder dec = codec(encoding).newDecoder();
    dec.feed(bytes.sublist(0, bytes.length ~/ 2));
    dec.reset();
    final String decoded = dec.feed(bytes, finalChunk: true) + dec.close();
    expect(decoded, equals('A\u2262\u0391.'));
  });

  test('incremental encoder reset clears pending state', () {
    final String encoding = 'utf-7';
    final IncrementalEncoder enc = codec(encoding).newEncoder();
    enc.feed('A\u2262');
    enc.reset();
    final List<int> encoded = <int>[
      ...enc.feed('A\u2262\u0391.', finalChunk: true),
      ...enc.close(),
    ];
    expect(encoded, equals(encodeString('A\u2262\u0391.', encoding: encoding)));
  });

  test('incremental setState validates input types', () {
    final IncrementalDecoder dec = codec('utf-8').newDecoder();
    final IncrementalEncoder enc = codec('utf-8').newEncoder();
    expect(() => dec.setState('bad'), throwsA(isA<ArgumentError>()));
    expect(() => enc.setState(123), throwsA(isA<ArgumentError>()));
  });

  test('incremental close is terminal and repeat close is empty', () {
    final IncrementalDecoder dec = codec('utf-8').newDecoder();
    expect(dec.feed('A'.codeUnits, finalChunk: true), equals('A'));
    expect(dec.close(), equals(''));
    expect(dec.close(), equals(''));
    expect(() => dec.feed('B'.codeUnits), throwsStateError);
    expect(dec.getState, throwsStateError);

    final IncrementalEncoder enc = codec('utf-8').newEncoder();
    expect(
      enc.feed('A', finalChunk: true),
      equals(encodeString('A', encoding: 'utf-8')),
    );
    expect(enc.close(), isEmpty);
    expect(enc.close(), isEmpty);
    expect(() => enc.feed('B'), throwsStateError);
    expect(enc.getState, throwsStateError);
  });

  test(
    'incremental decoder emits decoded prefix before final chunk (cp949)',
    () {
      final List<int> bytes = encodeString('파이썬 마을', encoding: 'cp949');
      final IncrementalDecoder dec = codec('cp949').newDecoder();

      final String out1 = dec.feed(bytes.sublist(0, 5));
      final String out2 = dec.feed(bytes.sublist(5, bytes.length - 1));
      final String out3 =
          dec.feed(bytes.sublist(bytes.length - 1), finalChunk: true) +
          dec.close();

      expect(out1, equals('파이'));
      expect('$out1$out2$out3', equals('파이썬 마을'));
    },
  );

  test('incremental decoder keeps trailing byte pending across chunks', () {
    final IncrementalDecoder dec = codec('euc-jp').newDecoder();
    expect(dec.feed(const <int>[0xA4]), equals(''));
    expect(dec.feed(const <int>[0xA6]), equals('う'));
    expect(dec.close(), equals(''));
  });

  test(
    'incremental decoder state replay preserves partial multibyte context',
    () {
      final IncrementalDecoder source = codec('euc-jp').newDecoder();
      expect(source.feed(const <int>[0xA4]), equals(''));
      final Object state = source.getState();

      final IncrementalDecoder restored = codec('euc-jp').newDecoder();
      restored.setState(state);
      expect(restored.feed(const <int>[0xA6], finalChunk: true), equals('う'));
      expect(restored.close(), equals(''));
    },
  );

  test(
    'incremental decoder preserves iso-2022-jp escape state across chunks',
    () {
      final IncrementalDecoder dec = codec('iso-2022-jp').newDecoder();
      expect(dec.feed(const <int>[0x1B, 0x24]), equals(''));
      expect(dec.feed(const <int>[0x42]), equals(''));
      expect(dec.feed(const <int>[0x40, 0x24]), equals('世'));
      expect(dec.feed(const <int>[0x1B, 0x28, 0x42]), equals(''));
      expect(dec.feed(const <int>[0x7A], finalChunk: true), equals('z'));
      expect(dec.close(), equals(''));
    },
  );

  test('incremental utf-8-sig decoder buffers BOM across chunks', () {
    final IncrementalDecoder dec = codec('utf-8-sig').newDecoder();
    expect(dec.feed(const <int>[0xEF]), equals(''));
    expect(dec.feed(const <int>[0xBB]), equals(''));
    expect(dec.feed(const <int>[0xBF, 0x41]), equals('A'));
    expect(dec.close(), equals(''));
  });

  test('incremental utf-16 decoder preserves split surrogate pairs', () {
    final List<int> bytes = encodeString('A😀', encoding: 'utf-16');
    final IncrementalDecoder dec = codec('utf-16').newDecoder();

    expect(dec.feed(bytes.sublist(0, 1)), equals(''));
    expect(dec.feed(bytes.sublist(1, 5)), equals('A'));
    expect(dec.feed(bytes.sublist(5), finalChunk: true), equals('😀'));
    expect(dec.close(), equals(''));
  });

  test(
    'incremental utf-16 encoder emits BOM once and joins split surrogates',
    () {
      final IncrementalEncoder enc = codec('utf-16').newEncoder();
      final List<int> out1 = enc.feed('A');
      final List<int> out2 = enc.feed('\uD83D');
      final List<int> out3 = enc.feed('\uDE00', finalChunk: true);
      final List<int> out4 = enc.close();

      expect(out2, isEmpty);
      expect(<int>[
        ...out1,
        ...out2,
        ...out3,
        ...out4,
      ], equals(encodeString('A😀', encoding: 'utf-16')));
    },
  );
}
