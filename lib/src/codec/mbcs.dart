// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import '../codec_types.dart';
import '../generated/codec_mbcs_data.g.dart';
import 'data_loader.dart';
import 'resolver.dart';

bool _isTableBacked(ResolvedCodec codec) {
  return generatedMbcsTableFamilyIndexByCodecId[codec.codecId] >= 0;
}

bool _isStatefulBacked(ResolvedCodec codec) {
  return generatedMbcsStatefulFamilyIndexByCodecId[codec.codecId] >= 0;
}

bool _isImplemented(ResolvedCodec codec) {
  return _isTableBacked(codec) || _isStatefulBacked(codec);
}

bool supportsIncrementalMultibyteDecode(ResolvedCodec codec) {
  return _isTableBacked(codec);
}

final class StatefulMultibyteDecoderState {
  StatefulMultibyteDecoderState(ResolvedCodec codec)
    : codecId = codec.codecId,
      pendingBytes = <int>[];

  StatefulMultibyteDecoderState.copy(StatefulMultibyteDecoderState other)
    : codecId = other.codecId,
      pendingBytes = List<int>.from(other.pendingBytes),
      hzInGb = other.hzInGb,
      krDesignated = other.krDesignated,
      krShifted = other.krShifted,
      isoEscThroughout = other.isoEscThroughout,
      isoG0 = other.isoG0,
      isoG2 = other.isoG2;

  final int codecId;
  final List<int> pendingBytes;
  bool hzInGb = false;
  bool krDesignated = false;
  bool krShifted = false;
  bool isoEscThroughout = false;
  String isoG0 = 'ascii';
  String isoG2 = 'ascii';
}

final class StatefulMultibyteEncoderState {
  StatefulMultibyteEncoderState(ResolvedCodec codec) : codecId = codec.codecId;

  StatefulMultibyteEncoderState.copy(StatefulMultibyteEncoderState other)
    : codecId = other.codecId,
      pendingScalar = other.pendingScalar,
      hzInGb = other.hzInGb,
      krDesignated = other.krDesignated,
      krShifted = other.krShifted,
      isoG0 = other.isoG0,
      isoG2 = other.isoG2;

  final int codecId;
  String pendingScalar = '';
  bool hzInGb = false;
  bool krDesignated = false;
  bool krShifted = false;
  String isoG0 = 'ascii';
  String isoG2 = 'ascii';
}

