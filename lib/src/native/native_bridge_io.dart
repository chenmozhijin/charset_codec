// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:charset_codec/src/generated/native_codec_matrix.g.dart';
import 'package:ffi/ffi.dart' as pkg_ffi;

import '../codec/resolver.dart';
import '../codec_types.dart';
import 'charset_codec_native_bindings.dart';
import 'native_bridge_stub.dart';

const int _nativeAbiVersion = 3;
final Finalizer<int> _incrementalSessionFinalizer = Finalizer<int>((
  int handle,
) {
  try {
    charset_codec_incremental_session_destroy(handle);
  } catch (_) {
    // Garbage collection is only a fallback; explicit close releases the
    // native session during normal operation.
  }
});

final class IoNativeCodecBridge implements NativeCodecBridge {
  const IoNativeCodecBridge();

  @override
  bool get isAvailable => _nativeAvailable ??= _detectAvailability();

  @override
  String get backendName =>
      isAvailable ? 'native-hybrid' : 'native-unavailable';

  @override
  bool supportsCodec(ResolvedCodec resolved) {
    if (!isAvailable) {
      return false;
    }
    return generatedNativeCodecSupportedById[resolved.codecId];
  }

  @override
  bool supportsIncrementalCodec(ResolvedCodec resolved) {
    // One-shot UTF conversion is fully native; incremental UTF stays in the
    // Dart state machine to preserve BOM and chunk-boundary semantics.
    return supportsCodec(resolved) && !resolved.isUtf;
  }

  @override
  bool supportsOperation(ResolvedCodec resolved, CodecErrorMode errors) {
    if (!supportsCodec(resolved)) {
      return false;
    }
    return errors == CodecErrorMode.strict;
  }

  @override
  String decode(
    ResolvedCodec resolved,
    List<int> bytes, {
    required CodecErrorMode errors,
  }) {
    final ffi.Pointer<ffi.Uint8> bytesPtr = _copyBytes(bytes);
    try {
      final ffi.Pointer<NativeCodecResult> resultPtr =
          charset_codec_decode_to_utf16le(
            resolved.codecId,
            errors.index,
            bytesPtr,
            bytes.length,
          );
      return _readUtf16LeResult(resultPtr, resolved, CodecOperation.decode);
    } finally {
      pkg_ffi.malloc.free(bytesPtr);
    }
  }

  @override
  Uint8List encode(
    ResolvedCodec resolved,
    String text, {
    required CodecErrorMode errors,
  }) {
    final List<int> units = text.codeUnits;
    final ffi.Pointer<ffi.Uint16> unitsPtr = _copyCodeUnits(units);
    try {
      final ffi.Pointer<NativeCodecResult> resultPtr =
          charset_codec_encode_from_utf16(
            resolved.codecId,
            errors.index,
            unitsPtr,
            units.length,
          );
      return _readBytesResult(resultPtr, resolved, CodecOperation.encode);
    } finally {
      pkg_ffi.malloc.free(unitsPtr);
    }
  }

  @override
  bool validate(ResolvedCodec resolved, List<int> bytes) {
    final ffi.Pointer<ffi.Uint8> bytesPtr = _copyBytes(bytes);
    try {
      return charset_codec_validate(resolved.codecId, bytesPtr, bytes.length) !=
          0;
    } finally {
      pkg_ffi.malloc.free(bytesPtr);
    }
  }

  @override
  int createIncrementalDecoderSession(
    ResolvedCodec resolved, {
    required CodecErrorMode errors,
  }) {
    final int handle = charset_codec_incremental_decoder_create(
      resolved.codecId,
      errors.index,
    );
    if (handle == 0) {
      throw CodecException(
        encoding: resolved.canonicalName,
        operation: CodecOperation.decode,
        position: 0,
        reason: 'native backend could not create incremental decoder session',
      );
    }
    return handle;
  }

