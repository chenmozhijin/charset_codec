// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

typedef _DecodeExpectation = ({
  String encoding,
  List<int> bytes,
  String? replace,
  String? ignore,
  bool strictError,
});

List<int> _asciiBytes(String text) => ascii.encode(text);

void main() {
  test('representative CJK invalid byte sequences follow CPython modes', () {
    final List<_DecodeExpectation> cases = <_DecodeExpectation>[
      (
        encoding: 'gb2312',
        bytes: <int>[..._asciiBytes('abc'), 0x81, 0x81, 0xC1, 0xC4],
        replace: 'abc\uFFFD\uFFFD\u804A',
        ignore: 'abc\u804A',
        strictError: true,
      ),
      (
        encoding: 'gbk',
        bytes: <int>[..._asciiBytes('abc'), 0x80, 0x80, 0xC1, 0xC4],
        replace: 'abc\uFFFD\uFFFD\u804A',
        ignore: 'abc\u804A',
        strictError: true,
      ),
      (
        encoding: 'gb18030',
        bytes: <int>[..._asciiBytes('abc'), 0x84, 0x39, 0x84, 0x39, 0xC1, 0xC4],
        replace: 'abc\uFFFD9\uFFFD9\u804A',
        ignore: 'abc99\u804A',
        strictError: true,
      ),
      (
        encoding: 'cp932',
        bytes: <int>[..._asciiBytes('abc'), 0x81, 0x00, 0x82, 0x84],
        replace: 'abc\uFFFD\u0000\uFF44',
        ignore: 'abc\u0000\uFF44',
        strictError: true,
      ),
      (
        encoding: 'big5',
        bytes: <int>[..._asciiBytes('abc'), 0x80, 0x80, 0xC1, 0xC4],
        replace: 'abc\uFFFD\uFFFD\u8B10',
        ignore: 'abc\u8B10',
        strictError: true,
      ),
      (
        encoding: 'euc-jp',
        bytes: <int>[..._asciiBytes('abc'), 0x80, 0x80, 0xC1, 0xC4],
        replace: 'abc\uFFFD\uFFFD\u7956',
        ignore: 'abc\u7956',
        strictError: true,
      ),
      (
        encoding: 'shift_jis',
        bytes: <int>[..._asciiBytes('abc'), 0x80, 0x80, 0x82, 0x84],
        replace: 'abc\uFFFD\uFFFD\uFF44',
        ignore: 'abc\uFF44',
        strictError: true,
      ),
      (
        encoding: 'iso-2022-jp',
        bytes: <int>[..._asciiBytes('ab'), 0xFF, ..._asciiBytes('cd')],
        replace: 'ab\uFFFDcd',
        ignore: 'abcd',
        strictError: true,
      ),
      (
        encoding: 'iso-2022-jp',
        bytes: <int>[..._asciiBytes('ab'), 0x1B, ..._asciiBytes('def')],
        replace: 'ab\u001Bdef',
        ignore: 'ab\u001Bdef',
        strictError: false,
      ),
      (
        encoding: 'iso-2022-jp',
        bytes: <int>[..._asciiBytes('ab'), 0x1B, 0x24, ..._asciiBytes('def')],
        replace: 'ab\uFFFD',
        ignore: 'ab',
        strictError: true,
      ),
    ];

    for (final _DecodeExpectation c in cases) {
      if (c.strictError) {
        expect(
          () => decodeBytes(c.bytes, encoding: c.encoding),
          throwsA(isA<CodecException>()),
          reason: 'encoding=${c.encoding} strict should fail',
        );
      } else {
        expect(
          decodeBytes(c.bytes, encoding: c.encoding),
          equals(c.replace),
          reason: 'encoding=${c.encoding} strict should keep valid escape text',
        );
      }
      expect(
        decodeBytes(
          c.bytes,
          encoding: c.encoding,
          errors: CodecErrorMode.replace,
        ),
        equals(c.replace),
        reason: 'encoding=${c.encoding} replace mismatch',
      );
      expect(
        decodeBytes(
          c.bytes,
          encoding: c.encoding,
          errors: CodecErrorMode.ignore,
        ),
        equals(c.ignore),
        reason: 'encoding=${c.encoding} ignore mismatch',
      );
    }
  });
}
