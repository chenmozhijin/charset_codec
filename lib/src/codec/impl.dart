// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../codec_types.dart';
import '../generated/codec_alias_data.g.dart';
import '../generated/codec_mbcs_data.g.dart';
import 'mbcs.dart';
import 'resolver.dart';
import 'sbcs.dart';
import 'utf.dart';

final List<CharsetCodec> _codecSingletons = List<CharsetCodec>.generate(
  generatedCanonicalNames.length,
  (int index) => CharsetCodecImpl(ResolvedCodec(index)),
  growable: false,
);

final class CharsetCodecImpl implements CharsetCodec {
  CharsetCodecImpl(this._resolved);

  final ResolvedCodec _resolved;

  @override
  String get name => _resolved.canonicalName;

  @override
  String decode(
    List<int> bytes, {
    CodecErrorMode errors = CodecErrorMode.strict,
  }) {
    if (_resolved.isUtf) {
      return decodeUtf(bytes, _resolved.codecId, errors: errors);
    }
    if (_resolved.isSingleByte) {
      return decodeSingleByte(bytes, _resolved.codecId, errors: errors);
    }
    if (_resolved.isMultibyte) {
      return decodeMultibyte(bytes, _resolved, errors: errors);
    }
    throw CodecException(
      encoding: _resolved.canonicalName,
      operation: CodecOperation.decode,
      position: 0,
      reason: 'unsupported codec family',
    );
  }

  @override
  List<int> encode(
    String text, {
    CodecErrorMode errors = CodecErrorMode.strict,
  }) {
    if (_resolved.isUtf) {
      return encodeUtf(text, _resolved.codecId, errors: errors);
    }
    if (_resolved.isSingleByte) {
      return encodeSingleByte(text, _resolved.codecId, errors: errors);
    }
    if (_resolved.isMultibyte) {
      return encodeMultibyte(text, _resolved, errors: errors);
    }
    throw CodecException(
      encoding: _resolved.canonicalName,
      operation: CodecOperation.encode,
      position: 0,
      reason: 'unsupported codec family',
    );
  }

  @override
  IncrementalDecoder newDecoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  }) => _IncrementalDecoderImpl(_resolved, errors);

  @override
  IncrementalEncoder newEncoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  }) => _IncrementalEncoderImpl(_resolved, errors);
}

final class _IncrementalDecoderImpl implements IncrementalDecoder {
  _IncrementalDecoderImpl(this._codec, this._errors);

  final ResolvedCodec _codec;
  final CodecErrorMode _errors;
  final List<int> _pending = <int>[];
  late final UtfIncrementalDecoderState? _utfState =
      _codec.isUtf && supportsIncrementalUtf(_codec.codecId)
      ? UtfIncrementalDecoderState(_codec.codecId)
      : null;
  late final StatefulMultibyteDecoderState? _statefulMultibyteState =
      _codec.isMultibyte &&
          isGeneratedStatefulMultibyteCodec(_codec.canonicalName)
      ? StatefulMultibyteDecoderState(_codec)
      : null;
  bool _closed = false;

  @override
  String feed(List<int> chunk, {bool finalChunk = false}) {
    _ensureOpen();
    if (_codec.isSingleByte) {
      if (chunk.isEmpty) {
        return '';
      }
      return decodeSingleByte(chunk, _codec.codecId, errors: _errors);
    }

    if (_utfState != null) {
      return decodeUtfIncrementalChunk(
        chunk,
        _utfState,
        errors: _errors,
        finalChunk: finalChunk,
      );
    }

    if (_statefulMultibyteState != null) {
      return decodeStatefulMultibyteIncrementalChunk(
        chunk,
        _codec,
        _statefulMultibyteState,
        errors: _errors,
        finalChunk: finalChunk,
      );
    }

    if (_usesSplitBufferMode) {
      return _feedSplitBuffer(chunk, finalChunk: finalChunk);
    }

    if (chunk.isNotEmpty) {
      _pending.addAll(chunk);
    }
    if (_pending.isEmpty) {
      return '';
    }
    if (finalChunk) {
      final String out = _decodeBytes(_pending, _errors);
      _pending.clear();
      return out;
    }

    if (_errors != CodecErrorMode.strict) {
      final String out = _decodeBytes(_pending, _errors);
      _pending.clear();
      return out;
    }

    try {
      final String out = _decodeBytes(_pending, CodecErrorMode.strict);
      _pending.clear();
      return out;
    } on CodecException catch (e) {
      if (!_isPossiblyIncompleteDecodeError(e)) {
        rethrow;
      }
      final int hintedSplit = e.position.clamp(0, _pending.length);
      return _drainDecodableStrictPrefix(hintedSplit);
    }
  }

