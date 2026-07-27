// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'codec/async_executor.dart';
import 'codec/backend.dart';
import 'codec_types.dart';

CharsetCodec codec(String encoding) =>
    activeCodecBackend.resolveCodec(encoding);

bool isValidDataForEncoding(List<int> data, String encoding) {
  return activeCodecBackend.isStrictlyValidData(data, encoding);
}

String decodeBytes(
  List<int> bytes, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  return codec(encoding).decode(bytes, errors: errors);
}

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

Uint8List encodeString(
  String text, {
  required String encoding,
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  return Uint8List.fromList(codec(encoding).encode(text, errors: errors));
}

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

Future<bool> isValidDataForEncodingAsync(List<int> data, String encoding) {
  return runCodecAsync(
    () => isValidDataForEncoding(data, encoding),
    estimatedPayloadBytes: data.length,
  );
}
