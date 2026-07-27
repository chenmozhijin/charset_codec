// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/codec/impl.dart';
import 'package:charset_codec/src/codec/mbcs.dart';
import 'package:charset_codec/src/codec/resolver.dart';
import 'package:charset_codec/src/codec/utf.dart';
import 'package:test/test.dart';

const Map<String, String> _samples = <String, String>{
  'gb18030': 'A𠀋B',
  'hz-gb-2312': '中文A',
  'iso-2022-kr': '한글A',
  'iso-2022-jp': '日本語A',
  'iso2022-jp-1': '日本語A',
  'iso2022-jp-2': '日本語A',
  'iso2022-jp-3': '日本語A',
  'iso2022-jp-2004': '日本語A',
  'iso2022-jp-ext': '日本語A',
};

CharsetCodec _dartCodec(String encoding) {
  final ResolvedCodec? resolved = resolveCodec(encoding);
  if (resolved == null) {
    throw StateError('missing codec: $encoding');
  }
  return CharsetCodecImpl(resolved);
}

void main() {
  test('Dart stateful decoders stream every generated family', () {
    for (final MapEntry<String, String> sample in _samples.entries) {
      final CharsetCodec implementation = _dartCodec(sample.key);
      final List<int> bytes = implementation.encode(sample.value);
      final IncrementalDecoder decoder = implementation.newDecoder();
      final StringBuffer decoded = StringBuffer();
      bool emittedBeforeFinal = false;

      for (int i = 0; i < bytes.length; i++) {
        final String part = decoder.feed(<int>[
          bytes[i],
        ], finalChunk: i == bytes.length - 1);
        decoded.write(part);
        emittedBeforeFinal |= i < bytes.length - 1 && part.isNotEmpty;
        if (i < bytes.length - 1) {
          final StatefulMultibyteDecoderState state =
              decoder.getState() as StatefulMultibyteDecoderState;
          expect(
            state.pendingBytes.length,
            lessThanOrEqualTo(5),
            reason: 'encoding=${sample.key}',
          );
        }
      }
      decoded.write(decoder.close());
      expect(
        decoded.toString(),
        sample.value,
        reason: 'encoding=${sample.key}',
      );
      expect(emittedBeforeFinal, isTrue, reason: 'encoding=${sample.key}');
    }
  });

  test('Dart stateful encoders preserve one-shot bytes across chunks', () {
    for (final MapEntry<String, String> sample in _samples.entries) {
      final CharsetCodec implementation = _dartCodec(sample.key);
      final List<int> expected = implementation.encode(sample.value);
      final IncrementalEncoder encoder = implementation.newEncoder();
      final List<int> actual = <int>[];
      bool emittedBeforeFinal = false;

      for (int i = 0; i < sample.value.length; i++) {
        final List<int> part = encoder.feed(
          sample.value.substring(i, i + 1),
          finalChunk: i == sample.value.length - 1,
        );
        actual.addAll(part);
        emittedBeforeFinal |= i < sample.value.length - 1 && part.isNotEmpty;
        if (i < sample.value.length - 1) {
          final StatefulMultibyteEncoderState state =
              encoder.getState() as StatefulMultibyteEncoderState;
          expect(
            state.pendingScalar.length,
            lessThanOrEqualTo(1),
            reason: 'encoding=${sample.key}',
          );
        }
      }
      actual.addAll(encoder.close());
      expect(actual, expected, reason: 'encoding=${sample.key}');
      expect(emittedBeforeFinal, isTrue, reason: 'encoding=${sample.key}');
    }
  });

  test('Dart stateful decoder restore keeps bounded control state', () {
    for (final MapEntry<String, String> sample in _samples.entries) {
      final CharsetCodec implementation = _dartCodec(sample.key);
      final List<int> bytes = implementation.encode(sample.value);
      final int cut = bytes.length ~/ 2;
      final IncrementalDecoder source = implementation.newDecoder();
      final String prefix = source.feed(bytes.sublist(0, cut));
      final Object state = source.getState();

      final IncrementalDecoder restored = implementation.newDecoder();
      restored.setState(state);
      final String suffix =
          restored.feed(bytes.sublist(cut), finalChunk: true) +
          restored.close();
      expect('$prefix$suffix', sample.value, reason: 'encoding=${sample.key}');
    }
  });

  test('Dart stateful decoder error modes match one-shot results', () {
    const Map<String, List<int>> invalid = <String, List<int>>{
      'gb18030': <int>[0x81, 0x30, 0x81],
      'hz-gb-2312': <int>[0x7E, 0x78, 0x41],
      'iso-2022-kr': <int>[0x1B, 0x58, 0x41, 0x42],
      'iso-2022-jp': <int>[0x1B, 0x24, 0x5A, 0x41],
    };
    const List<CodecErrorMode> modes = <CodecErrorMode>[
      CodecErrorMode.ignore,
      CodecErrorMode.replace,
      CodecErrorMode.backslashReplace,
      CodecErrorMode.xmlCharRefReplace,
      CodecErrorMode.nameReplace,
      CodecErrorMode.surrogateEscape,
      CodecErrorMode.surrogatePass,
    ];
    for (final MapEntry<String, List<int>> sample in invalid.entries) {
      final CharsetCodec implementation = _dartCodec(sample.key);
      for (final CodecErrorMode mode in modes) {
        final String expected = implementation.decode(
          sample.value,
          errors: mode,
        );
        final IncrementalDecoder decoder = implementation.newDecoder(
          errors: mode,
        );
        final String actual =
            decoder.feed(sample.value.sublist(0, 1)) +
            decoder.feed(sample.value.sublist(1), finalChunk: true) +
            decoder.close();
        expect(actual, expected, reason: '${sample.key} / ${mode.name}');
      }
    }
  });

  test('Dart stateful encoder error modes match one-shot results', () {
    const List<CodecErrorMode> modes = <CodecErrorMode>[
      CodecErrorMode.ignore,
      CodecErrorMode.replace,
      CodecErrorMode.backslashReplace,
      CodecErrorMode.xmlCharRefReplace,
      CodecErrorMode.nameReplace,
      CodecErrorMode.surrogatePass,
    ];
    for (final String encoding in const <String>[
      'hz-gb-2312',
      'iso-2022-kr',
      'iso-2022-jp',
    ]) {
      final CharsetCodec implementation = _dartCodec(encoding);
      for (final CodecErrorMode mode in modes) {
        const String text = 'A🙂B';
        final List<int> expected = implementation.encode(text, errors: mode);
        final IncrementalEncoder encoder = implementation.newEncoder(
          errors: mode,
        );
        final List<int> actual = <int>[
          ...encoder.feed(text.substring(0, 2)),
          ...encoder.feed(text.substring(2), finalChunk: true),
          ...encoder.close(),
        ];
        expect(actual, expected, reason: '$encoding / ${mode.name}');
      }
    }
  });

  test('Dart UTF-7 long streams retain only bit and surrogate state', () {
    final CharsetCodec implementation = _dartCodec('utf-7');
    final String text = List<String>.filled(2000, 'A≢Α.').join();
    final List<int> expected = implementation.encode(text);

    final IncrementalDecoder decoder = implementation.newDecoder();
    final StringBuffer decoded = StringBuffer();
    for (int i = 0; i < expected.length; i++) {
      decoded.write(
        decoder.feed(<int>[expected[i]], finalChunk: i == expected.length - 1),
      );
      if (i < expected.length - 1) {
        final UtfIncrementalDecoderState state =
            decoder.getState() as UtfIncrementalDecoderState;
        expect(state.pendingBytes, isEmpty);
        expect(state.utf7Base64Bits, lessThan(16));
      }
    }
    decoded.write(decoder.close());
    expect(decoded.toString(), text);

    final IncrementalEncoder encoder = implementation.newEncoder();
    final List<int> encoded = <int>[];
    for (int i = 0; i < text.length; i++) {
      encoded.addAll(
        encoder.feed(
          text.substring(i, i + 1),
          finalChunk: i == text.length - 1,
        ),
      );
      if (i < text.length - 1) {
        final UtfIncrementalEncoderState state =
            encoder.getState() as UtfIncrementalEncoderState;
        expect(state.pendingScalar, isEmpty);
        expect(state.utf7Base64Bits, lessThan(6));
      }
    }
    encoded.addAll(encoder.close());
    expect(encoded, expected);
  });

  test('Dart UTF-7 backslash errors do not replay emitted history', () {
    final IncrementalDecoder decoder = _dartCodec(
      'utf-7',
    ).newDecoder(errors: CodecErrorMode.backslashReplace);
    expect(decoder.feed(const <int>[0x2B]), isEmpty);
    expect(decoder.feed(const <int>[0x3F], finalChunk: true), equals(r'\x3f'));
    expect(decoder.close(), isEmpty);
  });
}
