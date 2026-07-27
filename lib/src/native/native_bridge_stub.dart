// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import '../codec/resolver.dart';
import '../codec_types.dart';

abstract interface class NativeCodecBridge {
  bool get isAvailable;
  String get backendName;
  bool supportsCodec(ResolvedCodec resolved);
  bool supportsIncrementalCodec(ResolvedCodec resolved);
  bool supportsOperation(ResolvedCodec resolved, CodecErrorMode errors);
  String decode(
    ResolvedCodec resolved,
    List<int> bytes, {
    required CodecErrorMode errors,
  });
  Uint8List encode(
    ResolvedCodec resolved,
    String text, {
    required CodecErrorMode errors,
  });
  bool validate(ResolvedCodec resolved, List<int> bytes);
  int createIncrementalDecoderSession(
    ResolvedCodec resolved, {
    required CodecErrorMode errors,
  });
  int createIncrementalEncoderSession(
    ResolvedCodec resolved, {
    required CodecErrorMode errors,
  });
  String feedDecoderSession(
    int handle,
    ResolvedCodec resolved,
    List<int> chunk, {
    required bool finalChunk,
  });
  Uint8List feedEncoderSession(
    int handle,
    ResolvedCodec resolved,
    String chunk, {
    required bool finalChunk,
  });
  String closeDecoderSession(int handle, ResolvedCodec resolved);
  Uint8List closeEncoderSession(int handle, ResolvedCodec resolved);
  Uint8List getIncrementalSessionState(int handle, ResolvedCodec resolved);
  void setIncrementalSessionState(
    int handle,
    ResolvedCodec resolved,
    Uint8List state,
  );
  void resetIncrementalSession(int handle, ResolvedCodec resolved);
  void destroyIncrementalSession(int handle);
  void attachIncrementalSessionFinalizer(Object owner, int handle);
  void detachIncrementalSessionFinalizer(Object owner);
}

final class StubNativeCodecBridge implements NativeCodecBridge {
  const StubNativeCodecBridge();

  @override
  bool get isAvailable => false;

  @override
  String get backendName => 'native-unavailable';

  @override
  bool supportsCodec(ResolvedCodec resolved) => false;

  @override
  bool supportsIncrementalCodec(ResolvedCodec resolved) => false;

  @override
  bool supportsOperation(ResolvedCodec resolved, CodecErrorMode errors) =>
      false;

  Never _unsupported() {
    throw UnsupportedError(
      'Native codec bridge is unavailable on this platform.',
    );
  }

  @override
  String decode(
    ResolvedCodec resolved,
    List<int> bytes, {
    required CodecErrorMode errors,
  }) => _unsupported();

  @override
  Uint8List encode(
    ResolvedCodec resolved,
    String text, {
    required CodecErrorMode errors,
  }) => _unsupported();

  @override
  bool validate(ResolvedCodec resolved, List<int> bytes) => _unsupported();

  @override
  int createIncrementalDecoderSession(
    ResolvedCodec resolved, {
    required CodecErrorMode errors,
  }) => _unsupported();

  @override
  int createIncrementalEncoderSession(
    ResolvedCodec resolved, {
    required CodecErrorMode errors,
  }) => _unsupported();

  @override
  String feedDecoderSession(
    int handle,
    ResolvedCodec resolved,
    List<int> chunk, {
    required bool finalChunk,
  }) => _unsupported();

  @override
  Uint8List feedEncoderSession(
    int handle,
    ResolvedCodec resolved,
    String chunk, {
    required bool finalChunk,
  }) => _unsupported();

  @override
  String closeDecoderSession(int handle, ResolvedCodec resolved) =>
      _unsupported();

  @override
  Uint8List closeEncoderSession(int handle, ResolvedCodec resolved) =>
      _unsupported();

  @override
  Uint8List getIncrementalSessionState(int handle, ResolvedCodec resolved) =>
      _unsupported();

  @override
  void setIncrementalSessionState(
    int handle,
    ResolvedCodec resolved,
    Uint8List state,
  ) => _unsupported();

  @override
  void resetIncrementalSession(int handle, ResolvedCodec resolved) =>
      _unsupported();

  @override
  void destroyIncrementalSession(int handle) => _unsupported();

  @override
  void attachIncrementalSessionFinalizer(Object owner, int handle) =>
      _unsupported();

  @override
  void detachIncrementalSessionFinalizer(Object owner) => _unsupported();
}

const NativeCodecBridge nativeCodecBridge = StubNativeCodecBridge();
