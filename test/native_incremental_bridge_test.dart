// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/codec/backend.dart';
import 'package:charset_codec/src/codec/resolver.dart';
import 'package:charset_codec/src/native/native_bridge.dart';
import 'package:test/test.dart';

const Map<String, String> _statefulSamples = <String, String>{
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

void main() {
  test('native hybrid incremental decoder preserves cp932 pending tail', () {
    final ResolvedCodec? resolved = resolveCodec('cp932');
    expect(resolved, isNotNull);

    if (!nativeCodecBridge.isAvailable) {
      expect(nativeCodecBridge.supportsCodec(resolved!), isFalse);
      return;
    }

    expect(activeCodecBackendName(), equals('native-hybrid'));
    expect(nativeCodecBridge.supportsCodec(resolved!), isTrue);

    final List<int> bytes = encodeString('日本語', encoding: 'cp932');
    final IncrementalDecoder decoder = codec('cp932').newDecoder();
    expect(decoder.feed(bytes.sublist(0, 1)), equals(''));
    final Object state = decoder.getState();

    final IncrementalDecoder restored = codec('cp932').newDecoder();
    restored.setState(state);
    final String out =
        restored.feed(bytes.sublist(1), finalChunk: true) + restored.close();
    expect(out, equals('日本語'));
  });

  test('native hybrid incremental decoder rejects legacy List<int> state', () {
    final ResolvedCodec? resolved = resolveCodec('cp932');
    expect(resolved, isNotNull);

    if (!nativeCodecBridge.isAvailable) {
      expect(nativeCodecBridge.supportsCodec(resolved!), isFalse);
      return;
    }

    final IncrementalDecoder decoder = codec('cp932').newDecoder();
    expect(() => decoder.setState(<int>[0x82]), throwsA(isA<ArgumentError>()));
  });

  test(
    'native hybrid incremental decoder preserves bounded iso-2022-jp state',
    () {
      final ResolvedCodec? resolved = resolveCodec('iso-2022-jp');
      expect(resolved, isNotNull);

      if (!nativeCodecBridge.isAvailable) {
        expect(nativeCodecBridge.supportsCodec(resolved!), isFalse);
        return;
      }

      expect(activeCodecBackendName(), equals('native-hybrid'));
      expect(nativeCodecBridge.supportsCodec(resolved!), isTrue);

      final List<int> bytes = encodeString('世界z', encoding: 'iso-2022-jp');
      final IncrementalDecoder decoder = codec('iso-2022-jp').newDecoder();
      final String prefix = decoder.feed(bytes.sublist(0, bytes.length - 1));
      final Object state = decoder.getState();

      final IncrementalDecoder restored = codec('iso-2022-jp').newDecoder();
      restored.setState(state);
      final String suffix =
          restored.feed(bytes.sublist(bytes.length - 1), finalChunk: true) +
          restored.close();
      expect('$prefix$suffix', equals('世界z'));
    },
  );

  test(
    'native hybrid incremental decoder streams gb18030 prefix and preserves state',
    () {
      final ResolvedCodec? resolved = resolveCodec('gb18030');
      expect(resolved, isNotNull);

      if (!nativeCodecBridge.isAvailable) {
        expect(nativeCodecBridge.supportsCodec(resolved!), isFalse);
        return;
      }

      expect(activeCodecBackendName(), equals('native-hybrid'));
      expect(nativeCodecBridge.supportsCodec(resolved!), isTrue);

      final List<int> bytes = encodeString('A𠀋B', encoding: 'gb18030');
      final IncrementalDecoder decoder = codec('gb18030').newDecoder();
      final String prefix = decoder.feed(bytes.sublist(0, 3));
      expect(prefix, equals('A'));
      final Object state = decoder.getState();

      final IncrementalDecoder restored = codec('gb18030').newDecoder();
      restored.setState(state);
      final String suffix =
          restored.feed(bytes.sublist(3), finalChunk: true) + restored.close();
      expect('$prefix$suffix', equals('A𠀋B'));
    },
  );

  test(
    'native hybrid incremental encoder streams gb18030 prefix and preserves state',
    () {
      final ResolvedCodec? resolved = resolveCodec('gb18030');
      expect(resolved, isNotNull);

      if (!nativeCodecBridge.isAvailable) {
        expect(nativeCodecBridge.supportsCodec(resolved!), isFalse);
        return;
      }

      expect(activeCodecBackendName(), equals('native-hybrid'));
      expect(nativeCodecBridge.supportsCodec(resolved!), isTrue);

      final IncrementalEncoder encoder = codec('gb18030').newEncoder();
      final List<int> prefix = encoder.feed('A');
      expect(prefix, equals(encodeString('A', encoding: 'gb18030')));
      expect(encoder.feed('\uD840'), isEmpty);
      final Object state = encoder.getState();

      final IncrementalEncoder restored = codec('gb18030').newEncoder();
      restored.setState(state);
      final List<int> out = <int>[
        ...prefix,
        ...restored.feed('\uDC0B', finalChunk: true),
        ...restored.close(),
      ];
      expect(out, equals(encodeString('A𠀋', encoding: 'gb18030')));
    },
  );

  test('native hybrid incremental encoder rejects legacy String state', () {
    final ResolvedCodec? resolved = resolveCodec('gb18030');
    expect(resolved, isNotNull);

    if (!nativeCodecBridge.isAvailable) {
      expect(nativeCodecBridge.supportsCodec(resolved!), isFalse);
      return;
    }

    final IncrementalEncoder encoder = codec('gb18030').newEncoder();
    expect(() => encoder.setState('A'), throwsA(isA<ArgumentError>()));
  });

  test('native stateful sessions stream every generated family', () {
    if (!nativeCodecBridge.isAvailable) {
      return;
    }
    for (final MapEntry<String, String> sample in _statefulSamples.entries) {
      final List<int> expectedBytes = encodeString(
        sample.value,
        encoding: sample.key,
      );
      final IncrementalDecoder decoder = codec(sample.key).newDecoder();
      final StringBuffer decoded = StringBuffer();
      bool decoderEmittedPrefix = false;
      for (int i = 0; i < expectedBytes.length; i++) {
        late final String part;
        try {
          part = decoder.feed(<int>[
            expectedBytes[i],
          ], finalChunk: i == expectedBytes.length - 1);
        } on Object catch (error) {
          fail(
            'encoding=${sample.key}, byteIndex=$i, '
            'byte=0x${expectedBytes[i].toRadixString(16)}, error=$error',
          );
        }
        decoded.write(part);
        decoderEmittedPrefix |= i < expectedBytes.length - 1 && part.isNotEmpty;
      }
      decoded.write(decoder.close());
      expect(decoded.toString(), sample.value, reason: sample.key);
      expect(decoderEmittedPrefix, isTrue, reason: sample.key);

      final IncrementalEncoder encoder = codec(sample.key).newEncoder();
      final List<int> actualBytes = <int>[];
      bool encoderEmittedPrefix = false;
      for (int i = 0; i < sample.value.length; i++) {
        final List<int> part = encoder.feed(
          sample.value.substring(i, i + 1),
          finalChunk: i == sample.value.length - 1,
        );
        actualBytes.addAll(part);
        encoderEmittedPrefix |= i < sample.value.length - 1 && part.isNotEmpty;
      }
      actualBytes.addAll(encoder.close());
      expect(actualBytes, expectedBytes, reason: sample.key);
      expect(encoderEmittedPrefix, isTrue, reason: sample.key);
    }
  });

  test('native stateful session restore preserves every family', () {
    if (!nativeCodecBridge.isAvailable) {
      return;
    }
    for (final MapEntry<String, String> sample in _statefulSamples.entries) {
      final List<int> bytes = encodeString(sample.value, encoding: sample.key);
      final int byteCut = bytes.length ~/ 2;
      final IncrementalDecoder sourceDecoder = codec(sample.key).newDecoder();
      final String decodedPrefix = sourceDecoder.feed(
        bytes.sublist(0, byteCut),
      );
      final Object decoderState = sourceDecoder.getState();
      final IncrementalDecoder restoredDecoder = codec(sample.key).newDecoder();
      restoredDecoder.setState(decoderState);
      final String decodedSuffix =
          restoredDecoder.feed(bytes.sublist(byteCut), finalChunk: true) +
          restoredDecoder.close();
      expect('$decodedPrefix$decodedSuffix', sample.value, reason: sample.key);

      final int textCut = sample.value.length ~/ 2;
      final IncrementalEncoder sourceEncoder = codec(sample.key).newEncoder();
      final List<int> encodedPrefix = sourceEncoder.feed(
        sample.value.substring(0, textCut),
      );
      final Object encoderState = sourceEncoder.getState();
      final IncrementalEncoder restoredEncoder = codec(sample.key).newEncoder();
      restoredEncoder.setState(encoderState);
      final List<int> encodedSuffix = <int>[
        ...restoredEncoder.feed(
          sample.value.substring(textCut),
          finalChunk: true,
        ),
        ...restoredEncoder.close(),
      ];
      expect(
        <int>[...encodedPrefix, ...encodedSuffix],
        bytes,
        reason: sample.key,
      );
    }
  });

  test('native stateful session blobs stay bounded during long streams', () {
    if (!nativeCodecBridge.isAvailable) {
      return;
    }
    for (final MapEntry<String, String> sample in _statefulSamples.entries) {
      final ResolvedCodec resolved = resolveCodec(sample.key)!;
      final int decoderHandle = nativeCodecBridge
          .createIncrementalDecoderSession(
            resolved,
            errors: CodecErrorMode.strict,
          );
      final int encoderHandle = nativeCodecBridge
          .createIncrementalEncoderSession(
            resolved,
            errors: CodecErrorMode.strict,
          );
      try {
        final List<int> encodedUnit = encodeString(
          sample.value,
          encoding: sample.key,
        );
        for (int i = 0; i < 2000; i++) {
          nativeCodecBridge.feedDecoderSession(
            decoderHandle,
            resolved,
            encodedUnit,
            finalChunk: false,
          );
          nativeCodecBridge.feedEncoderSession(
            encoderHandle,
            resolved,
            sample.value,
            finalChunk: false,
          );
        }
        expect(
          nativeCodecBridge
              .getIncrementalSessionState(decoderHandle, resolved)
              .length,
          lessThanOrEqualTo(41),
          reason: 'decoder ${sample.key}',
        );
        expect(
          nativeCodecBridge
              .getIncrementalSessionState(encoderHandle, resolved)
              .length,
          lessThanOrEqualTo(35),
          reason: 'encoder ${sample.key}',
        );
      } finally {
        nativeCodecBridge.destroyIncrementalSession(decoderHandle);
        nativeCodecBridge.destroyIncrementalSession(encoderHandle);
      }
    }
  });
}
