// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  group('mac family codecs', () {
    test('new mac codecs resolve module-style aliases', () {
      expect(codec('mac_arabic').name, equals('mac-arabic'));
      expect(codec('mac_croatian').name, equals('mac-croatian'));
      expect(codec('mac_farsi').name, equals('mac-farsi'));
      expect(codec('mac_romanian').name, equals('mac-romanian'));
    });

    test('new mac codecs decode and encode representative bytes', () {
      expect(
        decodeBytes(const <int>[0x80], encoding: 'mac-arabic'),
        equals('\u00C4'),
      );
      expect(
        decodeBytes(const <int>[0x80], encoding: 'mac-croatian'),
        equals('\u00C4'),
      );
      expect(
        encodeString('\u00C4', encoding: 'mac-farsi'),
        equals(const <int>[0x80]),
      );
      expect(
        encodeString('\u00C4', encoding: 'mac-romanian'),
        equals(const <int>[0x80]),
      );
    });
  });
}
