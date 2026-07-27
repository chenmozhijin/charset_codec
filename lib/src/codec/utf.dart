// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../codec_types.dart';
import 'resolver.dart';

const String _utf7Base64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

final class UtfIncrementalDecoderState {
  UtfIncrementalDecoderState(this.codecId)
    : pendingBytes = <int>[],
      atStart = true,
      littleEndian = _defaultLittleEndianForCodec(codecId),
      utf7InShift = false,
      utf7ShiftHasBase64 = false,
      utf7Base64Bits = 0,
      utf7Base64Buffer = 0,
      utf7ProcessedBytes = 0;

  UtfIncrementalDecoderState.copy(UtfIncrementalDecoderState other)
    : codecId = other.codecId,
      pendingBytes = List<int>.from(other.pendingBytes),
      atStart = other.atStart,
      littleEndian = other.littleEndian,
      utf7InShift = other.utf7InShift,
      utf7ShiftHasBase64 = other.utf7ShiftHasBase64,
      utf7Base64Bits = other.utf7Base64Bits,
      utf7Base64Buffer = other.utf7Base64Buffer,
      utf7PendingHighSurrogate = other.utf7PendingHighSurrogate,
      utf7ShiftStart = other.utf7ShiftStart,
      utf7ProcessedBytes = other.utf7ProcessedBytes;

  final int codecId;
  final List<int> pendingBytes;
  bool atStart;
  bool littleEndian;
  bool utf7InShift;
  bool utf7ShiftHasBase64;
  int utf7Base64Bits;
  int utf7Base64Buffer;
  int? utf7PendingHighSurrogate;
  int utf7ShiftStart = 0;
  int utf7ProcessedBytes;
}

final class UtfIncrementalEncoderState {
  UtfIncrementalEncoderState(this.codecId)
    : pendingScalar = '',
      bomEmitted = false,
      utf7InShift = false,
      utf7Base64Bits = 0,
      utf7Base64Buffer = 0;

  UtfIncrementalEncoderState.copy(UtfIncrementalEncoderState other)
    : codecId = other.codecId,
      pendingScalar = other.pendingScalar,
      bomEmitted = other.bomEmitted,
      utf7InShift = other.utf7InShift,
      utf7Base64Bits = other.utf7Base64Bits,
      utf7Base64Buffer = other.utf7Base64Buffer;

  final int codecId;
  String pendingScalar;
  bool bomEmitted;
  bool utf7InShift;
  int utf7Base64Bits;
  int utf7Base64Buffer;
}

String decodeUtf(
  List<int> bytes,
  int codecId, {
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  final String name = canonicalNameForCodecId(codecId);
  if (name == 'utf-8') {
    return _decodeUtf8(bytes, errors: errors);
  }
  if (name == 'utf-8-sig') {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _decodeUtf8(bytes.sublist(3), errors: errors);
    }
    return _decodeUtf8(bytes, errors: errors);
  }
  if (name == 'utf-16' || name == 'utf-16-le' || name == 'utf-16-be') {
    return _decodeUtf16(bytes, name, errors: errors);
  }
  if (name == 'utf-32' || name == 'utf-32-le' || name == 'utf-32-be') {
    return _decodeUtf32(bytes, name, errors: errors);
  }
  if (name == 'utf-7') {
    return _decodeUtf7(bytes, errors: errors);
  }
  throw CodecException(
    encoding: name,
    operation: CodecOperation.decode,
    position: 0,
    reason: 'unsupported utf codec',
  );
}

