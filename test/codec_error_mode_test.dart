// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  test('decode error modes on ascii invalid byte', () {
    const List<int> bytes = <int>[0x41, 0x80, 0x42];

    expect(
      decodeBytes(bytes, encoding: 'ascii', errors: CodecErrorMode.ignore),
      equals('AB'),
    );
    expect(
      decodeBytes(bytes, encoding: 'ascii', errors: CodecErrorMode.replace),
      equals('A\uFFFDB'),
    );
    expect(
      decodeBytes(
        bytes,
        encoding: 'ascii',
        errors: CodecErrorMode.backslashReplace,
      ),
      equals(r'A\x80B'),
    );
    expect(
      decodeBytes(
        bytes,
        encoding: 'ascii',
        errors: CodecErrorMode.surrogateEscape,
      ),
      equals('A\uDC80B'),
    );
    expect(
      () =>
          decodeBytes(bytes, encoding: 'ascii', errors: CodecErrorMode.strict),
      throwsA(isA<CodecException>()),
    );
  });

  test('encode error modes on ascii unencodable scalar', () {
    const String text = 'A中B';

    expect(
      encodeString(text, encoding: 'ascii', errors: CodecErrorMode.ignore),
      equals('AB'.codeUnits),
    );
    expect(
      encodeString(text, encoding: 'ascii', errors: CodecErrorMode.replace),
      equals('A?B'.codeUnits),
    );
    expect(
      encodeString(
        text,
        encoding: 'ascii',
        errors: CodecErrorMode.backslashReplace,
      ),
      equals(r'A\u4e2dB'.codeUnits),
    );
    expect(
      encodeString(
        text,
        encoding: 'ascii',
        errors: CodecErrorMode.xmlCharRefReplace,
      ),
      equals('A&#20013;B'.codeUnits),
    );
    expect(
      encodeString(text, encoding: 'ascii', errors: CodecErrorMode.nameReplace),
      equals(r'A\N{U+4E2D}B'.codeUnits),
    );
    expect(
      () =>
          encodeString(text, encoding: 'ascii', errors: CodecErrorMode.strict),
      throwsA(isA<CodecException>()),
    );
  });
}
