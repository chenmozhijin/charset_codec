// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  group('async codec api', () {
    test('decodeBytesAsync matches sync decode', () async {
      final String sync = decodeBytes(const <int>[
        0xE4,
        0xB8,
        0xAD,
      ], encoding: 'utf-8');
      final String async = await decodeBytesAsync(const <int>[
        0xE4,
        0xB8,
        0xAD,
      ], encoding: 'utf-8');
      expect(async, equals(sync));
    });

    test('encodeStringAsync matches sync encode', () async {
      final List<int> sync = encodeString('A中B', encoding: 'utf-8');
      final List<int> async = await encodeStringAsync('A中B', encoding: 'utf-8');
      expect(async, equals(sync));
    });

    test('isValidDataForEncodingAsync matches sync validation', () async {
      final bool sync = isValidDataForEncoding(const <int>[
        0x41,
        0x42,
        0x43,
      ], 'ascii');
      final bool async = await isValidDataForEncodingAsync(const <int>[
        0x41,
        0x42,
        0x43,
      ], 'ascii');
      expect(async, equals(sync));
    });

    test(
      'isValidDataForEncodingAsync returns false for unknown encoding',
      () async {
        expect(
          await isValidDataForEncodingAsync(const <int>[
            0x41,
          ], 'x-unknown-encoding'),
          isFalse,
        );
      },
    );
  });
}
