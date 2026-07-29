// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'codec/async_executor.dart';
import 'codec/backend.dart';
import 'codec_types.dart';

/// Resolves [encoding] to a codec using its canonical name or a common alias.
///
/// Unknown names throw [CodecException].
CharsetCodec codec(String encoding) =>
    activeCodecBackend.resolveCodec(encoding);

/// Whether [data] is completely valid for [encoding] in strict mode.
///
/// This performs strict validation only and does not return decoded text. It
/// returns `false` for unknown names or data that fails strict validation.
bool isValidDataForEncoding(List<int> data, String encoding) {
  return activeCodecBackend.isStrictlyValidData(data, encoding);
}

/// Decodes [bytes] with [encoding].
///
/// [errors] controls how malformed bytes are handled and defaults to strict
/// mode. Conversion failures and unknown names throw [CodecException].
String decodeBytes(
  List<int> bytes, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  return codec(encoding).decode(bytes, errors: errors);
}

/// Tries to decode [bytes] with [encoding], returning `null` on any failure.
///
/// Use this when invalid input should be treated as an ordinary miss; use
/// [decodeBytes] when the error position and reason are needed.
String? tryDecodeBytes(
  List<int> bytes, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  try {
    return decodeBytes(bytes, encoding: encoding, errors: errors);
  } catch (_) {
    return null;
  }
}

/// Encodes [text] with [encoding] and returns a new byte buffer.
///
/// [errors] controls how unrepresentable characters are handled and defaults to
/// strict mode. Conversion failures and unknown names throw [CodecException].
Uint8List encodeString(
  String text, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  return Uint8List.fromList(codec(encoding).encode(text, errors: errors));
}

/// Tries to encode [text] with [encoding], returning `null` on any failure.
///
/// Use this when conversion failure should be treated as an ordinary miss; use
/// [encodeString] when the error position and reason are needed.
Uint8List? tryEncodeString(
  String text, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  try {
    return encodeString(text, encoding: encoding, errors: errors);
  } catch (_) {
    return null;
  }
}

/// Asynchronously decodes [bytes] with [encoding].
///
/// On IO platforms, large inputs may run in a background isolate while small
/// inputs and Web use lightweight scheduling. Conversion errors are delivered
/// through the returned [Future].
Future<String> decodeBytesAsync(
  List<int> bytes, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  return runCodecAsync(
    () => decodeBytes(bytes, encoding: encoding, errors: errors),
    estimatedPayloadBytes: bytes.length,
  );
}

/// Asynchronously encodes [text] with [encoding].
///
/// On IO platforms, large inputs may run in a background isolate. The result is
/// an independent byte buffer, and conversion errors are delivered through the
/// returned [Future].
Future<Uint8List> encodeStringAsync(
  String text, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  return runCodecAsync(
    () => encodeString(text, encoding: encoding, errors: errors),
    estimatedPayloadBytes: text.length * 2,
  );
}

/// Asynchronously checks whether [data] is strictly valid for [encoding].
///
/// This does not produce decoded text. The returned [Future] completes with
/// `false` for unknown names or data that fails strict validation.
Future<bool> isValidDataForEncodingAsync(List<int> data, String encoding) {
  return runCodecAsync(
    () => isValidDataForEncoding(data, encoding),
    estimatedPayloadBytes: data.length,
  );
}
