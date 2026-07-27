// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/codec/data_loader.dart';
import 'package:charset_codec/src/codec/resolver.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    CodecDataLoader.resetCachesForTesting();
  });

  test('row-compressed mbcs double decode keeps encode/decode equivalence', () {
    for (final String codec in generatedMultibyteDecodeTableCodecs) {
      final int codecId = resolveCodecId(codec)!;
      final PagedEncodeTable? table = CodecDataLoader.loadMbcsEncodeTable(
        codecId,
      );
      expect(table, isNotNull, reason: 'codec=$codec');
      if (table == null) {
        continue;
      }

      int seen = 0;
      for (int page = 0; page < 256; page++) {
        final int pageRef = table.pageDirectory[page];
        if (pageRef == 0) {
          continue;
        }
        final int base = (pageRef - 1) << 8;
        for (int low = 0; low < 256; low++) {
          final int packed = table.pageValues[base | low];
          if (packed == 0) {
            continue;
          }
          final int cp = (page << 8) | low;
          final List<int> bytes = <int>[];
          CodecDataLoader.appendPackedBytes(bytes, packed);
          final String decoded = decodeBytes(bytes, encoding: codec);
          expect(
            decoded,
            equals(String.fromCharCode(cp)),
            reason: 'codec=$codec cp=U+${cp.toRadixString(16).toUpperCase()}',
          );
          seen++;
          if (seen >= 512) {
            break;
          }
        }
        if (seen >= 512) {
          break;
        }
      }

      final int supplementaryStep = table.supplementaryKeys.length > 64
          ? table.supplementaryKeys.length ~/ 64
          : 1;
      for (
        int i = 0;
        i < table.supplementaryKeys.length;
        i += supplementaryStep
      ) {
        final int cp = table.supplementaryKeys[i];
        final int packed = table.supplementaryPackedValues[i];
        final List<int> bytes = <int>[];
        CodecDataLoader.appendPackedBytes(bytes, packed);
        final String decoded = decodeBytes(bytes, encoding: codec);
        expect(
          decoded,
          equals(String.fromCharCode(cp)),
          reason: 'codec=$codec cp=U+${cp.toRadixString(16).toUpperCase()}',
        );
      }
    }
  });

  test('stateful sections load from shared payload', () {
    final DenseDecodeTable? gb2312 = CodecDataLoader.loadIso2022SetDecodeTable(
      'gb2312',
    );
    final DenseDecodeTable hz = CodecDataLoader.loadHzDecodeTable();
    final PagedEncodeTable? gb2312Encode =
        CodecDataLoader.loadIso2022SetEncodeTable('gb2312');
    final PagedEncodeTable hzEncode = CodecDataLoader.loadHzEncodeTable();

    expect(gb2312, isNotNull);
    expect(gb2312Encode, isNotNull);
    expect(hz.values.isNotEmpty, isTrue);
    expect(hzEncode.pageDirectory.length, equals(256));
  });
}
