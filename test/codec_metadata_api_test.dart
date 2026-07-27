// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

void main() {
  group('codec metadata api', () {
    test('lookupCodecInfo resolves known aliases', () {
      final CodecInfo? utf = lookupCodecInfo('utf_8');
      expect(utf, isNotNull);
      expect(utf!.canonicalName, 'utf-8');
      expect(utf.pythonCodecName, 'utf-8');
      expect(utf.isUtf, isTrue);
      expect(utf.isSingleByte, isFalse);
      expect(utf.isMultibyte, isFalse);

      final CodecInfo? cp1252 = lookupCodecInfo('cp1252');
      expect(cp1252, isNotNull);
      expect(cp1252!.canonicalName, 'windows-1252');
      expect(cp1252.pythonCodecName, 'cp1252');
      expect(cp1252.isUtf, isFalse);
      expect(cp1252.isSingleByte, isTrue);
      expect(cp1252.isMultibyte, isFalse);

      final CodecInfo? latin1 = lookupCodecInfo('latin_1');
      expect(latin1, isNotNull);
      expect(latin1!.canonicalName, 'iso-8859-1');
      expect(latin1.pythonCodecName, 'iso-8859-1');
    });

    test('lookupCodecInfo returns null for unknown encoding', () {
      expect(lookupCodecInfo('this-encoding-does-not-exist'), isNull);
    });

    test('supportedPythonCodecNames exposes known python codec names', () {
      final Set<String> names = supportedPythonCodecNames.toSet();
      expect(names.contains('utf-8'), isTrue);
      expect(names.contains('cp1252'), isTrue);
      expect(names.contains('gb18030'), isTrue);
      expect(names.contains('mac-arabic'), isTrue);
    });
  });
}