  @override
  String close() {
    if (_closed) {
      return '';
    }
    _closed = true;
    if (_utfState != null) {
      return decodeUtfIncrementalChunk(
        const <int>[],
        _utfState,
        errors: _errors,
        finalChunk: true,
      );
    }
    if (_statefulMultibyteState != null) {
      return decodeStatefulMultibyteIncrementalChunk(
        const <int>[],
        _codec,
        _statefulMultibyteState,
        errors: _errors,
        finalChunk: true,
      );
    }
    if (_pending.isEmpty) {
      return '';
    }
    final String out = _decodeBytes(_pending, _errors);
    _pending.clear();
    return out;
  }

  String _decodeBytes(List<int> bytes, CodecErrorMode errors) {
    if (_codec.isUtf) {
      return decodeUtf(bytes, _codec.codecId, errors: errors);
    }
    if (_codec.isMultibyte) {
      return decodeMultibyte(bytes, _codec, errors: errors);
    }
    return decodeSingleByte(bytes, _codec.codecId, errors: errors);
  }

  bool get _usesSplitBufferMode {
    if (_codec.isMultibyte) {
      return supportsIncrementalMultibyteDecode(_codec);
    }
    return false;
  }

  String _feedSplitBuffer(List<int> chunk, {required bool finalChunk}) {
    if (chunk.isNotEmpty) {
      _pending.addAll(chunk);
    }
    if (_pending.isEmpty) {
      return '';
    }
    if (finalChunk) {
      final String out = _decodeBytes(_pending, _errors);
      _pending.clear();
      return out;
    }

    final int split = nonFinalMultibyteDecodeSplit(_pending, _codec);
    if (split <= 0) {
      return '';
    }
    if (split >= _pending.length) {
      final String out = _decodeBytes(_pending, _errors);
      _pending.clear();
      return out;
    }

    final String out = _decodeBytes(_pending.sublist(0, split), _errors);
    final List<int> trailing = _pending.sublist(split);
    _pending
      ..clear()
      ..addAll(trailing);
    return out;
  }

  String _drainDecodableStrictPrefix(int hintedSplit) {
    final int upper = hintedSplit <= 0 ? _pending.length : hintedSplit;
    for (int n = upper; n > 0; n--) {
      try {
        final String decoded = _decodeBytes(
          _pending.sublist(0, n),
          CodecErrorMode.strict,
        );
        final List<int> trailing = _pending.sublist(n);
        _pending
          ..clear()
          ..addAll(trailing);
        return decoded;
      } on CodecException {
        continue;
      }
    }
    return '';
  }

  bool _isPossiblyIncompleteDecodeError(CodecException e) {
    final String reason = e.reason.toLowerCase();
    if (reason.contains('incomplete')) {
      return true;
    }
    if (reason.contains('odd byte length')) {
      return true;
    }
    if (reason.contains('not divisible by 4')) {
      return true;
    }
    if (reason.contains('unterminated')) {
      return true;
    }
    if (reason.contains('partial character')) {
      return true;
    }
    if (reason.contains('unexpected end')) {
      return true;
    }
    return false;
  }

  @override
  void reset() {
    _ensureOpen();
    if (_utfState != null) {
      resetUtfIncrementalDecoderState(_utfState);
      return;
    }
    if (_statefulMultibyteState != null) {
      resetStatefulMultibyteDecoderState(_statefulMultibyteState);
      return;
    }
    _pending.clear();
  }