List<int> encodeUtf(
  String text,
  int codecId, {
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  final String name = canonicalNameForCodecId(codecId);
  if (name == 'utf-8') {
    return _encodeUtf8(text, errors: errors);
  }
  if (name == 'utf-8-sig') {
    return <int>[0xEF, 0xBB, 0xBF, ..._encodeUtf8(text, errors: errors)];
  }
  if (name == 'utf-16' || name == 'utf-16-le' || name == 'utf-16-be') {
    return _encodeUtf16(text, name, errors: errors);
  }
  if (name == 'utf-32' || name == 'utf-32-le' || name == 'utf-32-be') {
    return _encodeUtf32(text, name, errors: errors);
  }
  if (name == 'utf-7') {
    return _encodeUtf7(text, errors: errors);
  }
  throw CodecException(
    encoding: name,
    operation: CodecOperation.encode,
    position: 0,
    reason: 'unsupported utf codec',
  );
}

bool validateUtf(List<int> bytes, int codecId) {
  final String name = canonicalNameForCodecId(codecId);
  switch (name) {
    case 'utf-8':
      return _validateUtf8(bytes);
    case 'utf-8-sig':
      return _validateUtf8(
        bytes.length >= 3 &&
                bytes[0] == 0xEF &&
                bytes[1] == 0xBB &&
                bytes[2] == 0xBF
            ? bytes.sublist(3)
            : bytes,
      );
    case 'utf-16':
    case 'utf-16-le':
    case 'utf-16-be':
      return _validateUtf16(bytes, name);
    case 'utf-32':
    case 'utf-32-le':
    case 'utf-32-be':
      return _validateUtf32(bytes, name);
    case 'utf-7':
      try {
        _decodeUtf7(bytes, errors: CodecErrorMode.strict);
        return true;
      } on CodecException {
        return false;
      }
    default:
      return false;
  }
}

bool supportsIncrementalUtf(int codecId) {
  return true;
}

String decodeUtfIncrementalChunk(
  List<int> chunk,
  UtfIncrementalDecoderState state, {
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  final String encoding = canonicalNameForCodecId(state.codecId);
  switch (encoding) {
    case 'utf-8':
    case 'utf-8-sig':
      return _decodeUtf8IncrementalChunk(
        chunk,
        state,
        encoding: encoding,
        errors: errors,
        finalChunk: finalChunk,
      );
    case 'utf-16':
    case 'utf-16-le':
    case 'utf-16-be':
      return _decodeUtf16IncrementalChunk(
        chunk,
        state,
        encoding: encoding,
        errors: errors,
        finalChunk: finalChunk,
      );
    case 'utf-32':
    case 'utf-32-le':
    case 'utf-32-be':
      return _decodeUtf32IncrementalChunk(
        chunk,
        state,
        encoding: encoding,
        errors: errors,
        finalChunk: finalChunk,
      );
    case 'utf-7':
      return _decodeUtf7IncrementalChunk(
        chunk,
        state,
        errors: errors,
        finalChunk: finalChunk,
      );
    default:
      throw StateError(
        'unsupported utf codec for incremental decode: $encoding',
      );
  }
}

List<int> encodeUtfIncrementalChunk(
  String chunk,
  UtfIncrementalEncoderState state, {
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  final String encoding = canonicalNameForCodecId(state.codecId);
  if (encoding == 'utf-7') {
    return _encodeUtf7IncrementalChunk(
      chunk,
      state,
      errors: errors,
      finalChunk: finalChunk,
    );
  }

  String text;
  if (state.pendingScalar.isEmpty) {
    text = chunk;
  } else if (chunk.isEmpty) {
    text = state.pendingScalar;
    state.pendingScalar = '';
  } else {
    text = '${state.pendingScalar}$chunk';
    state.pendingScalar = '';
  }
  if (text.isEmpty) {
    return const <int>[];
  }
  if (!finalChunk && _endsWithHighSurrogateCodeUnit(text)) {
    state.pendingScalar = text.substring(text.length - 1);
    text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty) {
    return const <int>[];
  }

  switch (encoding) {
    case 'utf-8':
      return _encodeUtf8(text, errors: errors);
    case 'utf-8-sig':
      final List<int> out = <int>[];
      if (!state.bomEmitted) {
        out.addAll(const <int>[0xEF, 0xBB, 0xBF]);
        state.bomEmitted = true;
      }
      out.addAll(_encodeUtf8(text, errors: errors));
      return out;
    case 'utf-16':
      if (!state.bomEmitted) {
        state.bomEmitted = true;
        return <int>[
          0xFF,
          0xFE,
          ..._encodeUtf16(text, 'utf-16-le', errors: errors),
        ];
      }
      return _encodeUtf16(text, 'utf-16-le', errors: errors);
    case 'utf-16-le':
    case 'utf-16-be':
      return _encodeUtf16(text, encoding, errors: errors);
    case 'utf-32':
      if (!state.bomEmitted) {
        state.bomEmitted = true;
        return <int>[
          0xFF,
          0xFE,
          0x00,
          0x00,
          ..._encodeUtf32(text, 'utf-32-le', errors: errors),
        ];
      }
      return _encodeUtf32(text, 'utf-32-le', errors: errors);
    case 'utf-32-le':
    case 'utf-32-be':
      return _encodeUtf32(text, encoding, errors: errors);
    default:
      throw StateError(
        'unsupported utf codec for incremental encode: $encoding',
      );
  }
}

void resetUtfIncrementalDecoderState(UtfIncrementalDecoderState state) {
  state.pendingBytes.clear();
  state.atStart = true;
  state.littleEndian = _defaultLittleEndianForCodec(state.codecId);
  state.utf7InShift = false;
  state.utf7ShiftHasBase64 = false;
  state.utf7Base64Bits = 0;
  state.utf7Base64Buffer = 0;
  state.utf7PendingHighSurrogate = null;
  state.utf7ShiftStart = 0;
  state.utf7ProcessedBytes = 0;
}

void resetUtfIncrementalEncoderState(UtfIncrementalEncoderState state) {
  state.pendingScalar = '';
  state.bomEmitted = false;
  state.utf7InShift = false;
  state.utf7Base64Bits = 0;
  state.utf7Base64Buffer = 0;
}

bool _defaultLittleEndianForCodec(int codecId) {
  final String encoding = canonicalNameForCodecId(codecId);
  return encoding != 'utf-16-be' && encoding != 'utf-32-be';
}

bool _endsWithHighSurrogateCodeUnit(String text) {
  if (text.isEmpty) {
    return false;
  }
  return _isHighSurrogate(text.codeUnitAt(text.length - 1));
}

List<int> _combinePendingBytes(List<int> pending, List<int> chunk) {
  if (pending.isEmpty) {
    return List<int>.from(chunk);
  }
  return <int>[...pending, ...chunk];
}

String _decodeUtf8IncrementalChunk(
  List<int> chunk,
  UtfIncrementalDecoderState state, {
  required String encoding,
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  final List<int> bytes = _combinePendingBytes(state.pendingBytes, chunk);
  state.pendingBytes.clear();
  if (bytes.isEmpty) {
    return '';
  }

  int i = 0;
  if (encoding == 'utf-8-sig' && state.atStart) {
    if (!finalChunk && bytes.length < 3 && _isUtf8BomPrefix(bytes)) {
      state.pendingBytes.addAll(bytes);
      return '';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      i = 3;
    }
  }
  state.atStart = false;

  final StringBuffer out = StringBuffer();
  while (i < bytes.length) {
    final int b0 = bytes[i] & 0xFF;
    if (b0 < 0x80) {
      out.writeCharCode(b0);
      i += 1;
      continue;
    }

    int needed = 0;
    int minCp = 0;
    int cp = 0;
    if (b0 >= 0xC2 && b0 <= 0xDF) {
      needed = 2;
      minCp = 0x80;
      cp = b0 & 0x1F;
    } else if (b0 >= 0xE0 && b0 <= 0xEF) {
      needed = 3;
      minCp = 0x800;
      cp = b0 & 0x0F;
    } else if (b0 >= 0xF0 && b0 <= 0xF4) {
      needed = 4;
      minCp = 0x10000;
      cp = b0 & 0x07;
    } else {
      _appendUtf8DecodeError(out, bytes, start: i, end: i + 1, errors: errors);
      i += 1;
      continue;
    }

    if (i + needed > bytes.length) {
      if (!finalChunk) {
        state.pendingBytes.addAll(bytes.getRange(i, bytes.length));
        break;
      }
      if (errors == CodecErrorMode.strict ||
          errors == CodecErrorMode.surrogatePass) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: i,
          reason: 'unexpected end of data',
        );
      }
      _appendUtf8DecodeError(
        out,
        bytes,
        start: i,
        end: bytes.length,
        errors: errors,
      );
      break;
    }

    bool invalid = false;
    for (int j = 1; j < needed; j++) {
      final int bx = bytes[i + j] & 0xFF;
      if ((bx & 0xC0) != 0x80) {
        invalid = true;
        break;
      }
      cp = (cp << 6) | (bx & 0x3F);
    }
    if (invalid || cp < minCp || cp > 0x10FFFF) {
      _appendUtf8DecodeError(out, bytes, start: i, end: i + 1, errors: errors);
      i += 1;
      continue;
    }

    if (cp >= 0xD800 && cp <= 0xDFFF) {
      if (errors == CodecErrorMode.surrogatePass) {
        out.writeCharCode(cp);
        i += needed;
        continue;
      }
      _appendUtf8DecodeError(out, bytes, start: i, end: i + 1, errors: errors);
      i += 1;
      continue;
    }

    out.write(String.fromCharCode(cp));
    i += needed;
  }
  return out.toString();
}

String _decodeUtf16IncrementalChunk(
  List<int> chunk,
  UtfIncrementalDecoderState state, {
  required String encoding,
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  final List<int> bytes = _combinePendingBytes(state.pendingBytes, chunk);
  state.pendingBytes.clear();
  if (bytes.isEmpty) {
    return '';
  }

  int i = 0;
  if (encoding == 'utf-16' && state.atStart) {
    if (!finalChunk && bytes.length < 2) {
      state.pendingBytes.addAll(bytes);
      return '';
    }
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFF) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFE))) {
      throw CodecException(
        encoding: encoding,
        operation: CodecOperation.decode,
        position: 0,
        reason: 'invalid utf-16 BOM',
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      state.littleEndian = false;
      i = 2;
    } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      state.littleEndian = true;
      i = 2;
    } else {
      state.littleEndian = true;
    }
  }
  state.atStart = false;

  final StringBuffer out = StringBuffer();
  while (i + 1 < bytes.length) {
    final int unit = _readUint16FromBytes(bytes, i, state.littleEndian);
    if (_isHighSurrogate(unit)) {
      if (i + 3 >= bytes.length) {
        if (!finalChunk) {
          state.pendingBytes.addAll(bytes.getRange(i, bytes.length));
          return out.toString();
        }
        if (errors == CodecErrorMode.strict) {
          throw CodecException(
            encoding: encoding,
            operation: CodecOperation.decode,
            position: i,
            reason: 'unexpected end of data',
          );
        }
        if (errors == CodecErrorMode.ignore) {
          i += 2;
          continue;
        }
        if (errors == CodecErrorMode.surrogatePass) {
          out.writeCharCode(unit);
        } else {
          out.writeCharCode(0xFFFD);
        }
        i += 2;
        continue;
      }
      final int next = _readUint16FromBytes(bytes, i + 2, state.littleEndian);
      if (_isLowSurrogate(next)) {
        out.write(String.fromCharCode(_joinSurrogates(unit, next)));
        i += 4;
        continue;
      }
      if (errors == CodecErrorMode.strict) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: i,
          reason: 'unexpected end of data',
        );
      }
      if (errors == CodecErrorMode.ignore) {
        i += 2;
        continue;
      }
      if (errors == CodecErrorMode.surrogatePass) {
        out.writeCharCode(unit);
      } else {
        out.writeCharCode(0xFFFD);
      }
      i += 2;
      continue;
    }
    if (_isLowSurrogate(unit)) {
      if (errors == CodecErrorMode.strict) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: i,
          reason: 'unexpected end of data',
        );
      }
      if (errors == CodecErrorMode.ignore) {
        i += 2;
        continue;
      }
      if (errors == CodecErrorMode.surrogatePass) {
        out.writeCharCode(unit);
      } else {
        out.writeCharCode(0xFFFD);
      }
      i += 2;
      continue;
    }
    out.writeCharCode(unit);
    i += 2;
  }

  if (i < bytes.length) {
    if (!finalChunk) {
      state.pendingBytes.add(bytes[i] & 0xFF);
      return out.toString();
    }
    _appendUtf16TrailingOddByte(out, bytes.last & 0xFF, encoding, errors);
  }

  return out.toString();
}

