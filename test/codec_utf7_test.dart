// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  test('utf-7 encodes and decodes representative samples', () {
    void check(String text, String encodedAscii) {
      final List<int> encoded = encodeString(text, encoding: 'utf-7');
      expect(encoded, equals(encodedAscii.codeUnits));
      expect(
        decodeBytes(encodedAscii.codeUnits, encoding: 'utf-7'),
        equals(text),
      );
    }

    check('A\u2262\u0391.', 'A+ImIDkQ.');
    check('Hi Mom -\u263A-!', 'Hi Mom -+Jjo--!');
    check('\u65E5\u672C\u8A9E', '+ZeVnLIqe-');
    check('Item 3 is \u00A31.', 'Item 3 is +AKM-1.');
    check('+', '+-');
    check('+-', '+--');
    check('+?', '+-?');
    check(r'\?', '+AFw?');
    check('++--', '+-+---');
    check(String.fromCharCode(0xABCDE), '+2m/c3g-');
    check('/', '/');
  });

  test('utf-7 handles non-bmp and lone surrogate code units', () {
    final String loneHigh = String.fromCharCode(0xD801);
    final String loneLow = String.fromCharCode(0xDC01);
    final String nonBmp = String.fromCharCode(0x104A0);
    final String cpAbcde = String.fromCharCode(0xABCDE);

    expect(
      encodeString(loneHigh, encoding: 'utf-7'),
      equals('+2AE-'.codeUnits),
    );
    expect(
      encodeString('${loneHigh}x', encoding: 'utf-7'),
      equals('+2AE-x'.codeUnits),
    );
    expect(encodeString(loneLow, encoding: 'utf-7'), equals('+3AE-'.codeUnits));
    expect(
      encodeString('${loneLow}x', encoding: 'utf-7'),
      equals('+3AE-x'.codeUnits),
    );

    expect(decodeBytes('+2AE-'.codeUnits, encoding: 'utf-7'), equals(loneHigh));
    expect(
      decodeBytes('+2AE-x'.codeUnits, encoding: 'utf-7'),
      equals('${loneHigh}x'),
    );
    expect(decodeBytes('+3AE-'.codeUnits, encoding: 'utf-7'), equals(loneLow));
    expect(
      decodeBytes('+3AE-x'.codeUnits, encoding: 'utf-7'),
      equals('${loneLow}x'),
    );

    expect(
      encodeString(nonBmp, encoding: 'utf-7'),
      equals('+2AHcoA-'.codeUnits),
    );
    expect(
      decodeBytes('+2AHcoA-'.codeUnits, encoding: 'utf-7'),
      equals(nonBmp),
    );
    expect(decodeBytes('+2AHcoA'.codeUnits, encoding: 'utf-7'), equals(nonBmp));

    expect(
      encodeString('$loneHigh$cpAbcde', encoding: 'utf-7'),
      equals('+2AHab9ze-'.codeUnits),
    );
    expect(
      decodeBytes('+2AHab9ze-'.codeUnits, encoding: 'utf-7'),
      equals('$loneHigh$cpAbcde'),
    );
  });

  test('utf-7 decode supports key error modes on ill-formed sequence', () {
    final List<int> illFormed = 'a+@b'.codeUnits;

    expect(
      () => decodeBytes(illFormed, encoding: 'utf-7'),
      throwsA(isA<CodecException>()),
    );
    expect(
      decodeBytes(illFormed, encoding: 'utf-7', errors: CodecErrorMode.ignore),
      equals('ab'),
    );
    expect(
      decodeBytes(illFormed, encoding: 'utf-7', errors: CodecErrorMode.replace),
      equals('a\uFFFDb'),
    );
    expect(
      decodeBytes(
        illFormed,
        encoding: 'utf-7',
        errors: CodecErrorMode.backslashReplace,
      ),
      equals(r'a\x2b\x40b'),
    );
    expect(
      () => decodeBytes(
        illFormed,
        encoding: 'utf-7',
        errors: CodecErrorMode.surrogateEscape,
      ),
      throwsA(isA<CodecException>()),
    );
  });

  test('utf-7 surrogateEscape maps non-ascii decode errors to DCxx', () {
    const List<int> data = <int>[0x61, 0xFF, 0x62];

    expect(
      decodeBytes(
        data,
        encoding: 'utf-7',
        errors: CodecErrorMode.surrogateEscape,
      ),
      equals('a\uDCFFb'),
    );
    expect(
      decodeBytes(
        data,
        encoding: 'utf-7',
        errors: CodecErrorMode.backslashReplace,
      ),
      equals(r'a\xffb'),
    );
  });

  test('utf-7 handles unterminated shift sequences like cpython', () {
    final List<int> broken = 'a+IK'.codeUnits;

    expect(
      () => decodeBytes(broken, encoding: 'utf-7'),
      throwsA(isA<CodecException>()),
    );
    expect(
      decodeBytes(broken, encoding: 'utf-7', errors: CodecErrorMode.ignore),
      equals('a'),
    );
    expect(
      decodeBytes(broken, encoding: 'utf-7', errors: CodecErrorMode.replace),
      equals('a\uFFFD'),
    );
    expect(
      decodeBytes(
        broken,
        encoding: 'utf-7',
        errors: CodecErrorMode.backslashReplace,
      ),
      equals(r'a\x2b\x49\x4b'),
    );
  });
}
