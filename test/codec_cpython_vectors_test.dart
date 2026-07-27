// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'package:charset_codec/charset_codec.dart';
import 'package:test/test.dart';

import 'support/fixture_loader.dart';

CodecErrorMode _parseErrorMode(String raw) {
  switch (raw) {
    case 'strict':
      return CodecErrorMode.strict;
    case 'ignore':
      return CodecErrorMode.ignore;
    case 'replace':
      return CodecErrorMode.replace;
    case 'backslashReplace':
      return CodecErrorMode.backslashReplace;
    case 'xmlCharRefReplace':
      return CodecErrorMode.xmlCharRefReplace;
    case 'nameReplace':
      return CodecErrorMode.nameReplace;
    case 'surrogateEscape':
      return CodecErrorMode.surrogateEscape;
    case 'surrogatePass':
      return CodecErrorMode.surrogatePass;
  }
  throw ArgumentError.value(raw, 'raw', 'unknown codec error mode');
}

void main() {
  group('cpython vectors', tags: <String>['full', 'fixtures'], () {
    late final List<CodecVectorCase> vectors;

    setUpAll(() {
      final String? reason = hasFixturesOrSkipReason();
      expect(reason, isNull, reason: reason);
      vectors = loadCodecVectorCases();
      expect(vectors, isNotEmpty);
    });

    for (final String operation in <String>['decode', 'encode']) {
      test('vectors $operation parity', () {
        for (final CodecVectorCase c in vectors.where(
          (CodecVectorCase v) => v.operation == operation,
        )) {
          final CodecErrorMode mode = _parseErrorMode(c.errors);
          if (c.operation == 'decode') {
            final List<int> input = hexToBytes(c.inputHex!);
            if (c.expectError) {
              expect(
                () => decodeBytes(input, encoding: c.encoding, errors: mode),
                throwsA(isA<CodecException>()),
                reason: 'vector=${c.id}',
              );
            } else {
              expect(
                decodeBytes(input, encoding: c.encoding, errors: mode),
                equals(c.expectedText),
                reason: 'vector=${c.id}',
              );
            }
            continue;
          }

          final String input = c.inputText!;
          if (c.expectError) {
            expect(
              () => encodeString(input, encoding: c.encoding, errors: mode),
              throwsA(isA<CodecException>()),
              reason: 'vector=${c.id}',
            );
          } else {
            expect(
              encodeString(input, encoding: c.encoding, errors: mode),
              equals(hexToBytes(c.expectedHex!)),
              reason: 'vector=${c.id}',
            );
          }
        }
      });
    }
  });
}
