// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  group('utf family parity', () {
    test('utf-8-sig strips only the first BOM on decode', () {
      expect(
        decodeBytes(const <int>[
          0xEF,
          0xBB,
          0xBF,
          0x41,
          0x42,
          0x43,
        ], encoding: 'utf-8-sig'),
        equals('ABC'),
      );
      expect(
        decodeBytes(const <int>[
          0xEF,
          0xBB,
          0xBF,
          0xEF,
          0xBB,
          0xBF,
          0x41,
        ], encoding: 'utf-8-sig'),
        equals('\uFEFFA'),
      );
    });

    test('utf-8-sig always prefixes BOM on encode', () {
      expect(
        encodeString('ABC', encoding: 'utf-8-sig'),
        equals(const <int>[0xEF, 0xBB, 0xBF, 0x41, 0x42, 0x43]),
      );
    });

    test('utf-16 bad BOM bytes raise decode errors in strict mode', () {
      expect(
        () => decodeBytes(const <int>[0xFF, 0xFF], encoding: 'utf-16'),
        throwsA(isA<CodecException>()),
      );
      expect(
        () => decodeBytes(const <int>[
          0xFF,
          0xFF,
          0xFF,
          0xFF,
        ], encoding: 'utf-16'),
        throwsA(isA<CodecException>()),
      );
    });

    test('utf-16 odd byte payload handling matches CPython error modes', () {
      expect(
        () => decodeBytes(const <int>[0x01], encoding: 'utf-16'),
        throwsA(isA<CodecException>()),
      );
      expect(
        decodeBytes(
          const <int>[0x01],
          encoding: 'utf-16',
          errors: CodecErrorMode.replace,
        ),
        equals('\uFFFD'),
      );
      expect(
        decodeBytes(
          const <int>[0x01],
          encoding: 'utf-16',
          errors: CodecErrorMode.ignore,
        ),
        equals(''),
      );
    });

    test(
      'utf-16 lone surrogates honor strict/replace/ignore/surrogatePass',
      () {
        const List<int> loneHighSurrogateLe = <int>[0xFF, 0xFE, 0x00, 0xD8];

        expect(
          () => decodeBytes(loneHighSurrogateLe, encoding: 'utf-16'),
          throwsA(isA<CodecException>()),
        );
        expect(
          decodeBytes(
            loneHighSurrogateLe,
            encoding: 'utf-16',
            errors: CodecErrorMode.replace,
          ),
          equals('\uFFFD'),
        );
        expect(
          decodeBytes(
            loneHighSurrogateLe,
            encoding: 'utf-16',
            errors: CodecErrorMode.ignore,
          ),
          equals(''),
        );
        expect(
          decodeBytes(
            loneHighSurrogateLe,
            encoding: 'utf-16',
            errors: CodecErrorMode.surrogatePass,
          ),
          equals('\uD800'),
        );
      },
    );

    test('utf-16 encode lone surrogate requires surrogatePass', () {
      const String loneHighSurrogate = '\uD800';

      expect(
        () => encodeString(loneHighSurrogate, encoding: 'utf-16'),
        throwsA(isA<CodecException>()),
      );
      expect(
        encodeString(
          loneHighSurrogate,
          encoding: 'utf-16',
          errors: CodecErrorMode.surrogatePass,
        ),
        equals(const <int>[0xFF, 0xFE, 0x00, 0xD8]),
      );
    });

    test(
      'utf-32 lone surrogates honor strict/replace/ignore/surrogatePass',
      () {
        const List<int> loneLowSurrogateLe = <int>[
          0xFF,
          0xFE,
          0x00,
          0x00,
          0x00,
          0xDC,
          0x00,
          0x00,
        ];

        expect(
          () => decodeBytes(loneLowSurrogateLe, encoding: 'utf-32'),
          throwsA(isA<CodecException>()),
        );
        expect(
          decodeBytes(
            loneLowSurrogateLe,
            encoding: 'utf-32',
            errors: CodecErrorMode.replace,
          ),
          equals('\uFFFD'),
        );
        expect(
          decodeBytes(
            loneLowSurrogateLe,
            encoding: 'utf-32',
            errors: CodecErrorMode.ignore,
          ),
          equals(''),
        );
        expect(
          decodeBytes(
            loneLowSurrogateLe,
            encoding: 'utf-32',
            errors: CodecErrorMode.surrogatePass,
          ),
          equals('\uDC00'),
        );
      },
    );

    test('utf-32 encode lone surrogate requires surrogatePass', () {
      const String loneLowSurrogate = '\uDC00';

      expect(
        () => encodeString(loneLowSurrogate, encoding: 'utf-32'),
        throwsA(isA<CodecException>()),
      );
      expect(
        encodeString(
          loneLowSurrogate,
          encoding: 'utf-32',
          errors: CodecErrorMode.surrogatePass,
        ),
        equals(const <int>[0xFF, 0xFE, 0x00, 0x00, 0x00, 0xDC, 0x00, 0x00]),
      );
    });

    test('utf-8 keeps real U+FFFD while handling trailing invalid byte', () {
      const List<int> data = <int>[0xEF, 0xBF, 0xBD, 0x80];

      expect(
        () => decodeBytes(data, encoding: 'utf-8'),
        throwsA(isA<CodecException>()),
      );
      expect(
        decodeBytes(data, encoding: 'utf-8', errors: CodecErrorMode.ignore),
        equals('\uFFFD'),
      );
      expect(
        decodeBytes(
          data,
          encoding: 'utf-8',
          errors: CodecErrorMode.backslashReplace,
        ),
        equals('\uFFFD\\x80'),
      );
      expect(
        decodeBytes(
          data,
          encoding: 'utf-8',
          errors: CodecErrorMode.surrogateEscape,
        ),
        equals('\uFFFD\uDC80'),
      );
    });
  });
}
