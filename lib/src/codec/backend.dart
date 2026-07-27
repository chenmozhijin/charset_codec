// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../codec_types.dart';
import '../generated/codec_alias_data.g.dart';
import '../native/native_bridge.dart';
import 'impl.dart';
import 'resolver.dart' as codec_resolver;

abstract interface class CodecBackend {
  String get name;
  bool get isAvailable;

  CharsetCodec resolveCodec(String encoding);
  bool isStrictlyValidData(List<int> bytes, String encoding);
}

final class DartCodecBackend implements CodecBackend {
  const DartCodecBackend();

  @override
  String get name => 'dart';

  @override
  bool get isAvailable => true;

  @override
  CharsetCodec resolveCodec(String encoding) => resolveCharsetCodec(encoding);

  @override
  bool isStrictlyValidData(List<int> bytes, String encoding) =>
      validateDataWithDartBackend(bytes, encoding);
}

final class NativeCodecBackend implements CodecBackend {
  const NativeCodecBackend();

  @override
  String get name => nativeCodecBridge.backendName;

  @override
  bool get isAvailable => nativeCodecBridge.isAvailable;

  @override
  CharsetCodec resolveCodec(String encoding) {
    final int? codecId = codec_resolver.resolveCodecId(encoding);
    if (codecId == null) {
      throw CodecException(
        encoding: encoding,
        operation: CodecOperation.decode,
        position: 0,
        reason: 'unknown encoding',
      );
    }
    return _nativeCodecSingletons[codecId];
  }

  @override
  bool isStrictlyValidData(List<int> bytes, String encoding) {
    final codec_resolver.ResolvedCodec? resolved = codec_resolver.resolveCodec(
      encoding,
    );
    if (resolved == null) {
      return false;
    }
    if (nativeCodecBridge.supportsCodec(resolved)) {
      return nativeCodecBridge.validate(resolved, bytes);
    }
    return validateDataWithDartBackend(bytes, encoding);
  }
}

const CodecBackend _dartCodecBackend = DartCodecBackend();
const CodecBackend _nativeCodecBackend = NativeCodecBackend();

final List<CharsetCodec> _nativeCodecSingletons = List<CharsetCodec>.generate(
  generatedCanonicalNames.length,
  (int index) => _HybridNativeCharsetCodec(
    codec_resolver.ResolvedCodec(index),
    resolveCharsetCodec(generatedCanonicalNames[index]),
  ),
  growable: false,
);

CodecBackend? _backendOverrideForTesting;

CodecBackend get activeCodecBackend {
  final CodecBackend? overridden = _backendOverrideForTesting;
  if (overridden != null) {
    return overridden;
  }
  if (_nativeCodecBackend.isAvailable) {
    return _nativeCodecBackend;
  }
  return _dartCodecBackend;
}

String activeCodecBackendName() => activeCodecBackend.name;

void debugOverrideCodecBackendForTesting(CodecBackend? backend) {
  _backendOverrideForTesting = backend;
}

final class _HybridNativeCharsetCodec implements CharsetCodec {
  const _HybridNativeCharsetCodec(this._resolved, this._fallback);

  final codec_resolver.ResolvedCodec _resolved;
  final CharsetCodec _fallback;

  @override
  String get name => _resolved.canonicalName;

  @override
  String decode(
    List<int> bytes, {
    CodecErrorMode errors = CodecErrorMode.strict,
  }) {
    if (nativeCodecBridge.supportsOperation(_resolved, errors)) {
      return nativeCodecBridge.decode(_resolved, bytes, errors: errors);
    }
    return _fallback.decode(bytes, errors: errors);
  }

  @override
  List<int> encode(
    String text, {
    CodecErrorMode errors = CodecErrorMode.strict,
  }) {
    if (nativeCodecBridge.supportsOperation(_resolved, errors)) {
      return nativeCodecBridge.encode(_resolved, text, errors: errors);
    }
    return _fallback.encode(text, errors: errors);
  }

  @override
  IncrementalDecoder newDecoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  }) {
    if (nativeCodecBridge.supportsOperation(_resolved, errors) &&
        nativeCodecBridge.supportsIncrementalCodec(_resolved)) {
      return _HybridNativeSessionIncrementalDecoder(_resolved, errors);
    }
    return _fallback.newDecoder(errors: errors);
  }

  @override
  IncrementalEncoder newEncoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  }) {
    if (nativeCodecBridge.supportsOperation(_resolved, errors) &&
        nativeCodecBridge.supportsIncrementalCodec(_resolved)) {
      if (isGeneratedStatefulMultibyteCodec(_resolved.canonicalName)) {
        return _HybridNativeSessionIncrementalEncoder(_resolved, errors);
      }
      return _HybridNativeDirectIncrementalEncoder(_resolved, errors);
    }
    return _fallback.newEncoder(errors: errors);
  }
}