String _decodeUtf32IncrementalChunk(
  List<int> chunk,
  UtfIncrementalDecoderState state, {
  required String encoding,
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  final List<int> bytes = _combinePendingBytes(state.pendingBytes, chunk);
  state.pendingBytes.clear();
  if (bytes.isEmpty) {
    return '';
  }

  int i = 0;
  if (encoding == 'utf-32' && state.atStart) {
    if (!finalChunk && bytes.length < 4) {
      state.pendingBytes.addAll(bytes);
      return '';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        bytes[2] == 0xFE &&
        bytes[3] == 0xFF) {
      state.littleEndian = false;
      i = 4;
    } else if (bytes.length >= 4 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xFE &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x00) {
      state.littleEndian = true;
      i = 4;
    } else {
      state.littleEndian = true;
    }
  }
  state.atStart = false;

  final StringBuffer out = StringBuffer();
  while (i + 3 < bytes.length) {
    final int cp = _readUint32FromBytes(bytes, i, state.littleEndian);
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
      if (errors == CodecErrorMode.strict) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: i,
          reason: 'invalid unicode scalar in utf-32 input',
        );
      }
      if (errors == CodecErrorMode.ignore) {
        i += 4;
        continue;
      }
      if (errors == CodecErrorMode.surrogatePass &&
          cp >= 0xD800 &&
          cp <= 0xDFFF) {
        out.writeCharCode(cp);
        i += 4;
        continue;
      }
      out.writeCharCode(0xFFFD);
      i += 4;
      continue;
    }
    out.write(String.fromCharCode(cp));
    i += 4;
  }

  if (i < bytes.length) {
    if (!finalChunk) {
      state.pendingBytes.addAll(bytes.getRange(i, bytes.length));
      return out.toString();
    }
    if (errors == CodecErrorMode.strict) {
      throw CodecException(
        encoding: encoding,
        operation: CodecOperation.decode,
        position: bytes.length,
        reason: 'utf-32 input length is not divisible by 4',
      );
    }
    if (errors == CodecErrorMode.replace) {
      out.writeCharCode(0xFFFD);
    }
  }

  return out.toString();
}

int _readUint16FromBytes(List<int> bytes, int offset, bool littleEndian) {
  if (littleEndian) {
    return (bytes[offset] & 0xFF) | ((bytes[offset + 1] & 0xFF) << 8);
  }
  return ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
}

int _readUint32FromBytes(List<int> bytes, int offset, bool littleEndian) {
  if (littleEndian) {
    return (bytes[offset] & 0xFF) |
        ((bytes[offset + 1] & 0xFF) << 8) |
        ((bytes[offset + 2] & 0xFF) << 16) |
        ((bytes[offset + 3] & 0xFF) << 24);
  }
  return ((bytes[offset] & 0xFF) << 24) |
      ((bytes[offset + 1] & 0xFF) << 16) |
      ((bytes[offset + 2] & 0xFF) << 8) |
      (bytes[offset + 3] & 0xFF);
}

void _appendUtf16TrailingOddByte(
  StringBuffer out,
  int byteValue,
  String encoding,
  CodecErrorMode errors,
) {
  if (errors == CodecErrorMode.replace ||
      errors == CodecErrorMode.xmlCharRefReplace ||
      errors == CodecErrorMode.nameReplace ||
      errors == CodecErrorMode.surrogatePass) {
    out.writeCharCode(0xFFFD);
    return;
  }
  if (errors == CodecErrorMode.backslashReplace) {
    out.write(r'\x');
    out.write(byteValue.toRadixString(16).padLeft(2, '0'));
    return;
  }
  if (errors == CodecErrorMode.surrogateEscape) {
    if (byteValue >= 0x80) {
      out.writeCharCode(0xDC00 + byteValue);
      return;
    }
    throw CodecException(
      encoding: encoding,
      operation: CodecOperation.decode,
      position: 0,
      reason: 'utf-16 input has odd byte length',
    );
  }
  if (errors == CodecErrorMode.strict) {
    throw CodecException(
      encoding: encoding,
      operation: CodecOperation.decode,
      position: 0,
      reason: 'utf-16 input has odd byte length',
    );
  }
}

bool _isUtf8BomPrefix(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 2) {
    return false;
  }
  if (bytes[0] != 0xEF) {
    return false;
  }
  return bytes.length == 1 || bytes[1] == 0xBB;
}

bool _validateUtf8(List<int> bytes) {
  int i = 0;
  while (i < bytes.length) {
    final int b0 = bytes[i] & 0xFF;
    if (b0 < 0x80) {
      i++;
      continue;
    }
    if (b0 < 0xC2 || b0 > 0xF4) {
      return false;
    }
    if (b0 < 0xE0) {
      if (i + 1 >= bytes.length) {
        return false;
      }
      final int b1 = bytes[i + 1] & 0xFF;
      if ((b1 & 0xC0) != 0x80) {
        return false;
      }
      i += 2;
      continue;
    }
    if (b0 < 0xF0) {
      if (i + 2 >= bytes.length) {
        return false;
      }
      final int b1 = bytes[i + 1] & 0xFF;
      final int b2 = bytes[i + 2] & 0xFF;
      if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80) {
        return false;
      }
      if ((b0 == 0xE0 && b1 < 0xA0) || (b0 == 0xED && b1 >= 0xA0)) {
        return false;
      }
      i += 3;
      continue;
    }
    if (i + 3 >= bytes.length) {
      return false;
    }
    final int b1 = bytes[i + 1] & 0xFF;
    final int b2 = bytes[i + 2] & 0xFF;
    final int b3 = bytes[i + 3] & 0xFF;
    if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80) {
      return false;
    }
    if ((b0 == 0xF0 && b1 < 0x90) || (b0 == 0xF4 && b1 >= 0x90)) {
      return false;
    }
    i += 4;
  }
  return true;
}