String decodeStatefulMultibyteIncrementalChunk(
  List<int> chunk,
  ResolvedCodec codec,
  StatefulMultibyteDecoderState state, {
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  if (state.codecId != codec.codecId) {
    throw ArgumentError('Incremental decoder state does not match the codec');
  }
  final List<int> bytes = <int>[...state.pendingBytes, ...chunk];
  state.pendingBytes.clear();
  if (bytes.isEmpty) {
    return '';
  }

  if (codec.canonicalName == 'gb18030') {
    final int split = finalChunk ? bytes.length : _gb18030NonFinalSplit(bytes);
    final String out = split == 0
        ? ''
        : _decodeGb18030(bytes.sublist(0, split), codec, errors: errors);
    if (split < bytes.length) {
      state.pendingBytes.addAll(bytes.sublist(split));
    }
    return out;
  }

  final StringBuffer out = StringBuffer();
  int start = 0;
  if (codec.canonicalName.startsWith('iso2022-jp') ||
      codec.canonicalName == 'iso-2022-jp') {
    while (state.isoEscThroughout && start < bytes.length) {
      final int byte = bytes[start] & 0xFF;
      out.writeCharCode(byte);
      start += 1;
      if (_isEscEndByte(byte)) {
        state.isoEscThroughout = false;
      }
    }
    if (state.isoEscThroughout) {
      return out.toString();
    }
  }

  final List<int> remaining = bytes.sublist(start);
  final List<int> prefix = _statefulDecodePrefix(codec, state);
  final int split = finalChunk
      ? remaining.length
      : _statefulStrictNonFinalSplit(remaining, prefix, codec);
  if (split > 0) {
    out.write(
      decodeMultibyte(
        <int>[...prefix, ...remaining.sublist(0, split)],
        codec,
        errors: errors,
      ),
    );
    _scanStatefulDecodeState(remaining.sublist(0, split), codec, state);
  }
  if (split < remaining.length) {
    state.pendingBytes.addAll(remaining.sublist(split));
  }
  return out.toString();
}

List<int> encodeStatefulMultibyteIncrementalChunk(
  String chunk,
  ResolvedCodec codec,
  StatefulMultibyteEncoderState state, {
  required CodecErrorMode errors,
  required bool finalChunk,
}) {
  if (state.codecId != codec.codecId) {
    throw ArgumentError('Incremental encoder state does not match the codec');
  }
  String text = state.pendingScalar + chunk;
  state.pendingScalar = '';
  final int trailingUnit = text.isEmpty ? 0 : text.codeUnitAt(text.length - 1);
  if (!finalChunk && trailingUnit >= 0xD800 && trailingUnit <= 0xDBFF) {
    state.pendingScalar = text.substring(text.length - 1);
    text = text.substring(0, text.length - 1);
  }

  if (codec.canonicalName == 'gb18030') {
    if (text.isEmpty) {
      return const <int>[];
    }
    return _encodeGb18030(text, codec, errors: errors);
  }
  if (codec.canonicalName == 'hz-gb-2312') {
    return _encodeHzIncremental(text, codec, state, errors, finalChunk);
  }
  if (codec.canonicalName == 'iso-2022-kr') {
    return _encodeIso2022KrIncremental(text, codec, state, errors, finalChunk);
  }
  return _encodeIso2022JpIncremental(text, codec, state, errors, finalChunk);
}

void resetStatefulMultibyteDecoderState(StatefulMultibyteDecoderState state) {
  state.pendingBytes.clear();
  state.hzInGb = false;
  state.krDesignated = false;
  state.krShifted = false;
  state.isoEscThroughout = false;
  state.isoG0 = 'ascii';
  state.isoG2 = 'ascii';
}

void resetStatefulMultibyteEncoderState(StatefulMultibyteEncoderState state) {
  state.pendingScalar = '';
  state.hzInGb = false;
  state.krDesignated = false;
  state.krShifted = false;
  state.isoG0 = 'ascii';
  state.isoG2 = 'ascii';
}

int _gb18030NonFinalSplit(List<int> bytes) {
  int i = 0;
  while (i < bytes.length) {
    final int b1 = bytes[i] & 0xFF;
    if (b1 < 0x81 || b1 > 0xFE) {
      i += 1;
      continue;
    }
    if (i + 1 >= bytes.length) {
      break;
    }
    final int b2 = bytes[i + 1] & 0xFF;
    if (b2 >= 0x30 && b2 <= 0x39) {
      if (i + 3 >= bytes.length) {
        break;
      }
      i += 4;
    } else {
      i += 2;
    }
  }
  return i;
}

List<int> _statefulDecodePrefix(
  ResolvedCodec codec,
  StatefulMultibyteDecoderState state,
) {
  if (codec.canonicalName == 'hz-gb-2312') {
    return state.hzInGb ? const <int>[0x7E, 0x7B] : const <int>[];
  }
  if (codec.canonicalName == 'iso-2022-kr') {
    return <int>[
      if (state.krDesignated) ...const <int>[0x1B, 0x24, 0x29, 0x43],
      if (state.krShifted) 0x0E,
    ];
  }
  return <int>[
    if (state.isoG2 != 'ascii')
      ...?generatedIso2022SetDesignationEscapes[state.isoG2],
    if (state.isoG0 != 'ascii')
      ...?generatedIso2022SetDesignationEscapes[state.isoG0],
  ];
}

int _statefulStrictNonFinalSplit(
  List<int> bytes,
  List<int> prefix,
  ResolvedCodec codec,
) {
  if (bytes.isEmpty) {
    return 0;
  }
  try {
    decodeMultibyte(
      <int>[...prefix, ...bytes],
      codec,
      errors: CodecErrorMode.strict,
    );
    return bytes.length;
  } on CodecException catch (error) {
    if (!error.reason.toLowerCase().contains('incomplete')) {
      return bytes.length;
    }
    final int split = error.position - prefix.length;
    if (split <= 0) {
      return 0;
    }
    return split >= bytes.length ? bytes.length : split;
  }
}

void _scanStatefulDecodeState(
  List<int> bytes,
  ResolvedCodec codec,
  StatefulMultibyteDecoderState state,
) {
  if (codec.canonicalName == 'hz-gb-2312') {
    _scanHzState(bytes, state);
    return;
  }
  if (codec.canonicalName == 'iso-2022-kr') {
    _scanIso2022KrState(bytes, state);
    return;
  }
  _scanIso2022JpState(bytes, codec, state);
}

void _scanHzState(List<int> bytes, StatefulMultibyteDecoderState state) {
  int i = 0;
  while (i < bytes.length) {
    final int byte = bytes[i] & 0xFF;
    if (byte == 0x7E && i + 1 < bytes.length) {
      final int next = bytes[i + 1] & 0xFF;
      if (next == 0x7B) {
        state.hzInGb = true;
      } else if (next == 0x7D) {
        state.hzInGb = false;
      }
      i += next == 0x0D && i + 2 < bytes.length && (bytes[i + 2] & 0xFF) == 0x0A
          ? 3
          : 2;
      continue;
    }
    i += state.hzInGb ? 2 : 1;
  }
}

void _scanIso2022KrState(List<int> bytes, StatefulMultibyteDecoderState state) {
  int i = 0;
  while (i < bytes.length) {
    final int byte = bytes[i] & 0xFF;
    if (byte == 0x1B &&
        i + 3 < bytes.length &&
        (bytes[i + 1] & 0xFF) == 0x24 &&
        (bytes[i + 2] & 0xFF) == 0x29 &&
        (bytes[i + 3] & 0xFF) == 0x43) {
      state.krDesignated = true;
      i += 4;
      continue;
    }
    if (byte == 0x0E) {
      state.krShifted = true;
      i += 1;
      continue;
    }
    if (byte == 0x0F) {
      state.krShifted = false;
      i += 1;
      continue;
    }
    i += state.krShifted ? 2 : 1;
  }
}

void _scanIso2022JpState(
  List<int> bytes,
  ResolvedCodec codec,
  StatefulMultibyteDecoderState state,
) {
  int i = 0;
  while (i < bytes.length) {
    final int byte = bytes[i] & 0xFF;
    if (state.isoEscThroughout) {
      if (_isEscEndByte(byte)) {
        state.isoEscThroughout = false;
      }
      i += 1;
      continue;
    }
    if (byte == 0x1B) {
      if (i + 2 < bytes.length &&
          codec.canonicalName == 'iso2022-jp-2' &&
          (bytes[i + 1] & 0xFF) == 0x4E) {
        i += 3;
        continue;
      }
      final ({String setId, String mode, int length})? designation =
          _matchIso2022Designation(bytes, i);
      if (designation != null) {
        if (designation.mode == 'g2') {
          state.isoG2 = designation.setId;
        } else {
          state.isoG0 = designation.setId;
        }
        i += designation.length;
        continue;
      }
      state.isoEscThroughout = true;
      i += 1;
      continue;
    }
    final int width = state.isoG0 == 'ascii'
        ? 1
        : (generatedIso2022SetWidths[state.isoG0] ?? 1);
    i += width;
  }
}

({String setId, String mode, int length})? _matchIso2022Designation(
  List<int> bytes,
  int offset,
) {
  if (_matchesAt(bytes, offset, const <int>[0x1B, 0x28, 0x42])) {
    return (setId: 'ascii', mode: 'g0', length: 3);
  }
  for (final MapEntry<String, List<int>> entry
      in generatedIso2022SetDesignationEscapes.entries) {
    if (_matchesAt(bytes, offset, entry.value)) {
      return (
        setId: entry.key,
        mode: generatedIso2022SetModes[entry.key] ?? 'g0',
        length: entry.value.length,
      );
    }
  }
  return null;
}

bool _matchesAt(List<int> bytes, int offset, List<int> pattern) {
  if (offset + pattern.length > bytes.length) {
    return false;
  }
  for (int i = 0; i < pattern.length; i++) {
    if ((bytes[offset + i] & 0xFF) != pattern[i]) {
      return false;
    }
  }
  return true;
}

List<int> _encodeHzIncremental(
  String text,
  ResolvedCodec codec,
  StatefulMultibyteEncoderState state,
  CodecErrorMode errors,
  bool finalChunk,
) {
  final bool wasInGb = state.hzInGb;
  final List<int> out = text.isEmpty
      ? <int>[]
      : List<int>.from(_encodeHz(text, codec, errors: errors));
  final bool chunkEndsInGb =
      out.length >= 2 && out[out.length - 2] == 0x7E && out.last == 0x7D;

  if (wasInGb && out.isNotEmpty) {
    if (out.length >= 2 && out[0] == 0x7E && out[1] == 0x7B) {
      out.removeRange(0, 2);
    } else {
      out.insertAll(0, const <int>[0x7E, 0x7D]);
    }
  }
  if (!finalChunk && chunkEndsInGb) {
    out.removeRange(out.length - 2, out.length);
    state.hzInGb = true;
  } else if (out.isEmpty && !finalChunk) {
    state.hzInGb = wasInGb;
  } else {
    state.hzInGb = false;
  }
  if (finalChunk && out.isEmpty && wasInGb) {
    out.addAll(const <int>[0x7E, 0x7D]);
    state.hzInGb = false;
  }
  return out;
}

List<int> _encodeIso2022KrIncremental(
  String text,
  ResolvedCodec codec,
  StatefulMultibyteEncoderState state,
  CodecErrorMode errors,
  bool finalChunk,
) {
  const List<int> designation = <int>[0x1B, 0x24, 0x29, 0x43];
  final bool wasDesignated = state.krDesignated;
  final bool wasShifted = state.krShifted;
  final List<int> out = text.isEmpty
      ? <int>[]
      : List<int>.from(_encodeIso2022Kr(text, codec, errors: errors));
  final int designationOffset = _indexOfPattern(out, designation);
  final bool chunkDesignates = designationOffset >= 0;
  if (wasDesignated && designationOffset >= 0) {
    out.removeRange(designationOffset, designationOffset + designation.length);
  }

  if (wasShifted && out.isNotEmpty) {
    if (out.first == 0x0E) {
      out.removeAt(0);
    } else {
      out.insert(0, 0x0F);
    }
  }
  final bool chunkEndsShifted = out.isNotEmpty && out.last == 0x0F;
  if (!finalChunk && chunkEndsShifted) {
    out.removeLast();
    state.krShifted = true;
  } else if (out.isEmpty && !finalChunk) {
    state.krShifted = wasShifted;
  } else {
    state.krShifted = false;
  }
  state.krDesignated = wasDesignated || chunkDesignates;
  if (finalChunk) {
    if (out.isEmpty && wasShifted) {
      out.add(0x0F);
    }
    state.krDesignated = false;
    state.krShifted = false;
  }
  return out;
}

List<int> _encodeIso2022JpIncremental(
  String text,
  ResolvedCodec codec,
  StatefulMultibyteEncoderState state,
  CodecErrorMode errors,
  bool finalChunk,
) {
  const List<int> asciiReset = <int>[0x1B, 0x28, 0x42];
  final List<int> encoded = text.isEmpty
      ? <int>[]
      : List<int>.from(_encodeIso2022JpFamily(text, codec, errors: errors));
  final bool hasTerminalReset =
      encoded.length >= asciiReset.length &&
      _matchesAt(encoded, encoded.length - asciiReset.length, asciiReset);
  if (!finalChunk && hasTerminalReset) {
    encoded.removeRange(encoded.length - asciiReset.length, encoded.length);
  }

  final List<int> out = <int>[];
  int i = 0;
  if (state.isoG0 != 'ascii' && encoded.isNotEmpty) {
    final bool beginsWithDesignation =
        _matchIso2022Designation(encoded, 0) != null;
    final bool beginsWithSingleShift =
        encoded.length >= 2 && encoded[0] == 0x1B && encoded[1] == 0x4E;
    if (!beginsWithDesignation && !beginsWithSingleShift) {
      out.addAll(asciiReset);
      state.isoG0 = 'ascii';
    }
  }

  while (i < encoded.length) {
    final ({String setId, String mode, int length})? designation =
        _matchIso2022Designation(encoded, i);
    if (designation != null) {
      final String current = designation.mode == 'g2'
          ? state.isoG2
          : state.isoG0;
      if (current != designation.setId) {
        out.addAll(encoded.sublist(i, i + designation.length));
        if (designation.mode == 'g2') {
          state.isoG2 = designation.setId;
        } else {
          state.isoG0 = designation.setId;
        }
      }
      i += designation.length;
      continue;
    }
    if (i + 1 < encoded.length &&
        encoded[i] == 0x1B &&
        encoded[i + 1] == 0x4E) {
      final int end = i + 3 < encoded.length ? i + 3 : encoded.length;
      out.addAll(encoded.sublist(i, end));
      i = end;
      continue;
    }
    out.add(encoded[i]);
    i += 1;
  }

  if (finalChunk) {
    if (out.isEmpty && state.isoG0 != 'ascii') {
      out.addAll(asciiReset);
    }
    state.isoG0 = 'ascii';
    state.isoG2 = 'ascii';
  }
  return out;
}

int _indexOfPattern(List<int> bytes, List<int> pattern) {
  if (pattern.isEmpty) {
    return 0;
  }
  for (int i = 0; i + pattern.length <= bytes.length; i++) {
    if (_matchesAt(bytes, i, pattern)) {
      return i;
    }
  }
  return -1;
}

bool validateMultibyteData(List<int> bytes, ResolvedCodec codec) {
  if (!_isImplemented(codec)) {
    return false;
  }
  if (_isTableBacked(codec)) {
    return _validateTableBackedMultibyte(bytes, codec);
  }
  if (codec.canonicalName == 'gb18030') {
    return _validateGb18030(bytes);
  }
  try {
    decodeMultibyte(bytes, codec, errors: CodecErrorMode.strict);
    return true;
  } on CodecException {
    return false;
  }
}

int nonFinalMultibyteDecodeSplit(List<int> bytes, ResolvedCodec codec) {
  if (!_isTableBacked(codec) || bytes.isEmpty) {
    return bytes.length;
  }
  final int maxSequenceLength =
      generatedMbcsMaxSequenceLengthByCodecId[codec.codecId];
  final DenseDecodeTable? singleDense =
      CodecDataLoader.loadMbcsSingleByteDecodeTable(codec.codecId);
  final RowCompressedDecodeTable? pairDense =
      CodecDataLoader.loadMbcsDoubleByteDecodeTable(codec.codecId);
  if (singleDense == null || pairDense == null) {
    return bytes.length;
  }
  final SparseDecodeTable? tripleSparse = maxSequenceLength >= 3
      ? CodecDataLoader.loadMbcsTripleByteDecodeTable(codec.codecId)
      : null;
  final int length = bytes.length;

  if (_validateTableBackedSlice(
    bytes,
    length,
    maxSequenceLength,
    singleDense,
    pairDense,
    tripleSparse,
  )) {
    return length;
  }

  if (tripleSparse != null && length >= 2) {
    final int b0 = bytes[length - 2] & 0xFF;
    final int b1 = bytes[length - 1] & 0xFF;
    if (tripleSparse.hasLeadPair(b0, b1) &&
        _validateTableBackedSlice(
          bytes,
          length - 2,
          maxSequenceLength,
          singleDense,
          pairDense,
          tripleSparse,
        )) {
      return length - 2;
    }
  }

  final int last = bytes[length - 1] & 0xFF;
  if (!_isCompleteSingleByte(singleDense, last) &&
      _validateTableBackedSlice(
        bytes,
        length - 1,
        maxSequenceLength,
        singleDense,
        pairDense,
        tripleSparse,
      )) {
    return length - 1;
  }

  return length;
}

String decodeMultibyte(
  List<int> bytes,
  ResolvedCodec codec, {
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  if (_isStatefulBacked(codec)) {
    if (codec.canonicalName == 'gb18030') {
      return _decodeGb18030(bytes, codec, errors: errors);
    }
    if (codec.canonicalName == 'iso-2022-jp' ||
        codec.canonicalName == 'iso2022-jp-1' ||
        codec.canonicalName == 'iso2022-jp-2' ||
        codec.canonicalName == 'iso2022-jp-3' ||
        codec.canonicalName == 'iso2022-jp-2004' ||
        codec.canonicalName == 'iso2022-jp-ext') {
      return _decodeIso2022JpFamily(bytes, codec, errors: errors);
    }
    if (codec.canonicalName == 'hz-gb-2312') {
      return _decodeHz(bytes, codec, errors: errors);
    }
    if (codec.canonicalName == 'iso-2022-kr') {
      return _decodeIso2022Kr(bytes, codec, errors: errors);
    }
  }

  if (!_isTableBacked(codec)) {
    throw CodecException(
      encoding: codec.canonicalName,
      operation: CodecOperation.decode,
      position: 0,
      reason: 'multibyte codec metadata is missing a decode implementation',
    );
  }

  final int maxSequenceLength =
      generatedMbcsMaxSequenceLengthByCodecId[codec.codecId];
  final DenseDecodeTable? singleDense =
      CodecDataLoader.loadMbcsSingleByteDecodeTable(codec.codecId);
  final RowCompressedDecodeTable? pairDense =
      CodecDataLoader.loadMbcsDoubleByteDecodeTable(codec.codecId);
  final SparseDecodeTable? tripleSparse = maxSequenceLength >= 3
      ? CodecDataLoader.loadMbcsTripleByteDecodeTable(codec.codecId)
      : null;

  if (singleDense == null || pairDense == null) {
    throw CodecException(
      encoding: codec.canonicalName,
      operation: CodecOperation.decode,
      position: 0,
      reason: 'multibyte decode tables are missing',
    );
  }

  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < bytes.length) {
    final int b0 = bytes[i] & 0xFF;
    if (b0 < singleDense.values.length) {
      final int cp = singleDense.values[b0];
      if (cp != invalidCodePoint && cp != multiCodePoint) {
        out.writeCharCode(cp);
        i += 1;
        continue;
      }
    }

    if (maxSequenceLength >= 3 &&
        i + 2 < bytes.length &&
        tripleSparse != null) {
      final int b1 = bytes[i + 1] & 0xFF;
      final int b2 = bytes[i + 2] & 0xFF;
      final int key3 = (b0 << 16) | (b1 << 8) | b2;
      final int cp3 = tripleSparse.lookupCodePoint(key3);
      if (cp3 != invalidCodePoint && cp3 != multiCodePoint) {
        out.writeCharCode(cp3);
        i += 3;
        continue;
      }
      if (cp3 == multiCodePoint) {
        final String? decoded = tripleSparse.lookupMultiRune(key3);
        if (decoded != null) {
          out.write(decoded);
          i += 3;
          continue;
        }
      }
    }

    if (i + 1 < bytes.length) {
      final int b1 = bytes[i + 1] & 0xFF;
      final int key2 = (b0 << 8) | b1;
      final int cp2 = pairDense.lookupCodePoint(b0, b1);
      if (cp2 != invalidCodePoint && cp2 != multiCodePoint) {
        out.writeCharCode(cp2);
        i += 2;
        continue;
      }
      if (cp2 == multiCodePoint) {
        final String? decoded = pairDense.lookupMultiRune(key2);
        if (decoded != null) {
          out.write(decoded);
          i += 2;
          continue;
        }
      }
    }

    final bool incomplete = i + 1 >= bytes.length;
    if (errors == CodecErrorMode.strict) {
      throw CodecException(
        encoding: codec.canonicalName,
        operation: CodecOperation.decode,
        position: i,
        reason: incomplete
            ? 'incomplete multibyte sequence'
            : 'invalid multibyte sequence',
      );
    }

    switch (errors) {
      case CodecErrorMode.ignore:
        break;
      case CodecErrorMode.backslashReplace:
        out.write(r'\x');
        out.write(b0.toRadixString(16).padLeft(2, '0'));
        break;
      case CodecErrorMode.surrogateEscape:
        out.writeCharCode(0xDC00 + b0);
        break;
      case CodecErrorMode.replace:
      case CodecErrorMode.xmlCharRefReplace:
      case CodecErrorMode.nameReplace:
      case CodecErrorMode.surrogatePass:
        out.writeCharCode(0xFFFD);
        break;
      case CodecErrorMode.strict:
        // handled above
        break;
    }
    i += 1;
  }

  return out.toString();
}

List<int> encodeMultibyte(
  String text,
  ResolvedCodec codec, {
  CodecErrorMode errors = CodecErrorMode.strict,
}) {
  if (_isStatefulBacked(codec)) {
    if (codec.canonicalName == 'gb18030') {
      return _encodeGb18030(text, codec, errors: errors);
    }
    if (codec.canonicalName == 'iso-2022-jp' ||
        codec.canonicalName == 'iso2022-jp-1' ||
        codec.canonicalName == 'iso2022-jp-2' ||
        codec.canonicalName == 'iso2022-jp-3' ||
        codec.canonicalName == 'iso2022-jp-2004' ||
        codec.canonicalName == 'iso2022-jp-ext') {
      return _encodeIso2022JpFamily(text, codec, errors: errors);
    }
    if (codec.canonicalName == 'hz-gb-2312') {
      return _encodeHz(text, codec, errors: errors);
    }
    if (codec.canonicalName == 'iso-2022-kr') {
      return _encodeIso2022Kr(text, codec, errors: errors);
    }
  }

  final PagedEncodeTable? encodeTable = CodecDataLoader.loadMbcsEncodeTable(
    codec.codecId,
  );
  if (encodeTable == null) {
    throw CodecException(
      encoding: codec.canonicalName,
      operation: CodecOperation.encode,
      position: 0,
      reason: 'multibyte codec metadata is missing an encode implementation',
    );
  }

  final List<int> out = <int>[];
  int i = 0;
  for (final int cp in text.runes) {
    final int? packed = encodeTable.lookupPacked(cp);
    if (packed != null) {
      CodecDataLoader.appendPackedBytes(out, packed);
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
          encoding: codec.canonicalName,
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
          encoding: codec.canonicalName,
          operation: CodecOperation.encode,
          position: i,
          reason:
              'character U+${cp.toRadixString(16).toUpperCase()} is not encodable',
        );
    }
  }
  return out;
}

