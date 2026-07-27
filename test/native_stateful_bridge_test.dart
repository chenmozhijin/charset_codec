// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/src/codec/resolver.dart';
import 'package:charset_codec/src/codec_types.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';
import 'package:charset_codec/src/native/native_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native bridge advertises strict stateful codec support when available',
    () {
      final ResolvedCodec? cp950 = resolveCodec('cp950');
      final ResolvedCodec? gb2312 = resolveCodec('gb2312');
      final ResolvedCodec? hz = resolveCodec('hz-gb-2312');
      final ResolvedCodec? iso2022Jp = resolveCodec('iso-2022-jp');
      final ResolvedCodec? iso2022Jp1 = resolveCodec('iso2022-jp-1');
      final ResolvedCodec? iso2022Jp2 = resolveCodec('iso2022-jp-2');
      final ResolvedCodec? iso2022Jp2004 = resolveCodec('iso2022-jp-2004');
      final ResolvedCodec? iso2022Jp3 = resolveCodec('iso2022-jp-3');
      final ResolvedCodec? iso2022JpExt = resolveCodec('iso2022-jp-ext');
      final ResolvedCodec? iso2022Kr = resolveCodec('iso-2022-kr');

      expect(cp950, isNotNull);
      expect(gb2312, isNotNull);
      expect(hz, isNotNull);
      expect(iso2022Jp, isNotNull);
      expect(iso2022Jp1, isNotNull);
      expect(iso2022Jp2, isNotNull);
      expect(iso2022Jp2004, isNotNull);
      expect(iso2022Jp3, isNotNull);
      expect(iso2022JpExt, isNotNull);
      expect(iso2022Kr, isNotNull);

      if (!nativeCodecBridge.isAvailable) {
        expect(nativeCodecBridge.supportsCodec(cp950!), isFalse);
        expect(nativeCodecBridge.supportsCodec(gb2312!), isFalse);
        expect(nativeCodecBridge.supportsCodec(hz!), isFalse);
        expect(nativeCodecBridge.supportsCodec(iso2022Jp!), isFalse);
        expect(nativeCodecBridge.supportsCodec(iso2022Jp1!), isFalse);
        expect(nativeCodecBridge.supportsCodec(iso2022Jp2!), isFalse);
        expect(nativeCodecBridge.supportsCodec(iso2022Jp2004!), isFalse);
        expect(nativeCodecBridge.supportsCodec(iso2022Jp3!), isFalse);
        expect(nativeCodecBridge.supportsCodec(iso2022JpExt!), isFalse);
        expect(nativeCodecBridge.supportsCodec(iso2022Kr!), isFalse);
        return;
      }

      expect(nativeCodecBridge.supportsCodec(cp950!), isTrue);
      expect(
        nativeCodecBridge.supportsOperation(cp950, CodecErrorMode.strict),
        isTrue,
      );
      expect(
        nativeCodecBridge.supportsOperation(cp950, CodecErrorMode.replace),
        isFalse,
      );

      expect(nativeCodecBridge.supportsCodec(gb2312!), isTrue);
      expect(
        nativeCodecBridge.supportsOperation(gb2312, CodecErrorMode.strict),
        isTrue,
      );
      expect(
        nativeCodecBridge.supportsOperation(gb2312, CodecErrorMode.replace),
        isFalse,
      );

      expect(nativeCodecBridge.supportsCodec(hz!), isTrue);
      expect(
        nativeCodecBridge.supportsOperation(hz, CodecErrorMode.strict),
        isTrue,
      );
      expect(
        nativeCodecBridge.supportsOperation(hz, CodecErrorMode.replace),
        isFalse,
      );

      for (final ResolvedCodec resolved in <ResolvedCodec>[
        iso2022Jp!,
        iso2022Jp1!,
        iso2022Jp2!,
        iso2022Jp2004!,
        iso2022Jp3!,
        iso2022JpExt!,
      ]) {
        expect(nativeCodecBridge.supportsCodec(resolved), isTrue);
        expect(
          nativeCodecBridge.supportsOperation(resolved, CodecErrorMode.strict),
          isTrue,
        );
        expect(
          nativeCodecBridge.supportsOperation(
            resolved,
            CodecErrorMode.backslashReplace,
          ),
          isFalse,
        );
      }

      expect(nativeCodecBridge.supportsCodec(iso2022Kr!), isTrue);
      expect(
        nativeCodecBridge.supportsOperation(iso2022Kr, CodecErrorMode.strict),
        isTrue,
      );
      expect(
        nativeCodecBridge.supportsOperation(
          iso2022Kr,
          CodecErrorMode.backslashReplace,
        ),
        isFalse,
      );
    },
  );

  test('generated route matrix covers native multibyte support', () {
    for (final String canonical in generatedMultibyteCodecs) {
      final ResolvedCodec? resolved = resolveCodec(canonical);
      expect(resolved, isNotNull, reason: canonical);
      final bool expectedNativeRoute =
          generatedMultibyteDecodeTableCodecs.contains(canonical) ||
          generatedMultibyteStatefulCodecs.contains(canonical);
      if (nativeCodecBridge.isAvailable) {
        expect(
          nativeCodecBridge.supportsCodec(resolved!),
          expectedNativeRoute,
          reason: canonical,
        );
      }
    }
  });
}
