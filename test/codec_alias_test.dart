// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  test('codec resolves canonical/alias/normalized names', () {
    expect(codec('cp932').name, equals('cp932'));
    expect(codec('CP932').name, equals('cp932'));
    expect(codec('big5').name, equals('big5'));
    expect(codec('csbig5').name, equals('big5'));
    expect(codec('euc-jisx0213').name, equals('euc-jisx0213'));
    expect(codec('eucjisx0213').name, equals('euc-jisx0213'));
    expect(codec('gb2312').name, equals('gb2312'));
    expect(codec('gbk').name, equals('gbk'));
    expect(codec('cp936').name, equals('gbk'));
    expect(codec('iso-2022-jp').name, equals('iso-2022-jp'));
    expect(codec('csiso2022jp').name, equals('iso-2022-jp'));
    expect(codec('iso2022-jp-1').name, equals('iso2022-jp-1'));
    expect(codec('iso2022-jp-3').name, equals('iso2022-jp-3'));
    expect(codec('shift-jisx0213').name, equals('shift-jisx0213'));
    expect(codec('shiftjisx0213').name, equals('shift-jisx0213'));
    expect(codec('shift_jis').name, equals('shift_jis'));
    expect(codec('sjis').name, equals('shift_jis'));
    expect(codec('euc-jp').name, equals('euc-jp'));
    expect(codec('ujis').name, equals('euc-jp'));
    expect(codec('iso-8859-11').name, equals('iso-8859-11'));
    expect(codec('cp037').name, equals('cp037'));
    expect(codec('cp950').name, equals('cp950'));
    expect(codec('ms950').name, equals('cp950'));
    expect(codec('utf8').name, equals('utf-8'));
    expect(codec('latin_1').name, equals('iso-8859-1'));
    expect(codec('  windows_1252 ').name, equals('windows-1252'));
  });

  test('codec no longer accepts removed legacy compatibility aliases', () {
    expect(() => codec('windows-936'), throwsA(isA<CodecException>()));
    expect(() => codec('windows-950'), throwsA(isA<CodecException>()));
    expect(() => codec('utf-8-bom'), throwsA(isA<CodecException>()));
  });

  test('codec throws on unknown name', () {
    expect(
      () => codec('definitely-unknown-codec'),
      throwsA(isA<CodecException>()),
    );
  });

  test('codec returns shared singleton instances', () {
    expect(identical(codec('utf-8'), codec('utf8')), isTrue);
    expect(identical(codec('cp932'), codec('CP932')), isTrue);
  });
}
