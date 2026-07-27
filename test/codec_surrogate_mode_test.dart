// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  group('surrogate mode parity', () {
    test('ascii surrogateEscape roundtrips bad bytes', () {
      const List<int> raw = <int>[0x66, 0x6F, 0x6F, 0x80, 0x62, 0x61, 0x72];
      final String decoded = decodeBytes(
        raw,
        encoding: 'ascii',
        errors: CodecErrorMode.surrogateEscape,
      );
      expect(decoded, equals('foo\uDC80bar'));
      expect(
        encodeString(
          decoded,
          encoding: 'ascii',
          errors: CodecErrorMode.surrogateEscape,
        ),
        equals(raw),
      );
    });

    test('utf-8 surrogateEscape roundtrips malformed bytes', () {
      const List<int> malformedUtf8 = <int>[0xED, 0xB0, 0x80];
      final String decoded = decodeBytes(
        malformedUtf8,
        encoding: 'utf-8',
        errors: CodecErrorMode.surrogateEscape,
      );
      expect(decoded, equals('\uDCED\uDCB0\uDC80'));
      expect(
        encodeString(
          decoded,
          encoding: 'utf-8',
          errors: CodecErrorMode.surrogateEscape,
        ),
        equals(malformedUtf8),
      );
    });

    test('utf-8 surrogatePass decodes and encodes surrogate payloads', () {
      expect(
        decodeBytes(
          const <int>[0xED, 0xB0, 0x80],
          encoding: 'utf-8',
          errors: CodecErrorMode.surrogatePass,
        ),
        equals('\uDC00'),
      );
      expect(
        encodeString(
          '\uDC00',
          encoding: 'utf-8',
          errors: CodecErrorMode.surrogatePass,
        ),
        equals(const <int>[0xED, 0xB0, 0x80]),
      );
    });

    test(
      'charmap surrogateEscape supports reversible unmapped byte handling',
      () {
        const List<int> raw = <int>[0x66, 0x6F, 0x6F, 0xA5, 0x62, 0x61, 0x72];
        final String decoded = decodeBytes(
          raw,
          encoding: 'iso-8859-3',
          errors: CodecErrorMode.surrogateEscape,
        );
        expect(decoded, equals('foo\uDCA5bar'));
        expect(
          encodeString(
            decoded,
            encoding: 'iso-8859-3',
            errors: CodecErrorMode.surrogateEscape,
          ),
          equals(raw),
        );
      },
    );

    test('iso-8859-1 surrogateEscape encodes DCxx surrogates directly', () {
      expect(
        encodeString(
          '\uDCE4\uDCEB\uDCEF\uDCF6\uDCFC',
          encoding: 'iso-8859-1',
          errors: CodecErrorMode.surrogateEscape,
        ),
        equals(const <int>[0xE4, 0xEB, 0xEF, 0xF6, 0xFC]),
      );
    });
  });
}
