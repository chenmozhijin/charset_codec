// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

import 'support/fixture_loader.dart';

int? _mapLimitFromEnv() {
  final String profile =
      Platform.environment['CHARSET_CODEC_MAP_CASE_PROFILE']
          ?.trim()
          .toLowerCase() ??
      'full';
  if (profile == 'sampled' || profile == 'smoke') {
    return 300;
  }
  return null;
}

void main() {
  group('codec map conformance', tags: <String>['full', 'fixtures'], () {
    late final List<CodecMapCase> mapCases;

    setUpAll(() {
      final String? reason = hasFixturesOrSkipReason();
      expect(reason, isNull, reason: reason);
      final int? limit = _mapLimitFromEnv();
      mapCases = loadCodecMapCases(perEncodingLimit: limit);
      // The full preset must run the complete fixture; only explicit sampled or
      // smoke modes may use a subset.
      // ignore: avoid_print
      print(
        "codec map conformance cases: ${mapCases.length} limit=${limit ?? 'all'}",
      );
      expect(mapCases, isNotEmpty);
    });

    test('decode map cases match expected unicode', () {
      for (final CodecMapCase c in mapCases) {
        expect(
          decodeBytes(hexToBytes(c.bytesHex), encoding: c.encoding),
          equals(c.text),
          reason:
              'encoding=${c.encoding} source=${c.source} bytes=${c.bytesHex}',
        );
      }
    });

    test('roundtrip map cases encode to original bytes', () {
      for (final CodecMapCase c in mapCases.where(
        (CodecMapCase e) => e.roundtrip,
      )) {
        expect(
          encodeString(c.text, encoding: c.encoding),
          equals(hexToBytes(c.bytesHex)),
          reason: 'encoding=${c.encoding} source=${c.source} text=${c.text}',
        );
      }
    });
  });
}