bool _validateTableBackedMultibyte(List<int> bytes, ResolvedCodec codec) {
  final int maxSequenceLength =
      generatedMbcsMaxSequenceLengthByCodecId[codec.codecId];
  final DenseDecodeTable? singleDense =
      CodecDataLoader.loadMbcsSingleByteDecodeTable(codec.codecId);
  final RowCompressedDecodeTable? pairDense =
      CodecDataLoader.loadMbcsDoubleByteDecodeTable(codec.codecId);
  final SparseDecodeTable? tripleSparse = maxSequenceLength >= 3
      ? CodecDataLoader.loadMbcsTripleByteDecodeTable(codec.codecId)
      : null;

  if (singleDense == null || pairDense == null) {
    return false;
  }

  return _validateTableBackedSlice(
    bytes,
    bytes.length,
    maxSequenceLength,
    singleDense,
    pairDense,
    tripleSparse,
  );
}

bool _validateTableBackedSlice(
  List<int> bytes,
  int end,
  int maxSequenceLength,
  DenseDecodeTable singleDense,
  RowCompressedDecodeTable pairDense,
  SparseDecodeTable? tripleSparse,
) {
  int i = 0;
  while (i < end) {
    final int b0 = bytes[i] & 0xFF;
    if (_isCompleteSingleByte(singleDense, b0)) {
      i += 1;
      continue;
    }

    if (maxSequenceLength >= 3 && i + 2 < end && tripleSparse != null) {
      final int b1 = bytes[i + 1] & 0xFF;
      final int b2 = bytes[i + 2] & 0xFF;
      if (_isCompleteTripleByte(tripleSparse, b0, b1, b2)) {
        i += 3;
        continue;
      }
    }

    if (i + 1 < end) {
      final int b1 = bytes[i + 1] & 0xFF;
      if (_isCompleteDoubleByte(pairDense, b0, b1)) {
        i += 2;
        continue;
      }
    }

    return false;
  }

  return true;
}