  @override
  void setState(Object state) {
    _ensureOpen();
    if (_utfState != null) {
      if (state is UtfIncrementalDecoderState) {
        resetUtfIncrementalDecoderState(_utfState);
        _utfState.pendingBytes.addAll(state.pendingBytes);
        _utfState.atStart = state.atStart;
        _utfState.littleEndian = state.littleEndian;
        _utfState.utf7InShift = state.utf7InShift;
        _utfState.utf7ShiftHasBase64 = state.utf7ShiftHasBase64;
        _utfState.utf7Base64Bits = state.utf7Base64Bits;
        _utfState.utf7Base64Buffer = state.utf7Base64Buffer;
        _utfState.utf7PendingHighSurrogate = state.utf7PendingHighSurrogate;
        _utfState.utf7ShiftStart = state.utf7ShiftStart;
        _utfState.utf7ProcessedBytes = state.utf7ProcessedBytes;
        return;
      }
      throw ArgumentError.value(
        state,
        'state',
        'must be UtfIncrementalDecoderState',
      );
    }
    if (_statefulMultibyteState != null) {
      if (state is StatefulMultibyteDecoderState &&
          state.codecId == _codec.codecId) {
        resetStatefulMultibyteDecoderState(_statefulMultibyteState);
        _statefulMultibyteState.pendingBytes.addAll(state.pendingBytes);
        _statefulMultibyteState.hzInGb = state.hzInGb;
        _statefulMultibyteState.krDesignated = state.krDesignated;
        _statefulMultibyteState.krShifted = state.krShifted;
        _statefulMultibyteState.isoEscThroughout = state.isoEscThroughout;
        _statefulMultibyteState.isoG0 = state.isoG0;
        _statefulMultibyteState.isoG2 = state.isoG2;
        return;
      }
      throw ArgumentError.value(
        state,
        'state',
        'must be matching StatefulMultibyteDecoderState',
      );
    }
    if (state is _IncrementalDecoderState) {
      _pending
        ..clear()
        ..addAll(state.bytes);
      return;
    }
    throw ArgumentError.value(
      state,
      'state',
      'must be _IncrementalDecoderState',
    );
  }

  @override
  Object getState() {
    _ensureOpen();
    if (_utfState != null) {
      return UtfIncrementalDecoderState.copy(_utfState);
    }
    if (_statefulMultibyteState != null) {
      return StatefulMultibyteDecoderState.copy(_statefulMultibyteState);
    }
    return _IncrementalDecoderState(bytes: Uint8List.fromList(_pending));
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('incremental decoder is already closed');
    }
  }
}

final class _IncrementalDecoderState {
  const _IncrementalDecoderState({required this.bytes});

  final Uint8List bytes;
}

final class _IncrementalEncoderImpl implements IncrementalEncoder {
  _IncrementalEncoderImpl(this._codec, this._errors);

  final ResolvedCodec _codec;
  final CodecErrorMode _errors;
  String _pendingScalar = '';
  bool _closed = false;
  late final UtfIncrementalEncoderState? _utfState =
      _codec.isUtf && supportsIncrementalUtf(_codec.codecId)
      ? UtfIncrementalEncoderState(_codec.codecId)
      : null;
  late final StatefulMultibyteEncoderState? _statefulMultibyteState =
      _codec.isMultibyte &&
          isGeneratedStatefulMultibyteCodec(_codec.canonicalName)
      ? StatefulMultibyteEncoderState(_codec)
      : null;

  @override
  List<int> feed(String chunk, {bool finalChunk = false}) {
    _ensureOpen();
    if (_utfState != null) {
      return encodeUtfIncrementalChunk(
        chunk,
        _utfState,
        errors: _errors,
        finalChunk: finalChunk,
      );
    }
    if (_statefulMultibyteState != null) {
      return encodeStatefulMultibyteIncrementalChunk(
        chunk,
        _codec,
        _statefulMultibyteState,
        errors: _errors,
        finalChunk: finalChunk,
      );
    }
    String text;
    if (_pendingScalar.isEmpty) {
      text = chunk;
    } else if (chunk.isEmpty) {
      text = _pendingScalar;
      _pendingScalar = '';
    } else {
      text = '$_pendingScalar$chunk';
      _pendingScalar = '';
    }
    if (text.isEmpty) {
      return const <int>[];
    }
    if (!finalChunk && _endsWithLeadingSurrogate(text)) {
      _pendingScalar = text.substring(text.length - 1);
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) {
      return const <int>[];
    }
    return _encodeText(text);
  }

  @override
  List<int> close() {
    if (_closed) {
      return const <int>[];
    }
    _closed = true;
    if (_utfState != null) {
      return encodeUtfIncrementalChunk(
        '',
        _utfState,
        errors: _errors,
        finalChunk: true,
      );
    }
    if (_statefulMultibyteState != null) {
      return encodeStatefulMultibyteIncrementalChunk(
        '',
        _codec,
        _statefulMultibyteState,
        errors: _errors,
        finalChunk: true,
      );
    }
    if (_pendingScalar.isEmpty) {
      return const <int>[];
    }
    final String text = _pendingScalar;
    _pendingScalar = '';
    return _encodeText(text);
  }