  @override
  int createIncrementalEncoderSession(
    ResolvedCodec resolved, {
    required CodecErrorMode errors,
  }) {
    final int handle = charset_codec_incremental_encoder_create(
      resolved.codecId,
      errors.index,
    );
    if (handle == 0) {
      throw CodecException(
        encoding: resolved.canonicalName,
        operation: CodecOperation.encode,
        position: 0,
        reason: 'native backend could not create incremental encoder session',
      );
    }
    return handle;
  }

  @override
  String feedDecoderSession(
    int handle,
    ResolvedCodec resolved,
    List<int> chunk, {
    required bool finalChunk,
  }) {
    final ffi.Pointer<ffi.Uint8> bytesPtr = _copyBytes(chunk);
    try {
      final ffi.Pointer<NativeCodecResult> resultPtr =
          charset_codec_incremental_decoder_feed(
            handle,
            bytesPtr,
            chunk.length,
            finalChunk ? 1 : 0,
          );
      return _readUtf8Result(resultPtr, resolved, CodecOperation.decode);
    } finally {
      pkg_ffi.malloc.free(bytesPtr);
    }
  }

  @override
  Uint8List feedEncoderSession(
    int handle,
    ResolvedCodec resolved,
    String chunk, {
    required bool finalChunk,
  }) {
    final List<int> units = chunk.codeUnits;
    final ffi.Pointer<ffi.Uint16> unitsPtr = _copyCodeUnits(units);
    try {
      final ffi.Pointer<NativeCodecResult> resultPtr =
          charset_codec_incremental_encoder_feed_utf16(
            handle,
            unitsPtr,
            units.length,
            finalChunk ? 1 : 0,
          );
      return _readBytesResult(resultPtr, resolved, CodecOperation.encode);
    } finally {
      pkg_ffi.malloc.free(unitsPtr);
    }
  }

  @override
  String closeDecoderSession(int handle, ResolvedCodec resolved) {
    final ffi.Pointer<NativeCodecResult> resultPtr =
        charset_codec_incremental_decoder_close(handle);
    return _readUtf8Result(resultPtr, resolved, CodecOperation.decode);
  }

  @override
  Uint8List closeEncoderSession(int handle, ResolvedCodec resolved) {
    final ffi.Pointer<NativeCodecResult> resultPtr =
        charset_codec_incremental_encoder_close(handle);
    return _readBytesResult(resultPtr, resolved, CodecOperation.encode);
  }

  @override
  Uint8List getIncrementalSessionState(int handle, ResolvedCodec resolved) {
    final ffi.Pointer<NativeCodecResult> resultPtr =
        charset_codec_incremental_session_get_state(handle);
    return _readBytesResult(resultPtr, resolved, CodecOperation.decode);
  }

  @override
  void setIncrementalSessionState(
    int handle,
    ResolvedCodec resolved,
    Uint8List state,
  ) {
    final ffi.Pointer<ffi.Uint8> bytesPtr = _copyBytes(state);
    try {
      final ffi.Pointer<NativeCodecResult> resultPtr =
          charset_codec_incremental_session_set_state(
            handle,
            bytesPtr,
            state.length,
          );
      _readBytesResult(resultPtr, resolved, CodecOperation.decode);
    } finally {
      pkg_ffi.malloc.free(bytesPtr);
    }
  }

  @override
  void resetIncrementalSession(int handle, ResolvedCodec resolved) {
    final ffi.Pointer<NativeCodecResult> resultPtr =
        charset_codec_incremental_session_reset(handle);
    _readBytesResult(resultPtr, resolved, CodecOperation.decode);
  }

  @override
  void destroyIncrementalSession(int handle) {
    charset_codec_incremental_session_destroy(handle);
  }

  @override
  void attachIncrementalSessionFinalizer(Object owner, int handle) {
    _incrementalSessionFinalizer.attach(owner, handle, detach: owner);
  }

  @override
  void detachIncrementalSessionFinalizer(Object owner) {
    _incrementalSessionFinalizer.detach(owner);
  }