bool _validateUtf16(List<int> bytes, String encoding) {
  bool littleEndian;
  int offset = 0;
  if (encoding == 'utf-16') {
    if (bytes.length < 2) {
      return false;
    }
    final int b0 = bytes[0] & 0xFF;
    final int b1 = bytes[1] & 0xFF;
    if (b0 == 0xFF && b1 == 0xFE) {
      littleEndian = true;
      offset = 2;
    } else if (b0 == 0xFE && b1 == 0xFF) {
      littleEndian = false;
      offset = 2;
    } else {
      return false;
    }
  } else {
    littleEndian = encoding == 'utf-16-le';
  }
  if (((bytes.length - offset) & 1) != 0) {
    return false;
  }
  for (int i = offset; i < bytes.length; i += 2) {
    final int unit = littleEndian
        ? (bytes[i] & 0xFF) | ((bytes[i + 1] & 0xFF) << 8)
        : ((bytes[i] & 0xFF) << 8) | (bytes[i + 1] & 0xFF);
    if (_isHighSurrogate(unit)) {
      if (i + 3 >= bytes.length) {
        return false;
      }
      final int next = littleEndian
          ? (bytes[i + 2] & 0xFF) | ((bytes[i + 3] & 0xFF) << 8)
          : ((bytes[i + 2] & 0xFF) << 8) | (bytes[i + 3] & 0xFF);
      if (!_isLowSurrogate(next)) {
        return false;
      }
      i += 2;
      continue;
    }
    if (_isLowSurrogate(unit)) {
      return false;
    }
  }
  return true;
}

bool _validateUtf32(List<int> bytes, String encoding) {
  bool littleEndian;
  int offset = 0;
  if (encoding == 'utf-32') {
    if (bytes.length < 4) {
      return false;
    }
    final int b0 = bytes[0] & 0xFF;
    final int b1 = bytes[1] & 0xFF;
    final int b2 = bytes[2] & 0xFF;
    final int b3 = bytes[3] & 0xFF;
    if (b0 == 0xFF && b1 == 0xFE && b2 == 0x00 && b3 == 0x00) {
      littleEndian = true;
      offset = 4;
    } else if (b0 == 0x00 && b1 == 0x00 && b2 == 0xFE && b3 == 0xFF) {
      littleEndian = false;
      offset = 4;
    } else {
      return false;
    }
  } else {
    littleEndian = encoding == 'utf-32-le';
  }
  if (((bytes.length - offset) & 3) != 0) {
    return false;
  }
  for (int i = offset; i < bytes.length; i += 4) {
    final int cp = littleEndian
        ? (bytes[i] & 0xFF) |
              ((bytes[i + 1] & 0xFF) << 8) |
              ((bytes[i + 2] & 0xFF) << 16) |
              ((bytes[i + 3] & 0xFF) << 24)
        : ((bytes[i] & 0xFF) << 24) |
              ((bytes[i + 1] & 0xFF) << 16) |
              ((bytes[i + 2] & 0xFF) << 8) |
              (bytes[i + 3] & 0xFF);
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
      return false;
    }
  }
  return true;
}