bool _validateGb18030(List<int> bytes) {
  final DenseDecodeTable pairTable =
      CodecDataLoader.loadGb18030DoubleByteDecodeTable();
  int i = 0;
  while (i < bytes.length) {
    final int b1 = bytes[i] & 0xFF;
    if (b1 < 0x80) {
      i += 1;
      continue;
    }
    if (i + 1 >= bytes.length) {
      return false;
    }

    final int b2 = bytes[i + 1] & 0xFF;
    if (b2 >= 0x30 && b2 <= 0x39) {
      if (i + 3 >= bytes.length) {
        return false;
      }
      final int b3 = bytes[i + 2] & 0xFF;
      final int b4 = bytes[i + 3] & 0xFF;
      if (b1 < 0x81 ||
          b1 > 0xFE ||
          b3 < 0x81 ||
          b3 > 0xFE ||
          b4 < 0x30 ||
          b4 > 0x39) {
        return false;
      }

      final int c1 = b1 - 0x81;
      final int c2 = b2 - 0x30;
      final int c3 = b3 - 0x81;
      final int c4 = b4 - 0x30;
      if (c1 < 4) {
        final int pointer = ((c1 * 10 + c2) * 126 + c3) * 10 + c4;
        if (pointer < 39420 &&
            _gb18030BmpCodePointFromPointer(pointer) != null) {
          i += 4;
          continue;
        }
      } else if (c1 >= 15) {
        final int cp = 0x10000 + (((c1 - 15) * 10 + c2) * 126 + c3) * 10 + c4;
        if (cp <= 0x10FFFF) {
          i += 4;
          continue;
        }
      }
      return false;
    }

    final int key = (b1 << 8) | b2;
    final int cp = pairTable.values[key];
    if (cp != invalidCodePoint &&
        (cp != multiCodePoint || pairTable.lookupMultiRune(key) != null)) {
      i += 2;
      continue;
    }
    return false;
  }
  return true;
}