  bool _detectAvailability() {
    try {
      return charset_codec_backend_abi_version() == _nativeAbiVersion;
    } catch (_) {
      return false;
    }
  }

  ffi.Pointer<ffi.Uint8> _copyBytes(List<int> bytes) {
    final ffi.Pointer<ffi.Uint8> ptr = pkg_ffi.malloc.allocate<ffi.Uint8>(
      bytes.isEmpty ? 1 : bytes.length,
    );
    if (bytes.isNotEmpty) {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
    }
    return ptr;
  }

  ffi.Pointer<ffi.Uint16> _copyCodeUnits(List<int> units) {
    final ffi.Pointer<ffi.Uint16> ptr = pkg_ffi.malloc.allocate<ffi.Uint16>(
      units.isEmpty ? 1 : units.length * ffi.sizeOf<ffi.Uint16>(),
    );
    if (units.isNotEmpty) {
      ptr.asTypedList(units.length).setAll(0, units);
    }
    return ptr;
  }

  String _readUtf8Result(
    ffi.Pointer<NativeCodecResult> resultPtr,
    ResolvedCodec resolved,
    CodecOperation operation,
  ) {
    final Uint8List bytes = _readResultBytes(resultPtr, resolved, operation);
    return utf8.decode(bytes, allowMalformed: false);
  }

  String _readUtf16LeResult(
    ffi.Pointer<NativeCodecResult> resultPtr,
    ResolvedCodec resolved,
    CodecOperation operation,
  ) {
    final Uint8List bytes = _readResultBytes(resultPtr, resolved, operation);
    if (bytes.length.isOdd) {
      throw CodecException(
        encoding: resolved.canonicalName,
        operation: operation,
        position: 0,
        reason: 'native UTF-16LE result has an odd byte length',
      );
    }
    // FFI uses fixed little-endian UTF-16 transport, preserving valid surrogate
    // pairs and the lone surrogate code units representable by UTF-7.
    if (Endian.host == Endian.little) {
      return String.fromCharCodes(
        Uint16List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2),
      );
    }
    final ByteData data = ByteData.sublistView(bytes);
    return String.fromCharCodes(
      Iterable<int>.generate(
        bytes.length ~/ 2,
        (int index) => data.getUint16(index * 2, Endian.little),
      ),
    );
  }

  Uint8List _readBytesResult(
    ffi.Pointer<NativeCodecResult> resultPtr,
    ResolvedCodec resolved,
    CodecOperation operation,
  ) {
    final Uint8List bytes = _readResultBytes(resultPtr, resolved, operation);
    return Uint8List.fromList(bytes);
  }

  Uint8List _readResultBytes(
    ffi.Pointer<NativeCodecResult> resultPtr,
    ResolvedCodec resolved,
    CodecOperation operation,
  ) {
    if (resultPtr == ffi.nullptr) {
      throw CodecException(
        encoding: resolved.canonicalName,
        operation: operation,
        position: 0,
        reason: 'native backend returned a null result',
      );
    }
    try {
      final NativeCodecResult result = resultPtr.ref;
      if (result.status == 0) {
        if (result.dataLen == 0 || result.dataPtr == ffi.nullptr) {
          return Uint8List(0);
        }
        return Uint8List.fromList(result.dataPtr.asTypedList(result.dataLen));
      }
      String reason = 'native codec failure';
      if (result.errorMessageLen > 0 && result.errorMessagePtr != ffi.nullptr) {
        reason = utf8.decode(
          result.errorMessagePtr.asTypedList(result.errorMessageLen),
          allowMalformed: false,
        );
      }
      throw CodecException(
        encoding: resolved.canonicalName,
        operation: operation,
        position: result.errorPosition,
        reason: reason,
      );
    } finally {
      charset_codec_free_result(resultPtr);
    }
  }
}

bool? _nativeAvailable;

const NativeCodecBridge nativeCodecBridge = IoNativeCodecBridge();
