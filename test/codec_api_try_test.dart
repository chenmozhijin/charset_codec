// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:test/test.dart';

void main() {
  group('api helper behavior', () {
    test('tryDecodeBytes returns null for unknown codec and decode errors', () {
      expect(
        tryDecodeBytes(const <int>[0x41], encoding: 'definitely-unknown-codec'),
        isNull,
      );
      expect(tryDecodeBytes(const <int>[0xFF], encoding: 'utf-8'), isNull);
    });

    test(
      'tryEncodeString returns null for unknown codec and encode errors',
      () {
        expect(
          tryEncodeString('A', encoding: 'definitely-unknown-codec'),
          isNull,
        );
        expect(tryEncodeString('中', encoding: 'ascii'), isNull);
      },
    );

    test(
      'isValidDataForEncoding rejects incomplete multibyte trailing bytes',
      () {
        expect(isValidDataForEncoding(const <int>[0x81], 'cp932'), isFalse);
        expect(isValidDataForEncoding(const <int>[0xA4], 'euc-jp'), isFalse);
      },
    );

    test('generated multibyte registry contains no pending codecs', () {
      expect(generatedMultibytePendingCodecs, isEmpty);
    });
  });
}