bool _isCompleteSingleByte(DenseDecodeTable table, int b0) {
  if (b0 < 0 || b0 >= table.values.length) {
    return false;
  }
  final int cp = table.values[b0];
  if (cp == invalidCodePoint) {
    return false;
  }
  return cp != multiCodePoint || table.lookupMultiRune(b0) != null;
}

bool _isCompleteDoubleByte(RowCompressedDecodeTable table, int b0, int b1) {
  final int key = (b0 << 8) | b1;
  final int cp = table.lookupCodePoint(b0, b1);
  if (cp == invalidCodePoint) {
    return false;
  }
  return cp != multiCodePoint || table.lookupMultiRune(key) != null;
}

bool _isCompleteTripleByte(SparseDecodeTable table, int b0, int b1, int b2) {
  final int key = (b0 << 16) | (b1 << 8) | b2;
  final int cp = table.lookupCodePoint(key);
  if (cp == invalidCodePoint) {
    return false;
  }
  return cp != multiCodePoint || table.lookupMultiRune(key) != null;
}

String _decodeGb18030(
  List<int> bytes,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final DenseDecodeTable pairTable =
      CodecDataLoader.loadGb18030DoubleByteDecodeTable();
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < bytes.length) {
    final int b1 = bytes[i] & 0xFF;
    if (b1 < 0x80) {
      out.writeCharCode(b1);
      i += 1;
      continue;
    }
    if (i + 1 >= bytes.length) {
      _appendDecodeError(out, b1, codec, i, errors, incomplete: true);
      i += 1;
      continue;
    }

    final int b2 = bytes[i + 1] & 0xFF;
    if (b2 >= 0x30 && b2 <= 0x39) {
      if (i + 3 >= bytes.length) {
        _appendDecodeError(out, b1, codec, i, errors, incomplete: true);
        i += 1;
        continue;
      }
      final int b3 = bytes[i + 2] & 0xFF;
      final int b4 = bytes[i + 3] & 0xFF;
      if (b1 < 0x81 ||
          b1 > 0xFE ||
          b3 < 0x81 ||
          b3 > 0xFE ||
          b4 < 0x30 ||
          b4 > 0x39) {
        _appendDecodeError(out, b1, codec, i, errors);
        i += 1;
        continue;
      }

      final int c1 = b1 - 0x81;
      final int c2 = b2 - 0x30;
      final int c3 = b3 - 0x81;
      final int c4 = b4 - 0x30;
      if (c1 < 4) {
        final int pointer = ((c1 * 10 + c2) * 126 + c3) * 10 + c4;
        if (pointer < 39420) {
          final int? cp = _gb18030BmpCodePointFromPointer(pointer);
          if (cp != null) {
            out.writeCharCode(cp);
            i += 4;
            continue;
          }
        }
      } else if (c1 >= 15) {
        final int cp = 0x10000 + (((c1 - 15) * 10 + c2) * 126 + c3) * 10 + c4;
        if (cp <= 0x10FFFF) {
          out.writeCharCode(cp);
          i += 4;
          continue;
        }
      }
      _appendDecodeError(out, b1, codec, i, errors);
      i += 1;
      continue;
    }

    final int key = (b1 << 8) | b2;
    final int cp = pairTable.values[key];
    if (cp != invalidCodePoint && cp != multiCodePoint) {
      out.writeCharCode(cp);
      i += 2;
      continue;
    }
    if (cp == multiCodePoint) {
      final String? decoded = pairTable.lookupMultiRune(key);
      if (decoded != null) {
        out.write(decoded);
        i += 2;
        continue;
      }
    }

    _appendDecodeError(out, b1, codec, i, errors);
    i += 1;
  }
  return out.toString();
}

List<int> _encodeGb18030(
  String text,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final PagedEncodeTable pairTable =
      CodecDataLoader.loadGb18030DoubleByteEncodeTable();
  final List<int> out = <int>[];
  int i = 0;
  for (final int cp in text.runes) {
    if (cp < 0x80) {
      out.add(cp);
      i += 1;
      continue;
    }
    if (cp > 0x10FFFF) {
      _handleEncodeError(out, cp, codec, i, errors);
      i += 1;
      continue;
    }
    if (cp >= 0x10000) {
      final int tc = cp - 0x10000;
      out.addAll(_gb18030PointerToSequence(tc, firstByteBase: 0x90));
      i += 1;
      continue;
    }

    final int? packed = pairTable.lookupPacked(cp);
    if (packed != null) {
      CodecDataLoader.appendPackedBytes(out, packed);
      i += 1;
      continue;
    }

    final int? pointer = _gb18030BmpPointerFromCodePoint(cp);
    if (pointer != null) {
      out.addAll(_gb18030PointerToSequence(pointer, firstByteBase: 0x81));
      i += 1;
      continue;
    }

    _handleEncodeError(out, cp, codec, i, errors);
    i += 1;
  }
  return out;
}

