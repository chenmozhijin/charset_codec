// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../codec_types.dart';
import 'data_loader.dart';
import 'resolver.dart';

bool validateSingleByte(List<int> bytes, int codecId) {
  final DenseDecodeTable? dense = CodecDataLoader.loadSbcsDecodeTable(codecId);
  final Uint32List? table = dense?.values;
  if (table == null || table.length != 256) {
    return false;
  }
  for (int i = 0; i < bytes.length; i++) {
    final int cp = table[bytes[i] & 0xFF];
    if (cp == invalidCodePoint || cp == multiCodePoint) {
      return false;
    }
  }
  return true;
}

String decodeSingleByte(
  List<int> bytes,
  int codecId, {
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  final String encoding = canonicalNameForCodecId(codecId);
  final DenseDecodeTable? dense = CodecDataLoader.loadSbcsDecodeTable(codecId);
  final Uint32List? table = dense?.values;
  if (table == null || table.length != 256) {
    throw CodecException(
      encoding: encoding,
      operation: CodecOperation.decode,
      position: 0,
      reason: 'single-byte decode table not found',
    );
  }

  final StringBuffer out = StringBuffer();
  for (int i = 0; i < bytes.length; i++) {
    final int b = bytes[i] & 0xFF;
    final int cp = table[b];
    if (cp != invalidCodePoint && cp != multiCodePoint) {
      out.writeCharCode(cp);
      continue;
    }
    switch (errors) {
      case CodecErrorMode.strict:
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: i,
          reason: 'invalid byte 0x${b.toRadixString(16).padLeft(2, '0')}',
        );
      case CodecErrorMode.ignore:
        continue;
      case CodecErrorMode.backslashReplace:
        out.write(r'\x');
        out.write(b.toRadixString(16).padLeft(2, '0'));
        continue;
      case CodecErrorMode.surrogateEscape:
        out.writeCharCode(0xDC00 + b);
        continue;
      case CodecErrorMode.replace:
      case CodecErrorMode.xmlCharRefReplace:
      case CodecErrorMode.nameReplace:
      case CodecErrorMode.surrogatePass:
        out.writeCharCode(0xFFFD);
        continue;
    }
  }
  return out.toString();
}

List<int> encodeSingleByte(
  String text,
  int codecId, {
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  final String encoding = canonicalNameForCodecId(codecId);
  final PagedEncodeTable? table = CodecDataLoader.loadSbcsEncodeTable(codecId);
  if (table == null) {
    throw CodecException(
      encoding: encoding,
      operation: CodecOperation.encode,
      position: 0,
      reason: 'single-byte encode table not found',
    );
  }

  final List<int> out = <int>[];
  int i = 0;
  for (final int cp in text.runes) {
    final int? packed = table.lookupPacked(cp);
    if (packed != null) {
      out.add(CodecDataLoader.packedByteAt(packed, 0));
      i += 1;
      continue;
    }
    if (errors == CodecErrorMode.surrogateEscape &&
        cp >= 0xDC80 &&
        cp <= 0xDCFF) {
      out.add(cp - 0xDC00);
      i += 1;
      continue;
    }
    switch (errors) {
      case CodecErrorMode.strict:
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.encode,
          position: i,
          reason:
              'character U+${cp.toRadixString(16).toUpperCase()} is not encodable',
        );
      case CodecErrorMode.ignore:
        i += 1;
        continue;
      case CodecErrorMode.replace:
      case CodecErrorMode.surrogatePass:
        out.add(0x3F);
        i += 1;
        continue;
      case CodecErrorMode.backslashReplace:
        out.addAll(_asciiEscape(cp, lowercaseHex: true));
        i += 1;
        continue;
      case CodecErrorMode.xmlCharRefReplace:
        out.addAll('&#$cp;'.codeUnits);
        i += 1;
        continue;
      case CodecErrorMode.nameReplace:
        out.addAll(r'\N{U+'.codeUnits);
        out.addAll(cp.toRadixString(16).toUpperCase().codeUnits);
        out.addAll('}'.codeUnits);
        i += 1;
        continue;
      case CodecErrorMode.surrogateEscape:
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.encode,
          position: i,
          reason:
              'character U+${cp.toRadixString(16).toUpperCase()} is not encodable',
        );
    }
  }
  return out;
}

List<int> _asciiEscape(int cp, {required bool lowercaseHex}) {
  final String hex = cp.toRadixString(16);
  if (cp <= 0xFF) {
    return ('\\x${hex.padLeft(2, '0')}'.toLowerCase()).codeUnits;
  }
  if (cp <= 0xFFFF) {
    final String h = hex.padLeft(4, '0');
    return '${lowercaseHex ? r'\u' : r'\U'}${lowercaseHex ? h : h.toUpperCase()}'
        .codeUnits;
  }
  final String h = hex.padLeft(8, '0');
  return r'\U'
          '${lowercaseHex ? h : h.toUpperCase()}'
      .codeUnits;
}
