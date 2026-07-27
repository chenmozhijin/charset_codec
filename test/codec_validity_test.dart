// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  test('isValidDataForEncoding returns false for unknown encoding', () {
    expect(
      isValidDataForEncoding(const <int>[0x41], 'x-unknown-encoding'),
      isFalse,
    );
  });

  test('isValidDataForEncoding returns false for strict decode failure', () {
    expect(isValidDataForEncoding(const <int>[0xFF], 'utf-8'), isFalse);
  });

  test('isValidDataForEncoding returns true for valid bytes', () {
    expect(isValidDataForEncoding('hello'.codeUnits, 'utf-8'), isTrue);
  });
}
