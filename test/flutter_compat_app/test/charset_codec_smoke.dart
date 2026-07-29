// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves and runs charset_codec from Flutter', () {
    expect(
      decodeBytes(const <int>[0x48, 0x69], encoding: 'ascii'),
      'Hi',
    );
  });
}
