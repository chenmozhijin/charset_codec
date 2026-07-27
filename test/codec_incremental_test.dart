// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:test/test.dart';

String _pickCodec() {
  if (generatedMultibyteDecodeTableCodecs.contains('cp932')) {
    return 'cp932';
  }
  return generatedMultibyteDecodeTableCodecs.first;
}

void main() {
  test('incremental decoder parity with one-shot decode', () {
    final String name = _pickCodec();
    final List<int> bytes = generatedMbcsSampleMultibyteBytesByCodec[name]!;
    final String oneShot = decodeBytes(bytes, encoding: name);

    final IncrementalDecoder decoder = codec(name).newDecoder();
    final String out1 = decoder.feed(<int>[bytes.first]);
    final String out2 = decoder.feed(bytes.sublist(1), finalChunk: true);
    final String out3 = decoder.close();
    expect('$out1$out2$out3', equals(oneShot));
  });

  test('incremental decoder state restore works', () {
    final String name = _pickCodec();
    final List<int> bytes = generatedMbcsSampleMultibyteBytesByCodec[name]!;
    final String oneShot = decodeBytes(bytes, encoding: name);

    final IncrementalDecoder source = codec(name).newDecoder();
    source.feed(<int>[bytes.first]);
    final Object state = source.getState();

    final IncrementalDecoder restored = codec(name).newDecoder();
    restored.setState(state);
    final String out =
        restored.feed(bytes.sublist(1), finalChunk: true) + restored.close();
    expect(out, equals(oneShot));
  });

  test('incremental encoder parity with one-shot encode', () {
    final String name = _pickCodec();
    final int scalarCp = generatedMbcsSampleMultibyteScalarByCodec[name]!;
    final String scalar = String.fromCharCode(scalarCp);
    final String text = '$scalar$scalar';
    final List<int> oneShot = encodeString(text, encoding: name);

    final IncrementalEncoder encoder = codec(name).newEncoder();
    final List<int> out1 = encoder.feed(scalar);
    final List<int> out2 = encoder.feed(scalar, finalChunk: true);
    final List<int> out3 = encoder.close();
    expect(<int>[...out1, ...out2, ...out3], equals(oneShot));
  });

  test('incremental encoder state restore works', () {
    final String name = _pickCodec();
    final int scalarCp = generatedMbcsSampleMultibyteScalarByCodec[name]!;
    final String scalar = String.fromCharCode(scalarCp);
    final String text = '$scalar$scalar';
    final List<int> oneShot = encodeString(text, encoding: name);

    final IncrementalEncoder source = codec(name).newEncoder();
    final List<int> prefix = source.feed(scalar);
    final Object state = source.getState();

    final IncrementalEncoder restored = codec(name).newEncoder();
    restored.setState(state);
    final List<int> out = <int>[
      ...prefix,
      ...restored.feed(scalar, finalChunk: true),
      ...restored.close(),
    ];
    expect(out, equals(oneShot));
  });

  test('incremental encoder emits table-backed prefix before final chunk', () {
    final IncrementalEncoder encoder = codec('cp932').newEncoder();
    final List<int> prefix = encoder.feed('日本');
    final List<int> suffix = <int>[
      ...encoder.feed('語', finalChunk: true),
      ...encoder.close(),
    ];

    expect(prefix, isNotEmpty);
    expect(<int>[
      ...prefix,
      ...suffix,
    ], equals(encodeString('日本語', encoding: 'cp932')));
  });
}
