// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves Dart and native codec routes from Flutter', () {
    expect(decodeBytes(const <int>[0x48, 0x69], encoding: 'ascii'), 'Hi');
    expect(
      decodeBytes(const <int>[0x93, 0xFA, 0x96, 0x7B], encoding: 'cp932'),
      '日本',
    );
    expect(encodeString('日本', encoding: 'cp932'), const <int>[
      0x93,
      0xFA,
      0x96,
      0x7B,
    ]);
  });
}