  List<int> _encodeText(String text) {
    if (_codec.isUtf) {
      return encodeUtf(text, _codec.codecId, errors: _errors);
    }
    if (_codec.isMultibyte) {
      return encodeMultibyte(text, _codec, errors: _errors);
    }
    return encodeSingleByte(text, _codec.codecId, errors: _errors);
  }

  @override
  Object getState() {
    _ensureOpen();
    if (_utfState != null) {
      return UtfIncrementalEncoderState.copy(_utfState);
    }
    if (_statefulMultibyteState != null) {
      return StatefulMultibyteEncoderState.copy(_statefulMultibyteState);
    }
    return _IncrementalEncoderState(text: _pendingScalar);
  }

  @override
  void reset() {
    _ensureOpen();
    if (_utfState != null) {
      resetUtfIncrementalEncoderState(_utfState);
      return;
    }
    if (_statefulMultibyteState != null) {
      resetStatefulMultibyteEncoderState(_statefulMultibyteState);
      return;
    }
    _pendingScalar = '';
  }

  @override
  void setState(Object state) {
    _ensureOpen();
    if (_utfState != null) {
      if (state is UtfIncrementalEncoderState) {
        _utfState.pendingScalar = state.pendingScalar;
        _utfState.bomEmitted = state.bomEmitted;
        _utfState.utf7InShift = state.utf7InShift;
        _utfState.utf7Base64Bits = state.utf7Base64Bits;
        _utfState.utf7Base64Buffer = state.utf7Base64Buffer;
        return;
      }
      throw ArgumentError.value(
        state,
        'state',
        'must be UtfIncrementalEncoderState',
      );
    }
    if (_statefulMultibyteState != null) {
      if (state is StatefulMultibyteEncoderState &&
          state.codecId == _codec.codecId) {
        resetStatefulMultibyteEncoderState(_statefulMultibyteState);
        _statefulMultibyteState.pendingScalar = state.pendingScalar;
        _statefulMultibyteState.hzInGb = state.hzInGb;
        _statefulMultibyteState.krDesignated = state.krDesignated;
        _statefulMultibyteState.krShifted = state.krShifted;
        _statefulMultibyteState.isoG0 = state.isoG0;
        _statefulMultibyteState.isoG2 = state.isoG2;
        return;
      }
      throw ArgumentError.value(
        state,
        'state',
        'must be matching StatefulMultibyteEncoderState',
      );
    }
    if (state is _IncrementalEncoderState) {
      _pendingScalar = state.text;
      return;
    }
    throw ArgumentError.value(
      state,
      'state',
      'must be _IncrementalEncoderState',
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('incremental encoder is already closed');
    }
  }
}

final class _IncrementalEncoderState {
  const _IncrementalEncoderState({required this.text});

  final String text;
}

bool _endsWithLeadingSurrogate(String text) {
  if (text.isEmpty) {
    return false;
  }
  final int unit = text.codeUnitAt(text.length - 1);
  return unit >= 0xD800 && unit <= 0xDBFF;
}

bool isGeneratedStatefulMultibyteCodec(String canonicalName) =>
    generatedMultibyteStatefulCodecs.contains(canonicalName);

CharsetCodec resolveCharsetCodec(String encoding) {
  final int? codecId = resolveCodecId(encoding);
  if (codecId == null) {
    throw CodecException(
      encoding: encoding,
      operation: CodecOperation.decode,
      position: 0,
      reason: 'unknown encoding',
    );
  }
  return _codecSingletons[codecId];
}

bool validateDataWithDartBackend(List<int> bytes, String encoding) {
  final ResolvedCodec? resolved = resolveCodec(encoding);
  if (resolved == null) {
    return false;
  }
  if (resolved.isUtf) {
    return validateUtf(bytes, resolved.codecId);
  }
  if (resolved.isSingleByte) {
    return validateSingleByte(bytes, resolved.codecId);
  }
  if (resolved.isMultibyte) {
    return validateMultibyteData(bytes, resolved);
  }
  return false;
}
