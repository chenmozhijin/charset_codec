// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

/// Cross-platform character encoding codecs aligned with CPython behavior.
///
/// Provides encoding and decoding, strict validation, asynchronous processing,
/// and bounded incremental processing across Dart VM, Flutter, and Web.
library;

export 'src/codec_api.dart'
    show
        decodeBytes,
        tryDecodeBytes,
        encodeString,
        tryEncodeString,
        decodeBytesAsync,
        encodeStringAsync,
        isValidDataForEncodingAsync,
        codec,
        isValidDataForEncoding;
export 'src/codec_metadata.dart'
    show CodecInfo, lookupCodecInfo, supportedPythonCodecNames;
export 'src/codec_types.dart'
    show
        CodecErrorMode,
        CodecOperation,
        CodecException,
        CharsetCodec,
        IncrementalDecoder,
        IncrementalEncoder;