String _decodeIso2022JpFamily(
  List<int> bytes,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final String canonical = codec.canonicalName;
  final bool useG2 = canonical == 'iso2022-jp-2';
  final StringBuffer out = StringBuffer();
  bool escThroughout = false;
  String g0 = 'ascii';
  String g2 = 'ascii';
  int i = 0;

  while (i < bytes.length) {
    final int b = bytes[i] & 0xFF;

    if (escThroughout) {
      out.writeCharCode(b);
      i += 1;
      if (_isEscEndByte(b)) {
        escThroughout = false;
      }
      continue;
    }

    if (b == 0x1B) {
      if (i + 1 >= bytes.length) {
        _appendDecodeError(out, b, codec, i, errors, incomplete: true);
        i += 1;
        continue;
      }
      final int b2 = bytes[i + 1] & 0xFF;

      if (useG2 && b2 == 0x4E) {
        if (i + 2 >= bytes.length) {
          _appendDecodeError(out, b, codec, i, errors, incomplete: true);
          i += 1;
          continue;
        }
        final int key = bytes[i + 2] & 0xFF;
        if (key >= 0x80) {
          _appendDecodeError(out, b, codec, i, errors);
          i += 1;
          continue;
        }
        if (!_writeIso2022SetDecodeUnit(out, g2, key, width: 1)) {
          _appendDecodeError(out, b, codec, i, errors);
          i += 1;
          continue;
        }
        i += 3;
        continue;
      }

      if (_isIso2022EscHeader(b2)) {
        if (i + 2 >= bytes.length) {
          _appendDecodeError(out, b, codec, i, errors, incomplete: true);
          i += 1;
          continue;
        }
        int consumed = 0;
        String? nextG0;
        String? nextG2;

        if (i + 5 < bytes.length &&
            b2 == 0x26 &&
            (bytes[i + 2] & 0xFF) == 0x40 &&
            (bytes[i + 3] & 0xFF) == 0x1B &&
            (bytes[i + 4] & 0xFF) == 0x24 &&
            (bytes[i + 5] & 0xFF) == 0x42) {
          consumed = 6;
          nextG0 = 'jisx0208';
        } else if (b2 == 0x28 && i + 2 < bytes.length) {
          final int mark = bytes[i + 2] & 0xFF;
          consumed = 3;
          if (mark == 0x42) {
            nextG0 = 'ascii';
          } else if (mark == 0x4A) {
            nextG0 = 'jisx0201_r';
          } else if (mark == 0x49) {
            nextG0 = 'jisx0201_k';
          } else {
            consumed = 0;
          }
        } else if (b2 == 0x24 && i + 2 < bytes.length) {
          final int mark = bytes[i + 2] & 0xFF;
          if (mark == 0x42) {
            consumed = 3;
            nextG0 = 'jisx0208';
          } else if (mark == 0x40) {
            consumed = 3;
            nextG0 = 'jisx0208_o';
          } else if (mark == 0x28 && i + 3 < bytes.length) {
            consumed = 4;
            final int mark2 = bytes[i + 3] & 0xFF;
            if (mark2 == 0x41) {
              nextG0 = 'gb2312';
            } else if (mark2 == 0x43) {
              nextG0 = 'ksx1001';
            } else if (mark2 == 0x44) {
              nextG0 = 'jisx0212';
            } else if (mark2 == 0x50) {
              nextG0 = 'jisx0213_2';
            } else if (mark2 == 0x51) {
              nextG0 = 'jisx0213_2004_1';
            } else if (mark2 == 0x40) {
              nextG0 = 'jisx0208_o';
            } else {
              consumed = 0;
            }
          }
        } else if (useG2 && b2 == 0x2E && i + 2 < bytes.length) {
          final int mark = bytes[i + 2] & 0xFF;
          consumed = 3;
          if (mark == 0x41) {
            nextG2 = 'iso8859_1_g2';
          } else if (mark == 0x46) {
            nextG2 = 'iso8859_7_g2';
          } else if (mark == 0x42) {
            nextG2 = 'ascii';
          } else {
            consumed = 0;
          }
        }

        if (consumed == 0) {
          _appendDecodeError(out, b, codec, i, errors);
          if (b2 == 0x24 && errors != CodecErrorMode.strict) {
            break;
          }
          i += 1;
          continue;
        }

        if (nextG0 != null &&
            !_codecSupportsIso2022Set(canonical, nextG0) &&
            nextG0 != 'ascii') {
          _appendDecodeError(out, b, codec, i, errors);
          i += 1;
          continue;
        }
        if (nextG2 != null &&
            !_codecSupportsIso2022Set(canonical, nextG2) &&
            nextG2 != 'ascii') {
          _appendDecodeError(out, b, codec, i, errors);
          i += 1;
          continue;
        }
        if (nextG0 != null) {
          g0 = nextG0;
        }
        if (nextG2 != null) {
          g2 = nextG2;
        }
        i += consumed;
        continue;
      }

      out.writeCharCode(0x1B);
      escThroughout = true;
      i += 1;
      continue;
    }

    if (b == 0x0A || b == 0x0E || b == 0x0F || b < 0x20) {
      out.writeCharCode(b);
      i += 1;
      continue;
    }
    if (b >= 0x80) {
      _appendDecodeError(out, b, codec, i, errors);
      i += 1;
      continue;
    }
    if (g0 == 'ascii') {
      out.writeCharCode(b);
      i += 1;
      continue;
    }

    final int? width = generatedIso2022SetWidths[g0];
    if (width == null) {
      _appendDecodeError(out, b, codec, i, errors);
      i += 1;
      continue;
    }

    if (width == 1) {
      if (!_writeIso2022SetDecodeUnit(out, g0, b, width: 1)) {
        _appendDecodeError(out, b, codec, i, errors);
        i += 1;
        continue;
      }
      i += 1;
      continue;
    }

    if (i + 1 >= bytes.length) {
      _appendDecodeError(out, b, codec, i, errors, incomplete: true);
      i += 1;
      continue;
    }
    final int bNext = bytes[i + 1] & 0xFF;
    if (bNext < 0x20 || bNext >= 0x80) {
      _appendDecodeError(out, b, codec, i, errors);
      i += 1;
      continue;
    }
    if (!_writeIso2022SetDecodeUnit(out, g0, (b << 8) | bNext, width: 2)) {
      _appendDecodeError(out, b, codec, i, errors);
      i += 1;
      continue;
    }
    i += 2;
  }

  return out.toString();
}