String _decodeUtf7IncrementalChunk(
  List<int> chunk,
  UtfIncrementalDecoderState state, {
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  final StringBuffer out = StringBuffer();

  void appendError(int byteValue, int position, String reason) {
    switch (errors) {
      case CodecErrorMode.strict:
      case CodecErrorMode.surrogatePass:
      case CodecErrorMode.surrogateEscape:
        throw CodecException(
          encoding: 'utf-7',
          operation: CodecOperation.decode,
          position: position,
          reason: reason,
        );
      case CodecErrorMode.ignore:
        return;
      case CodecErrorMode.replace:
      case CodecErrorMode.xmlCharRefReplace:
      case CodecErrorMode.nameReplace:
        out.writeCharCode(0xFFFD);
        return;
      case CodecErrorMode.backslashReplace:
        out.write(r'\x');
        out.write((byteValue & 0xFF).toRadixString(16).padLeft(2, '0'));
        return;
    }
  }

  void clearShift() {
    state.utf7InShift = false;
    state.utf7ShiftHasBase64 = false;
    state.utf7Base64Bits = 0;
    state.utf7Base64Buffer = 0;
    state.utf7PendingHighSurrogate = null;
  }

  int i = 0;
  while (i < chunk.length) {
    final int ch = chunk[i] & 0xFF;
    final int position = state.utf7ProcessedBytes + i;
    if (state.utf7InShift) {
      if (_isUtf7Base64(ch)) {
        state.utf7ShiftHasBase64 = true;
        state.utf7Base64Buffer =
            (state.utf7Base64Buffer << 6) | _utf7FromBase64(ch);
        state.utf7Base64Bits += 6;
        i += 1;
        while (state.utf7Base64Bits >= 16) {
          final int unit =
              (state.utf7Base64Buffer >> (state.utf7Base64Bits - 16)) & 0xFFFF;
          state.utf7Base64Bits -= 16;
          state.utf7Base64Buffer &= (1 << state.utf7Base64Bits) - 1;
          final int? high = state.utf7PendingHighSurrogate;
          if (high != null) {
            state.utf7PendingHighSurrogate = null;
            if (_isLowSurrogate(unit)) {
              out.writeCharCode(_joinSurrogates(high, unit));
              continue;
            }
            out.writeCharCode(high);
          }
          if (_isHighSurrogate(unit)) {
            state.utf7PendingHighSurrogate = unit;
          } else {
            out.writeCharCode(unit);
          }
        }
        continue;
      }

      if (!state.utf7ShiftHasBase64) {
        if (ch == 0x2D) {
          out.writeCharCode(0x2B);
          clearShift();
          i += 1;
          continue;
        }
        appendError(ch, state.utf7ShiftStart, 'ill-formed sequence');
        clearShift();
        i += 1;
        continue;
      }

      if (state.utf7Base64Bits >= 6 || state.utf7Base64Buffer != 0) {
        appendError(
          ch,
          state.utf7ShiftStart,
          state.utf7Base64Bits >= 6
              ? 'partial character in shift sequence'
              : 'non-zero padding bits in shift sequence',
        );
        clearShift();
        i += 1;
        continue;
      }
      final int? high = state.utf7PendingHighSurrogate;
      clearShift();
      if (high != null && _isUtf7DecodeDirect(ch)) {
        out.writeCharCode(high);
      }
      if (ch == 0x2D) {
        i += 1;
      }
      continue;
    }

    if (ch == 0x2B) {
      state.utf7InShift = true;
      state.utf7ShiftHasBase64 = false;
      state.utf7Base64Bits = 0;
      state.utf7Base64Buffer = 0;
      state.utf7PendingHighSurrogate = null;
      state.utf7ShiftStart = position;
      i += 1;
      continue;
    }
    if (_isUtf7DecodeDirect(ch)) {
      out.writeCharCode(ch);
      i += 1;
      continue;
    }
    appendError(ch, position, 'unexpected special character');
    i += 1;
  }

  state.utf7ProcessedBytes += chunk.length;
  if (finalChunk && state.utf7InShift) {
    final bool inconsistent =
        state.utf7PendingHighSurrogate != null ||
        state.utf7Base64Bits >= 6 ||
        (state.utf7Base64Bits > 0 && state.utf7Base64Buffer != 0);
    if (inconsistent) {
      appendError(0x2B, state.utf7ShiftStart, 'unterminated shift sequence');
    }
    clearShift();
  }
  return out.toString();
}

List<int> _encodeUtf7IncrementalChunk(
  String chunk,
  UtfIncrementalEncoderState state, {
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  _validateUtf7EncodeErrorMode(errors);
  final List<int> out = <int>[];

  void appendUnit(int unit) {
    state.utf7Base64Buffer = (state.utf7Base64Buffer << 16) | (unit & 0xFFFF);
    state.utf7Base64Bits += 16;
    while (state.utf7Base64Bits >= 6) {
      out.add(
        _utf7ToBase64(state.utf7Base64Buffer >> (state.utf7Base64Bits - 6)),
      );
      state.utf7Base64Bits -= 6;
      state.utf7Base64Buffer &= (1 << state.utf7Base64Bits) - 1;
    }
  }

  void flushShiftBits() {
    if (state.utf7Base64Bits > 0) {
      out.add(
        _utf7ToBase64(state.utf7Base64Buffer << (6 - state.utf7Base64Bits)),
      );
    }
    state.utf7Base64Bits = 0;
    state.utf7Base64Buffer = 0;
  }

  for (final int unit in chunk.codeUnits) {
    if (state.utf7InShift && _isUtf7EncodeDirect(unit)) {
      flushShiftBits();
      state.utf7InShift = false;
      if (_isUtf7Base64(unit) || unit == 0x2D) {
        out.add(0x2D);
      }
      out.add(unit);
      continue;
    }
    if (state.utf7InShift) {
      appendUnit(unit);
      continue;
    }
    if (unit == 0x2B) {
      out.addAll(const <int>[0x2B, 0x2D]);
      continue;
    }
    if (_isUtf7EncodeDirect(unit)) {
      out.add(unit);
      continue;
    }
    out.add(0x2B);
    state.utf7InShift = true;
    appendUnit(unit);
  }

  if (finalChunk) {
    if (state.utf7InShift) {
      flushShiftBits();
      out.add(0x2D);
      state.utf7InShift = false;
    }
  }
  return out;
}

String _decodeUtf7(List<int> bytes, {required CodecErrorMode errors}) {
  if (bytes.isEmpty) {
    return '';
  }
  final StringBuffer out = StringBuffer();
  bool inShift = false;
  int shiftStart = 0;
  int base64Bits = 0;
  int base64Buffer = 0;
  int? pendingHighSurrogate;

  void handleError(int start, int end, String reason) {
    final bool handled = _handleUtf7DecodeError(
      bytes,
      out,
      start: start,
      end: end,
      errors: errors,
    );
    if (!handled) {
      throw CodecException(
        encoding: 'utf-7',
        operation: CodecOperation.decode,
        position: start,
        reason: reason,
      );
    }
  }

  int i = 0;
  while (i < bytes.length) {
    final int ch = bytes[i] & 0xFF;
    if (inShift) {
      if (_isUtf7Base64(ch)) {
        base64Buffer = (base64Buffer << 6) | _utf7FromBase64(ch);
        base64Bits += 6;
        i++;
        while (base64Bits >= 16) {
          final int unit = (base64Buffer >> (base64Bits - 16)) & 0xFFFF;
          base64Bits -= 16;
          base64Buffer &= (1 << base64Bits) - 1;
          if (pendingHighSurrogate != null) {
            if (_isLowSurrogate(unit)) {
              out.writeCharCode(_joinSurrogates(pendingHighSurrogate, unit));
              pendingHighSurrogate = null;
              continue;
            }
            out.writeCharCode(pendingHighSurrogate);
            pendingHighSurrogate = null;
          }
          if (_isHighSurrogate(unit)) {
            pendingHighSurrogate = unit;
          } else {
            out.writeCharCode(unit);
          }
        }
        continue;
      }

      inShift = false;
      if (base64Bits > 0) {
        if (base64Bits >= 6) {
          handleError(shiftStart, i + 1, 'partial character in shift sequence');
          i += 1;
          base64Bits = 0;
          base64Buffer = 0;
          pendingHighSurrogate = null;
          continue;
        }
        if (base64Buffer != 0) {
          handleError(
            shiftStart,
            i + 1,
            'non-zero padding bits in shift sequence',
          );
          i += 1;
          base64Bits = 0;
          base64Buffer = 0;
          pendingHighSurrogate = null;
          continue;
        }
      }
      if (pendingHighSurrogate != null && _isUtf7DecodeDirect(ch)) {
        out.writeCharCode(pendingHighSurrogate);
      }
      pendingHighSurrogate = null;
      base64Bits = 0;
      base64Buffer = 0;
      if (ch == 0x2D) {
        i += 1;
      }
      continue;
    }

    if (ch == 0x2B) {
      shiftStart = i;
      i += 1;
      if (i < bytes.length && (bytes[i] & 0xFF) == 0x2D) {
        i += 1;
        out.writeCharCode(0x2B);
        continue;
      }
      if (i < bytes.length && !_isUtf7Base64(bytes[i] & 0xFF)) {
        handleError(shiftStart, i + 1, 'ill-formed sequence');
        i += 1;
        continue;
      }
      inShift = true;
      base64Bits = 0;
      base64Buffer = 0;
      pendingHighSurrogate = null;
      continue;
    }

    if (_isUtf7DecodeDirect(ch)) {
      out.writeCharCode(ch);
      i += 1;
      continue;
    }

    handleError(i, i + 1, 'unexpected special character');
    i += 1;
  }

  if (inShift) {
    final bool inconsistent =
        pendingHighSurrogate != null ||
        base64Bits >= 6 ||
        (base64Bits > 0 && base64Buffer != 0);
    if (inconsistent) {
      handleError(shiftStart, bytes.length, 'unterminated shift sequence');
    }
  }
  return out.toString();
}

List<int> _encodeUtf7(String text, {required CodecErrorMode errors}) {
  // UTF-7 can encode all code units, including lone surrogates.
  _validateUtf7EncodeErrorMode(errors);
  final List<int> out = <int>[];
  bool inShift = false;
  int base64Bits = 0;
  int base64Buffer = 0;

  void encodeUtf16Unit(int unit) {
    base64Bits += 16;
    base64Buffer = (base64Buffer << 16) | (unit & 0xFFFF);
    while (base64Bits >= 6) {
      out.add(_utf7ToBase64(base64Buffer >> (base64Bits - 6)));
      base64Bits -= 6;
      base64Buffer &= (1 << base64Bits) - 1;
    }
  }

  void encodeScalar(int cp) {
    if (cp >= 0x10000) {
      final int scalar = cp - 0x10000;
      encodeUtf16Unit(0xD800 | (scalar >> 10));
      encodeUtf16Unit(0xDC00 | (scalar & 0x3FF));
      return;
    }
    encodeUtf16Unit(cp);
  }

  for (final int ch in text.runes) {
    if (inShift) {
      if (_isUtf7EncodeDirect(ch)) {
        if (base64Bits > 0) {
          out.add(_utf7ToBase64(base64Buffer << (6 - base64Bits)));
          base64Bits = 0;
          base64Buffer = 0;
        }
        inShift = false;
        if (_isUtf7Base64(ch) || ch == 0x2D) {
          out.add(0x2D);
        }
        out.add(ch);
      } else {
        encodeScalar(ch);
      }
      continue;
    }

    if (ch == 0x2B) {
      out.add(0x2B);
      out.add(0x2D);
      continue;
    }
    if (_isUtf7EncodeDirect(ch)) {
      out.add(ch);
      continue;
    }
    out.add(0x2B);
    inShift = true;
    encodeScalar(ch);
  }

  if (base64Bits > 0) {
    out.add(_utf7ToBase64(base64Buffer << (6 - base64Bits)));
  }
  if (inShift) {
    out.add(0x2D);
  }
  return out;
}

void _validateUtf7EncodeErrorMode(CodecErrorMode errors) {
  switch (errors) {
    case CodecErrorMode.strict:
    case CodecErrorMode.ignore:
    case CodecErrorMode.replace:
    case CodecErrorMode.backslashReplace:
    case CodecErrorMode.xmlCharRefReplace:
    case CodecErrorMode.nameReplace:
    case CodecErrorMode.surrogateEscape:
    case CodecErrorMode.surrogatePass:
      return;
  }
}

bool _handleUtf7DecodeError(
  List<int> bytes,
  StringBuffer out, {
  required int start,
  required int end,
  required CodecErrorMode errors,
}) {
  switch (errors) {
    case CodecErrorMode.strict:
    case CodecErrorMode.surrogatePass:
      return false;
    case CodecErrorMode.ignore:
      return true;
    case CodecErrorMode.replace:
    case CodecErrorMode.xmlCharRefReplace:
    case CodecErrorMode.nameReplace:
      out.writeCharCode(0xFFFD);
      return true;
    case CodecErrorMode.backslashReplace:
      for (int i = start; i < end; i++) {
        out.write(r'\x');
        out.write((bytes[i] & 0xFF).toRadixString(16).padLeft(2, '0'));
      }
      return true;
    case CodecErrorMode.surrogateEscape:
      for (int i = start; i < end; i++) {
        if ((bytes[i] & 0xFF) < 0x80) {
          return false;
        }
      }
      for (int i = start; i < end; i++) {
        out.writeCharCode(0xDC00 + (bytes[i] & 0xFF));
      }
      return true;
  }
}

bool _isUtf7Base64(int ch) {
  return (ch >= 0x41 && ch <= 0x5A) ||
      (ch >= 0x61 && ch <= 0x7A) ||
      (ch >= 0x30 && ch <= 0x39) ||
      ch == 0x2B ||
      ch == 0x2F;
}

int _utf7FromBase64(int ch) {
  if (ch >= 0x41 && ch <= 0x5A) {
    return ch - 0x41;
  }
  if (ch >= 0x61 && ch <= 0x7A) {
    return ch - 0x61 + 26;
  }
  if (ch >= 0x30 && ch <= 0x39) {
    return ch - 0x30 + 52;
  }
  if (ch == 0x2B) {
    return 62;
  }
  return 63;
}

int _utf7ToBase64(int n) {
  return _utf7Base64Alphabet.codeUnitAt(n & 0x3F);
}

bool _isUtf7DecodeDirect(int ch) {
  return ch <= 0x7F && ch != 0x2B;
}

bool _isUtf7EncodeDirect(int ch) {
  if (ch <= 0 || ch >= 0x80) {
    return false;
  }
  if (ch == 0x2B || ch == 0x5C || ch == 0x7E || ch == 0x7F) {
    return false;
  }
  if (ch < 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D) {
    return false;
  }
  return true;
}

bool _isHighSurrogate(int unit) {
  return unit >= 0xD800 && unit <= 0xDBFF;
}

bool _isLowSurrogate(int unit) {
  return unit >= 0xDC00 && unit <= 0xDFFF;
}

int _joinSurrogates(int high, int low) {
  return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
}

String _decodeUtf8(List<int> bytes, {required CodecErrorMode errors}) {
  if (bytes.isEmpty) {
    return '';
  }
  final StringBuffer out = StringBuffer();
  int i = 0;

  while (i < bytes.length) {
    final int b0 = bytes[i] & 0xFF;
    if (b0 < 0x80) {
      out.writeCharCode(b0);
      i += 1;
      continue;
    }

    int needed = 0;
    int minCp = 0;
    int cp = 0;
    if (b0 >= 0xC2 && b0 <= 0xDF) {
      needed = 2;
      minCp = 0x80;
      cp = b0 & 0x1F;
    } else if (b0 >= 0xE0 && b0 <= 0xEF) {
      needed = 3;
      minCp = 0x800;
      cp = b0 & 0x0F;
    } else if (b0 >= 0xF0 && b0 <= 0xF4) {
      needed = 4;
      minCp = 0x10000;
      cp = b0 & 0x07;
    } else {
      _appendUtf8DecodeError(out, bytes, start: i, end: i + 1, errors: errors);
      i += 1;
      continue;
    }

    if (i + needed > bytes.length) {
      if (errors == CodecErrorMode.strict ||
          errors == CodecErrorMode.surrogatePass) {
        throw CodecException(
          encoding: 'utf-8',
          operation: CodecOperation.decode,
          position: i,
          reason: 'unexpected end of data',
        );
      }
      _appendUtf8DecodeError(
        out,
        bytes,
        start: i,
        end: bytes.length,
        errors: errors,
      );
      break;
    }

    bool invalid = false;
    for (int j = 1; j < needed; j++) {
      final int bx = bytes[i + j] & 0xFF;
      if ((bx & 0xC0) != 0x80) {
        invalid = true;
        break;
      }
      cp = (cp << 6) | (bx & 0x3F);
    }
    if (invalid || cp < minCp || cp > 0x10FFFF) {
      _appendUtf8DecodeError(out, bytes, start: i, end: i + 1, errors: errors);
      i += 1;
      continue;
    }

    if (cp >= 0xD800 && cp <= 0xDFFF) {
      if (errors == CodecErrorMode.surrogatePass) {
        out.writeCharCode(cp);
        i += needed;
        continue;
      }
      _appendUtf8DecodeError(out, bytes, start: i, end: i + 1, errors: errors);
      i += 1;
      continue;
    }

    out.write(String.fromCharCode(cp));
    i += needed;
  }
  return out.toString();
}

List<int> _encodeUtf8(String text, {required CodecErrorMode errors}) {
  final List<int> out = <int>[];
  final List<int> units = text.codeUnits;
  int i = 0;
  while (i < units.length) {
    final int unit = units[i];
    if (_isHighSurrogate(unit)) {
      if (i + 1 < units.length && _isLowSurrogate(units[i + 1])) {
        _appendUtf8Scalar(out, _joinSurrogates(unit, units[i + 1]));
        i += 2;
        continue;
      }
      _handleUtf8EncodeSurrogateError(out, unit, i, errors);
      i += 1;
      continue;
    }
    if (_isLowSurrogate(unit)) {
      _handleUtf8EncodeSurrogateError(out, unit, i, errors);
      i += 1;
      continue;
    }
    _appendUtf8Scalar(out, unit);
    i += 1;
  }
  return out;
}

String _decodeUtf16(
  List<int> bytes,
  String encoding, {
  required CodecErrorMode errors,
}) {
  bool littleEndian = true;
  int offset = 0;
  if (encoding == 'utf-16') {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFF) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFE))) {
      throw CodecException(
        encoding: encoding,
        operation: CodecOperation.decode,
        position: 0,
        reason: 'invalid utf-16 BOM',
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      littleEndian = false;
      offset = 2;
    } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      littleEndian = true;
      offset = 2;
    } else {
      littleEndian = true;
    }
  } else {
    littleEndian = encoding == 'utf-16-le';
  }
  final int payload = bytes.length - offset;
  if (payload.isOdd && errors == CodecErrorMode.strict) {
    throw CodecException(
      encoding: encoding,
      operation: CodecOperation.decode,
      position: bytes.length,
      reason: 'utf-16 input has odd byte length',
    );
  }
  final int unitCount = payload ~/ 2;
  final ByteData bd = ByteData.sublistView(
    Uint8List.fromList(bytes.sublist(offset, offset + unitCount * 2)),
  );
  final StringBuffer sb = StringBuffer();
  int i = 0;
  while (i < unitCount) {
    final int pos = offset + i * 2;
    final int unit = bd.getUint16(
      i * 2,
      littleEndian ? Endian.little : Endian.big,
    );
    if (_isHighSurrogate(unit)) {
      if (i + 1 < unitCount) {
        final int next = bd.getUint16(
          (i + 1) * 2,
          littleEndian ? Endian.little : Endian.big,
        );
        if (_isLowSurrogate(next)) {
          sb.write(String.fromCharCode(_joinSurrogates(unit, next)));
          i += 2;
          continue;
        }
      }
      if (errors == CodecErrorMode.strict) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: pos,
          reason: 'unexpected end of data',
        );
      }
      if (errors == CodecErrorMode.ignore) {
        i += 1;
        continue;
      }
      if (errors == CodecErrorMode.surrogatePass) {
        sb.writeCharCode(unit);
      } else {
        sb.writeCharCode(0xFFFD);
      }
      i += 1;
      continue;
    }
    if (_isLowSurrogate(unit)) {
      if (errors == CodecErrorMode.strict) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: pos,
          reason: 'unexpected end of data',
        );
      }
      if (errors == CodecErrorMode.ignore) {
        i += 1;
        continue;
      }
      if (errors == CodecErrorMode.surrogatePass) {
        sb.writeCharCode(unit);
      } else {
        sb.writeCharCode(0xFFFD);
      }
      i += 1;
      continue;
    }
    sb.writeCharCode(unit);
    i += 1;
  }
  if (payload.isOdd) {
    if (errors == CodecErrorMode.replace ||
        errors == CodecErrorMode.xmlCharRefReplace ||
        errors == CodecErrorMode.nameReplace ||
        errors == CodecErrorMode.surrogatePass) {
      sb.writeCharCode(0xFFFD);
    } else if (errors == CodecErrorMode.backslashReplace) {
      final int b = bytes.last & 0xFF;
      sb.write(r'\x');
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    } else if (errors == CodecErrorMode.surrogateEscape) {
      final int b = bytes.last & 0xFF;
      if (b >= 0x80) {
        sb.writeCharCode(0xDC00 + b);
      } else {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: bytes.length - 1,
          reason: 'utf-16 input has odd byte length',
        );
      }
    }
  }
  return sb.toString();
}