final class _HybridNativeSessionIncrementalDecoder
    implements IncrementalDecoder {
  _HybridNativeSessionIncrementalDecoder(this._resolved, CodecErrorMode errors)
    : _handle = nativeCodecBridge.createIncrementalDecoderSession(
        _resolved,
        errors: errors,
      ) {
    nativeCodecBridge.attachIncrementalSessionFinalizer(this, _handle);
  }

  final codec_resolver.ResolvedCodec _resolved;
  final int _handle;
  bool _closed = false;

  @override
  String feed(List<int> chunk, {bool finalChunk = false}) {
    _ensureOpen();
    return nativeCodecBridge.feedDecoderSession(
      _handle,
      _resolved,
      chunk,
      finalChunk: finalChunk,
    );
  }

  @override
  String close() {
    if (_closed) {
      return '';
    }
    _closed = true;
    try {
      return nativeCodecBridge.closeDecoderSession(_handle, _resolved);
    } finally {
      nativeCodecBridge.detachIncrementalSessionFinalizer(this);
      nativeCodecBridge.destroyIncrementalSession(_handle);
    }
  }

  @override
  void reset() {
    _ensureOpen();
    nativeCodecBridge.resetIncrementalSession(_handle, _resolved);
  }

  @override
  Object getState() {
    _ensureOpen();
    return _HybridNativeIncrementalDecoderState(
      nativeCodecBridge.getIncrementalSessionState(_handle, _resolved),
    );
  }

  @override
  void setState(Object state) {
    _ensureOpen();
    if (state is _HybridNativeIncrementalDecoderState) {
      nativeCodecBridge.setIncrementalSessionState(
        _handle,
        _resolved,
        state.blob,
      );
      return;
    }
    throw ArgumentError.value(
      state,
      'state',
      'must be _HybridNativeIncrementalDecoderState',
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('incremental decoder is already closed');
    }
  }
}

final class _HybridNativeIncrementalDecoderState {
  const _HybridNativeIncrementalDecoderState(this.blob);

  final Uint8List blob;
}

final class _HybridNativeDirectIncrementalEncoder
    implements IncrementalEncoder {
  _HybridNativeDirectIncrementalEncoder(this._resolved, this._errors);

  final codec_resolver.ResolvedCodec _resolved;
  final CodecErrorMode _errors;
  String _pendingScalar = '';
  bool _closed = false;

  @override
  List<int> feed(String chunk, {bool finalChunk = false}) {
    _ensureOpen();
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
    return nativeCodecBridge.encode(_resolved, text, errors: _errors);
  }

  @override
  List<int> close() {
    if (_closed) {
      return const <int>[];
    }
    _closed = true;
    if (_pendingScalar.isEmpty) {
      return const <int>[];
    }
    final String text = _pendingScalar;
    _pendingScalar = '';
    return nativeCodecBridge.encode(_resolved, text, errors: _errors);
  }

  @override
  Object getState() {
    _ensureOpen();
    return _HybridNativeDirectIncrementalEncoderState(_pendingScalar);
  }

  @override
  void reset() {
    _ensureOpen();
    _pendingScalar = '';
  }

  @override
  void setState(Object state) {
    _ensureOpen();
    if (state is _HybridNativeDirectIncrementalEncoderState) {
      _pendingScalar = state.pendingScalar;
      return;
    }
    throw ArgumentError.value(
      state,
      'state',
      'must be _HybridNativeDirectIncrementalEncoderState',
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('incremental encoder is already closed');
    }
  }
}

final class _HybridNativeDirectIncrementalEncoderState {
  const _HybridNativeDirectIncrementalEncoderState(this.pendingScalar);

  final String pendingScalar;
}

final class _HybridNativeSessionIncrementalEncoder
    implements IncrementalEncoder {
  _HybridNativeSessionIncrementalEncoder(this._resolved, CodecErrorMode errors)
    : _handle = nativeCodecBridge.createIncrementalEncoderSession(
        _resolved,
        errors: errors,
      ) {
    nativeCodecBridge.attachIncrementalSessionFinalizer(this, _handle);
  }

  final codec_resolver.ResolvedCodec _resolved;
  final int _handle;
  bool _closed = false;

  @override
  List<int> feed(String chunk, {bool finalChunk = false}) {
    _ensureOpen();
    return nativeCodecBridge.feedEncoderSession(
      _handle,
      _resolved,
      chunk,
      finalChunk: finalChunk,
    );
  }

  @override
  List<int> close() {
    if (_closed) {
      return const <int>[];
    }
    _closed = true;
    try {
      return nativeCodecBridge.closeEncoderSession(_handle, _resolved);
    } finally {
      nativeCodecBridge.detachIncrementalSessionFinalizer(this);
      nativeCodecBridge.destroyIncrementalSession(_handle);
    }
  }

  @override
  Object getState() {
    _ensureOpen();
    return _HybridNativeIncrementalEncoderState(
      nativeCodecBridge.getIncrementalSessionState(_handle, _resolved),
    );
  }

  @override
  void reset() {
    _ensureOpen();
    nativeCodecBridge.resetIncrementalSession(_handle, _resolved);
  }

  @override
  void setState(Object state) {
    _ensureOpen();
    if (state is _HybridNativeIncrementalEncoderState) {
      nativeCodecBridge.setIncrementalSessionState(
        _handle,
        _resolved,
        state.blob,
      );
      return;
    }
    throw ArgumentError.value(
      state,
      'state',
      'must be _HybridNativeIncrementalEncoderState',
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('incremental encoder is already closed');
    }
  }
}

final class _HybridNativeIncrementalEncoderState {
  const _HybridNativeIncrementalEncoderState(this.blob);

  final Uint8List blob;
}

bool _endsWithLeadingSurrogate(String text) {
  if (text.isEmpty) {
    return false;
  }
  final int unit = text.codeUnitAt(text.length - 1);
  return unit >= 0xD800 && unit <= 0xDBFF;
}