List<int> _encodeIso2022JpFamily(
  String text,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final String canonical = codec.canonicalName;
  final List<String>? setOrder = generatedIso2022CodecSetOrder[canonical];
  if (setOrder == null) {
    throw CodecException(
      encoding: canonical,
      operation: CodecOperation.encode,
      position: 0,
      reason: 'missing iso2022 set order',
    );
  }

  final List<int> out = <int>[];
  String g0 = 'ascii';
  String g2 = 'ascii';
  int i = 0;
  for (final int cp in text.runes) {
    if (cp < 0x80) {
      if (g0 != 'ascii') {
        out.addAll(const <int>[0x1B, 0x28, 0x42]);
        g0 = 'ascii';
      }
      out.add(cp);
      i += 1;
      continue;
    }

    String? chosenSet;
    int? packedUnit;
    for (final String setId in setOrder) {
      final PagedEncodeTable? encodeTable =
          CodecDataLoader.loadIso2022SetEncodeTable(setId);
      final int? candidate = encodeTable?.lookupPacked(cp);
      if (candidate != null) {
        chosenSet = setId;
        packedUnit = candidate;
        break;
      }
    }

    if (chosenSet == null || packedUnit == null) {
      _handleEncodeError(out, cp, codec, i, errors);
      i += 1;
      continue;
    }

    final String mode = generatedIso2022SetModes[chosenSet] ?? 'g0';
    if (mode == 'g2') {
      if (g2 != chosenSet) {
        final List<int>? esc = generatedIso2022SetDesignationEscapes[chosenSet];
        if (esc == null) {
          _handleEncodeError(out, cp, codec, i, errors);
          continue;
        }
        out.addAll(esc);
        g2 = chosenSet;
      }
      out.addAll(const <int>[0x1B, 0x4E]);
      out.add(CodecDataLoader.packedByteAt(packedUnit, 0));
      i += 1;
      continue;
    }

    if (g0 != chosenSet) {
      final List<int>? esc = generatedIso2022SetDesignationEscapes[chosenSet];
      if (esc == null) {
        _handleEncodeError(out, cp, codec, i, errors);
        continue;
      }
      out.addAll(esc);
      g0 = chosenSet;
    }
    CodecDataLoader.appendPackedBytes(out, packedUnit);
    i += 1;
  }

  if (g0 != 'ascii') {
    out.addAll(const <int>[0x1B, 0x28, 0x42]);
  }
  return out;
}

String _decodeHz(
  List<int> bytes,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final DenseDecodeTable hzDecodeTable = CodecDataLoader.loadHzDecodeTable();
  final StringBuffer out = StringBuffer();
  bool inGb = false;
  int i = 0;
  while (i < bytes.length) {
    final int b = bytes[i] & 0xFF;
    if (b == 0x7E) {
      if (i + 1 >= bytes.length) {
        if (!_appendDecodeError(out, b, codec, i, errors, incomplete: true)) {
          i += 1;
        } else {
          i += 1;
        }
        continue;
      }
      final int next = bytes[i + 1] & 0xFF;
      if (next == 0x7B) {
        inGb = true;
        i += 2;
        continue;
      }
      if (next == 0x7D) {
        inGb = false;
        i += 2;
        continue;
      }
      if (next == 0x7E) {
        out.writeCharCode(0x7E);
        i += 2;
        continue;
      }
      if (next == 0x0A) {
        i += 2;
        continue;
      }
      if (next == 0x0D) {
        if (i + 2 < bytes.length && (bytes[i + 2] & 0xFF) == 0x0A) {
          i += 3;
        } else {
          i += 2;
        }
        continue;
      }
      _appendDecodeError(out, b, codec, i, errors);
      i += 1;
      continue;
    }

    if (!inGb) {
      if (b < 0x80) {
        out.writeCharCode(b);
      } else {
        _appendDecodeError(out, b, codec, i, errors);
      }
      i += 1;
      continue;
    }

    if (i + 1 >= bytes.length) {
      _appendDecodeError(out, b, codec, i, errors, incomplete: true);
      i += 1;
      continue;
    }

    final int b1 = b;
    final int b2 = bytes[i + 1] & 0xFF;
    if (b1 < 0x21 || b1 > 0x7E || b2 < 0x21 || b2 > 0x7E) {
      _appendDecodeError(out, b1, codec, i, errors);
      i += 1;
      continue;
    }
    final int index = _pair94Index(b1, b2);
    if (!_writeDenseDecodeByIndex(out, hzDecodeTable, index)) {
      _appendDecodeError(out, b1, codec, i, errors);
      i += 1;
      continue;
    }
    i += 2;
  }
  return out.toString();
}

String _decodeIso2022Kr(
  List<int> bytes,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final DenseDecodeTable krDecodeTable =
      CodecDataLoader.loadIso2022KrDecodeTable();
  final StringBuffer out = StringBuffer();
  bool designated = false;
  bool shifted = false;
  int i = 0;
  while (i < bytes.length) {
    final int b = bytes[i] & 0xFF;
    if (b == 0x1B) {
      if (i + 3 >= bytes.length) {
        _appendDecodeError(out, b, codec, i, errors, incomplete: true);
        i += 1;
        continue;
      }
      final int b1 = bytes[i + 1] & 0xFF;
      final int b2 = bytes[i + 2] & 0xFF;
      final int b3 = bytes[i + 3] & 0xFF;
      if (b1 == 0x24 && b2 == 0x29 && b3 == 0x43) {
        designated = true;
        i += 4;
        continue;
      }
      _appendDecodeError(out, b, codec, i, errors);
      i += 1;
      continue;
    }
    if (b == 0x0E) {
      shifted = true;
      i += 1;
      continue;
    }
    if (b == 0x0F) {
      shifted = false;
      i += 1;
      continue;
    }

    if (!shifted) {
      if (b < 0x80) {
        out.writeCharCode(b);
      } else {
        _appendDecodeError(out, b, codec, i, errors);
      }
      i += 1;
      continue;
    }

    if (!designated) {
      _appendDecodeError(out, b, codec, i, errors);
      i += 1;
      continue;
    }
    if (i + 1 >= bytes.length) {
      _appendDecodeError(out, b, codec, i, errors, incomplete: true);
      i += 1;
      continue;
    }
    final int b1 = b;
    final int b2 = bytes[i + 1] & 0xFF;
    if (b1 < 0x21 || b1 > 0x7E || b2 < 0x21 || b2 > 0x7E) {
      _appendDecodeError(out, b1, codec, i, errors);
      i += 1;
      continue;
    }
    final int index = _pair94Index(b1, b2);
    if (!_writeDenseDecodeByIndex(out, krDecodeTable, index)) {
      _appendDecodeError(out, b1, codec, i, errors);
      i += 1;
      continue;
    }
    i += 2;
  }
  return out.toString();
}

List<int> _encodeHz(
  String text,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final PagedEncodeTable hzEncodeTable = CodecDataLoader.loadHzEncodeTable();
  final List<int> out = <int>[];
  bool inGb = false;
  int i = 0;
  for (final int cp in text.runes) {
    if (cp < 0x80) {
      if (inGb) {
        out.addAll(const <int>[0x7E, 0x7D]);
        inGb = false;
      }
      if (cp == 0x7E) {
        out.addAll(const <int>[0x7E, 0x7E]);
      } else {
        out.add(cp);
      }
      i += 1;
      continue;
    }
    final int? packed = hzEncodeTable.lookupPacked(cp);
    if (packed == null) {
      _handleEncodeError(out, cp, codec, i, errors);
      i += 1;
      continue;
    }
    if (!inGb) {
      out.addAll(const <int>[0x7E, 0x7B]);
      inGb = true;
    }
    CodecDataLoader.appendPackedBytes(out, packed);
    i += 1;
  }
  if (inGb) {
    out.addAll(const <int>[0x7E, 0x7D]);
  }
  return out;
}