String _decodeUtf32(
  List<int> bytes,
  String encoding, {
  required CodecErrorMode errors,
}) {
  bool littleEndian = true;
  int offset = 0;
  if (encoding == 'utf-32') {
    if (bytes.length >= 4 &&
        bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        bytes[2] == 0xFE &&
        bytes[3] == 0xFF) {
      littleEndian = false;
      offset = 4;
    } else if (bytes.length >= 4 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xFE &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x00) {
      littleEndian = true;
      offset = 4;
    }
  } else {
    littleEndian = encoding == 'utf-32-le';
  }
  final int payload = bytes.length - offset;
  if (payload % 4 != 0 && errors == CodecErrorMode.strict) {
    throw CodecException(
      encoding: encoding,
      operation: CodecOperation.decode,
      position: bytes.length,
      reason: 'utf-32 input length is not divisible by 4',
    );
  }
  final int usableBytes = (payload ~/ 4) * 4;
  final ByteData bd = ByteData.sublistView(
    Uint8List.fromList(bytes.sublist(offset, offset + usableBytes)),
  );
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < usableBytes; i += 4) {
    final int cp = bd.getUint32(i, littleEndian ? Endian.little : Endian.big);
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
      if (errors == CodecErrorMode.strict) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.decode,
          position: i + offset,
          reason: 'invalid unicode scalar in utf-32 input',
        );
      }
      if (errors == CodecErrorMode.ignore) {
        continue;
      }
      if (errors == CodecErrorMode.surrogatePass &&
          cp >= 0xD800 &&
          cp <= 0xDFFF) {
        sb.writeCharCode(cp);
        continue;
      }
      sb.writeCharCode(0xFFFD);
      continue;
    }
    sb.write(String.fromCharCode(cp));
  }
  if (usableBytes != payload && errors == CodecErrorMode.replace) {
    sb.writeCharCode(0xFFFD);
  }
  return sb.toString();
}

List<int> _encodeUtf16(
  String text,
  String encoding, {
  required CodecErrorMode errors,
}) {
  final bool withBom = encoding == 'utf-16';
  final bool littleEndian = encoding != 'utf-16-be';
  final List<int> out = <int>[];
  if (withBom) {
    out.addAll(littleEndian ? <int>[0xFF, 0xFE] : <int>[0xFE, 0xFF]);
  }
  final List<int> units = text.codeUnits;
  int i = 0;
  while (i < units.length) {
    final int unit = units[i];
    if (_isHighSurrogate(unit)) {
      if (i + 1 < units.length && _isLowSurrogate(units[i + 1])) {
        if (littleEndian) {
          out.add(unit & 0xFF);
          out.add((unit >> 8) & 0xFF);
          out.add(units[i + 1] & 0xFF);
          out.add((units[i + 1] >> 8) & 0xFF);
        } else {
          out.add((unit >> 8) & 0xFF);
          out.add(unit & 0xFF);
          out.add((units[i + 1] >> 8) & 0xFF);
          out.add(units[i + 1] & 0xFF);
        }
        i += 2;
        continue;
      }
      if (!_appendUtf16EncodeError(
        out,
        unit,
        encoding,
        i,
        errors,
        littleEndian: littleEndian,
      )) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.encode,
          position: i,
          reason: 'input contains invalid surrogate sequence',
        );
      }
      i += 1;
      continue;
    }
    if (_isLowSurrogate(unit)) {
      if (!_appendUtf16EncodeError(
        out,
        unit,
        encoding,
        i,
        errors,
        littleEndian: littleEndian,
      )) {
        throw CodecException(
          encoding: encoding,
          operation: CodecOperation.encode,
          position: i,
          reason: 'input contains invalid surrogate sequence',
        );
      }
      i += 1;
      continue;
    }
    if (littleEndian) {
      out.add(unit & 0xFF);
      out.add((unit >> 8) & 0xFF);
    } else {
      out.add((unit >> 8) & 0xFF);
      out.add(unit & 0xFF);
    }
    i += 1;
  }
  return out;
}