List<int> _encodeIso2022Kr(
  String text,
  ResolvedCodec codec, {
  required CodecErrorMode errors,
}) {
  final PagedEncodeTable krEncodeTable =
      CodecDataLoader.loadIso2022KrEncodeTable();
  final List<int> out = <int>[];
  bool designated = false;
  bool shifted = false;
  int i = 0;
  for (final int cp in text.runes) {
    if (cp < 0x80) {
      if (shifted) {
        out.add(0x0F);
        shifted = false;
      }
      out.add(cp);
      i += 1;
      continue;
    }
    final int? packed = krEncodeTable.lookupPacked(cp);
    if (packed == null) {
      _handleEncodeError(out, cp, codec, i, errors);
      i += 1;
      continue;
    }
    if (!designated) {
      out.addAll(const <int>[0x1B, 0x24, 0x29, 0x43]);
      designated = true;
    }
    if (!shifted) {
      out.add(0x0E);
      shifted = true;
    }
    CodecDataLoader.appendPackedBytes(out, packed);
    i += 1;
  }
  if (shifted) {
    out.add(0x0F);
  }
  return out;
}

bool _writeIso2022SetDecodeUnit(
  StringBuffer out,
  String setId,
  int key, {
  required int width,
}) {
  final DenseDecodeTable? table = CodecDataLoader.loadIso2022SetDecodeTable(
    setId,
  );
  if (table == null) {
    return false;
  }
  if (width == 1) {
    if (key < 0 || key >= table.values.length) {
      return false;
    }
    return _writeDenseDecodeByIndex(out, table, key);
  }
  final int b1 = (key >> 8) & 0xFF;
  final int b2 = key & 0xFF;
  if (b1 < 0x21 || b1 > 0x7E || b2 < 0x21 || b2 > 0x7E) {
    return false;
  }
  final int index = _pair94Index(b1, b2);
  if (index < 0 || index >= table.values.length) {
    return false;
  }
  return _writeDenseDecodeByIndex(out, table, index);
}

bool _writeDenseDecodeByIndex(
  StringBuffer out,
  DenseDecodeTable table,
  int index,
) {
  final int cp = table.values[index];
  if (cp == invalidCodePoint) {
    return false;
  }
  if (cp == multiCodePoint) {
    final String? multi = table.lookupMultiRune(index);
    if (multi == null) {
      return false;
    }
    out.write(multi);
    return true;
  }
  out.writeCharCode(cp);
  return true;
}

int _pair94Index(int b1, int b2) => (b1 - 0x21) * 94 + (b2 - 0x21);

bool _codecSupportsIso2022Set(String canonicalCodec, String setId) {
  if (setId == 'ascii') {
    return true;
  }
  final List<String>? sets = generatedIso2022CodecSetOrder[canonicalCodec];
  if (sets == null) {
    return false;
  }
  return sets.contains(setId);
}

bool _isIso2022EscHeader(int b) {
  return b == 0x28 || b == 0x29 || b == 0x24 || b == 0x2E || b == 0x26;
}

bool _isEscEndByte(int b) {
  return (b >= 0x41 && b <= 0x5A) || b == 0x40;
}

int? _gb18030BmpCodePointFromPointer(int pointer) {
  for (final List<int> range in generatedGb18030BmpRanges) {
    final int first = range[0];
    final int last = range[1];
    final int base = range[2];
    final int maxPointer = base + (last - first);
    if (pointer < base) {
      return null;
    }
    if (pointer <= maxPointer) {
      return first + (pointer - base);
    }
  }
  return null;
}

int? _gb18030BmpPointerFromCodePoint(int codePoint) {
  for (final List<int> range in generatedGb18030BmpRanges) {
    final int first = range[0];
    final int last = range[1];
    final int base = range[2];
    if (codePoint >= first && codePoint <= last) {
      return base + (codePoint - first);
    }
  }
  return null;
}

List<int> _gb18030PointerToSequence(int pointer, {required int firstByteBase}) {
  int tc = pointer;
  final int b4 = (tc % 10) + 0x30;
  tc ~/= 10;
  final int b3 = (tc % 126) + 0x81;
  tc ~/= 126;
  final int b2 = (tc % 10) + 0x30;
  tc ~/= 10;
  final int b1 = tc + firstByteBase;
  return <int>[b1, b2, b3, b4];
}

bool _appendDecodeError(
  StringBuffer out,
  int byteValue,
  ResolvedCodec codec,
  int position,
  CodecErrorMode errors, {
  bool incomplete = false,
}) {
  if (errors == CodecErrorMode.strict) {
    throw CodecException(
      encoding: codec.canonicalName,
      operation: CodecOperation.decode,
      position: position,
      reason: incomplete
          ? 'incomplete multibyte sequence'
          : 'invalid multibyte sequence',
    );
  }
  switch (errors) {
    case CodecErrorMode.ignore:
      return true;
    case CodecErrorMode.backslashReplace:
      out.write(r'\x');
      out.write(byteValue.toRadixString(16).padLeft(2, '0'));
      return true;
    case CodecErrorMode.surrogateEscape:
      out.writeCharCode(0xDC00 + (byteValue & 0xFF));
      return true;
    case CodecErrorMode.replace:
    case CodecErrorMode.xmlCharRefReplace:
    case CodecErrorMode.nameReplace:
    case CodecErrorMode.surrogatePass:
      out.writeCharCode(0xFFFD);
      return true;
    case CodecErrorMode.strict:
      return false;
  }
}

void _handleEncodeError(
  List<int> out,
  int cp,
  ResolvedCodec codec,
  int position,
  CodecErrorMode errors,
) {
  if (errors == CodecErrorMode.surrogateEscape &&
      cp >= 0xDC80 &&
      cp <= 0xDCFF) {
    out.add(cp - 0xDC00);
    return;
  }
  switch (errors) {
    case CodecErrorMode.strict:
      throw CodecException(
        encoding: codec.canonicalName,
        operation: CodecOperation.encode,
        position: position,
        reason:
            'character U+${cp.toRadixString(16).toUpperCase()} is not encodable',
      );
    case CodecErrorMode.ignore:
      return;
    case CodecErrorMode.replace:
    case CodecErrorMode.surrogatePass:
      out.add(0x3F);
      return;
    case CodecErrorMode.backslashReplace:
      out.addAll(_asciiEscape(cp, lowercaseHex: true));
      return;
    case CodecErrorMode.xmlCharRefReplace:
      out.addAll('&#$cp;'.codeUnits);
      return;
    case CodecErrorMode.nameReplace:
      out.addAll(r'\N{U+'.codeUnits);
      out.addAll(cp.toRadixString(16).toUpperCase().codeUnits);
      out.addAll('}'.codeUnits);
      return;
    case CodecErrorMode.surrogateEscape:
      throw CodecException(
        encoding: codec.canonicalName,
        operation: CodecOperation.encode,
        position: position,
        reason:
            'character U+${cp.toRadixString(16).toUpperCase()} is not encodable',
      );
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