List<int> _encodeUtf32(
  String text,
  String encoding, {
  required CodecErrorMode errors,
}) {
  final bool withBom = encoding == 'utf-32';
  final bool littleEndian = encoding != 'utf-32-be';
  final List<int> out = <int>[];
  if (withBom) {
    out.addAll(
      littleEndian
          ? <int>[0xFF, 0xFE, 0x00, 0x00]
          : <int>[0x00, 0x00, 0xFE, 0xFF],
    );
  }
  final List<int> units = text.codeUnits;
  int i = 0;
  while (i < units.length) {
    final int unit = units[i];
    int? cp;
    if (_isHighSurrogate(unit)) {
      if (i + 1 < units.length && _isLowSurrogate(units[i + 1])) {
        cp = _joinSurrogates(unit, units[i + 1]);
        i += 2;
      } else {
        cp = _coerceUtf32Surrogate(unit, encoding, i, errors);
        i += 1;
      }
    } else if (_isLowSurrogate(unit)) {
      cp = _coerceUtf32Surrogate(unit, encoding, i, errors);
      i += 1;
    } else {
      cp = unit;
      i += 1;
    }
    if (cp == null) {
      continue;
    }
    if (littleEndian) {
      out.add(cp & 0xFF);
      out.add((cp >> 8) & 0xFF);
      out.add((cp >> 16) & 0xFF);
      out.add((cp >> 24) & 0xFF);
    } else {
      out.add((cp >> 24) & 0xFF);
      out.add((cp >> 16) & 0xFF);
      out.add((cp >> 8) & 0xFF);
      out.add(cp & 0xFF);
    }
  }
  return out;
}

void _appendUtf8DecodeError(
  StringBuffer out,
  List<int> bytes, {
  required int start,
  required int end,
  required CodecErrorMode errors,
}) {
  if (errors == CodecErrorMode.strict ||
      errors == CodecErrorMode.surrogatePass) {
    throw CodecException(
      encoding: 'utf-8',
      operation: CodecOperation.decode,
      position: start,
      reason: 'invalid utf-8 sequence',
    );
  }
  switch (errors) {
    case CodecErrorMode.ignore:
      return;
    case CodecErrorMode.replace:
    case CodecErrorMode.xmlCharRefReplace:
    case CodecErrorMode.nameReplace:
      out.writeCharCode(0xFFFD);
      return;
    case CodecErrorMode.backslashReplace:
      for (int i = start; i < end; i++) {
        out.write(r'\x');
        out.write((bytes[i] & 0xFF).toRadixString(16).padLeft(2, '0'));
      }
      return;
    case CodecErrorMode.surrogateEscape:
      for (int i = start; i < end; i++) {
        final int b = bytes[i] & 0xFF;
        if (b < 0x80) {
          throw CodecException(
            encoding: 'utf-8',
            operation: CodecOperation.decode,
            position: i,
            reason: 'invalid utf-8 sequence',
          );
        }
        out.writeCharCode(0xDC00 + b);
      }
      return;
    case CodecErrorMode.strict:
    case CodecErrorMode.surrogatePass:
      return;
  }
}

void _appendUtf8Scalar(List<int> out, int cp) {
  if (cp <= 0x7F) {
    out.add(cp);
    return;
  }
  if (cp <= 0x7FF) {
    out.add(0xC0 | (cp >> 6));
    out.add(0x80 | (cp & 0x3F));
    return;
  }
  if (cp <= 0xFFFF) {
    out.add(0xE0 | (cp >> 12));
    out.add(0x80 | ((cp >> 6) & 0x3F));
    out.add(0x80 | (cp & 0x3F));
    return;
  }
  out.add(0xF0 | (cp >> 18));
  out.add(0x80 | ((cp >> 12) & 0x3F));
  out.add(0x80 | ((cp >> 6) & 0x3F));
  out.add(0x80 | (cp & 0x3F));
}

void _handleUtf8EncodeSurrogateError(
  List<int> out,
  int surrogate,
  int position,
  CodecErrorMode errors,
) {
  switch (errors) {
    case CodecErrorMode.ignore:
      return;
    case CodecErrorMode.replace:
      _appendUtf8Scalar(out, 0xFFFD);
      return;
    case CodecErrorMode.backslashReplace:
      out.addAll(_asciiEscape(surrogate, lowercaseHex: true));
      return;
    case CodecErrorMode.xmlCharRefReplace:
      out.addAll('&#$surrogate;'.codeUnits);
      return;
    case CodecErrorMode.nameReplace:
      out.addAll(r'\N{U+'.codeUnits);
      out.addAll(surrogate.toRadixString(16).toUpperCase().codeUnits);
      out.addAll('}'.codeUnits);
      return;
    case CodecErrorMode.surrogateEscape:
      if (surrogate >= 0xDC80 && surrogate <= 0xDCFF) {
        out.add(surrogate - 0xDC00);
        return;
      }
      throw CodecException(
        encoding: 'utf-8',
        operation: CodecOperation.encode,
        position: position,
        reason: 'input contains invalid surrogate sequence',
      );
    case CodecErrorMode.surrogatePass:
      _appendUtf8Scalar(out, surrogate);
      return;
    case CodecErrorMode.strict:
      throw CodecException(
        encoding: 'utf-8',
        operation: CodecOperation.encode,
        position: position,
        reason: 'input contains invalid surrogate sequence',
      );
  }
}

bool _appendUtf16EncodeError(
  List<int> out,
  int unit,
  String encoding,
  int position,
  CodecErrorMode errors, {
  required bool littleEndian,
}) {
  switch (errors) {
    case CodecErrorMode.ignore:
      return true;
    case CodecErrorMode.replace:
    case CodecErrorMode.xmlCharRefReplace:
    case CodecErrorMode.nameReplace:
    case CodecErrorMode.backslashReplace:
      _appendUtf16Unit(out, 0xFFFD, littleEndian: littleEndian);
      return true;
    case CodecErrorMode.surrogatePass:
      _appendUtf16Unit(out, unit, littleEndian: littleEndian);
      return true;
    case CodecErrorMode.surrogateEscape:
      throw CodecException(
        encoding: encoding,
        operation: CodecOperation.encode,
        position: position,
        reason: 'input contains invalid surrogate sequence',
      );
    case CodecErrorMode.strict:
      return false;
  }
}

void _appendUtf16Unit(List<int> out, int unit, {required bool littleEndian}) {
  if (littleEndian) {
    out.add(unit & 0xFF);
    out.add((unit >> 8) & 0xFF);
  } else {
    out.add((unit >> 8) & 0xFF);
    out.add(unit & 0xFF);
  }
}

int? _coerceUtf32Surrogate(
  int surrogate,
  String encoding,
  int position,
  CodecErrorMode errors,
) {
  switch (errors) {
    case CodecErrorMode.strict:
      throw CodecException(
        encoding: encoding,
        operation: CodecOperation.encode,
        position: position,
        reason: 'input contains invalid surrogate sequence',
      );
    case CodecErrorMode.ignore:
      return null;
    case CodecErrorMode.replace:
    case CodecErrorMode.xmlCharRefReplace:
    case CodecErrorMode.nameReplace:
    case CodecErrorMode.backslashReplace:
      return 0xFFFD;
    case CodecErrorMode.surrogateEscape:
      throw CodecException(
        encoding: encoding,
        operation: CodecOperation.encode,
        position: position,
        reason: 'input contains invalid surrogate sequence',
      );
    case CodecErrorMode.surrogatePass:
      return surrogate;
  }
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
