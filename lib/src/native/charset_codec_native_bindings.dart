// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

// ignore_for_file: type=lint
@ffi.DefaultAsset(
  'package:charset_codec/src/native/charset_codec_native_bindings.dart',
)
library;

import 'dart:ffi' as ffi;

final class NativeCodecResult extends ffi.Struct {
  @ffi.Int32()
  external int status;

  external ffi.Pointer<ffi.Uint8> dataPtr;

  @ffi.Size()
  external int dataLen;

  @ffi.Uint32()
  external int errorPosition;

  external ffi.Pointer<ffi.Uint8> errorMessagePtr;

  @ffi.Size()
  external int errorMessageLen;
}

@ffi.Native<ffi.Uint32 Function()>()
external int charset_codec_backend_abi_version();

@ffi.Native<
  ffi.Pointer<NativeCodecResult> Function(
    ffi.Uint32,
    ffi.Uint32,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
  )
>()
external ffi.Pointer<NativeCodecResult> charset_codec_decode_to_utf16le(
  int codecId,
  int errorMode,
  ffi.Pointer<ffi.Uint8> bytes,
  int length,
);

@ffi.Native<
  ffi.Pointer<NativeCodecResult> Function(
    ffi.Uint32,
    ffi.Uint32,
    ffi.Pointer<ffi.Uint16>,
    ffi.Size,
  )
>()
external ffi.Pointer<NativeCodecResult> charset_codec_encode_from_utf16(
  int codecId,
  int errorMode,
  ffi.Pointer<ffi.Uint16> utf16Units,
  int length,
);

@ffi.Native<ffi.Uint8 Function(ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)>()
external int charset_codec_validate(
  int codecId,
  ffi.Pointer<ffi.Uint8> bytes,
  int length,
);

@ffi.Native<ffi.Uint64 Function(ffi.Uint32, ffi.Uint32)>()
external int charset_codec_incremental_decoder_create(
  int codecId,
  int errorMode,
);

@ffi.Native<ffi.Uint64 Function(ffi.Uint32, ffi.Uint32)>()
external int charset_codec_incremental_encoder_create(
  int codecId,
  int errorMode,
);

@ffi.Native<
  ffi.Pointer<NativeCodecResult> Function(
    ffi.Uint64,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
    ffi.Uint8,
  )
>()
external ffi.Pointer<NativeCodecResult> charset_codec_incremental_decoder_feed(
  int handle,
  ffi.Pointer<ffi.Uint8> bytes,
  int length,
  int finalChunk,
);

@ffi.Native<
  ffi.Pointer<NativeCodecResult> Function(
    ffi.Uint64,
    ffi.Pointer<ffi.Uint16>,
    ffi.Size,
    ffi.Uint8,
  )
>()
external ffi.Pointer<NativeCodecResult>
charset_codec_incremental_encoder_feed_utf16(
  int handle,
  ffi.Pointer<ffi.Uint16> units,
  int length,
  int finalChunk,
);

@ffi.Native<ffi.Pointer<NativeCodecResult> Function(ffi.Uint64)>()
external ffi.Pointer<NativeCodecResult> charset_codec_incremental_decoder_close(
  int handle,
);

@ffi.Native<ffi.Pointer<NativeCodecResult> Function(ffi.Uint64)>()
external ffi.Pointer<NativeCodecResult> charset_codec_incremental_encoder_close(
  int handle,
);

@ffi.Native<ffi.Pointer<NativeCodecResult> Function(ffi.Uint64)>()
external ffi.Pointer<NativeCodecResult>
charset_codec_incremental_session_get_state(int handle);

@ffi.Native<
  ffi.Pointer<NativeCodecResult> Function(
    ffi.Uint64,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
  )
>()
external ffi.Pointer<NativeCodecResult>
charset_codec_incremental_session_set_state(
  int handle,
  ffi.Pointer<ffi.Uint8> stateBytes,
  int stateLength,
);

@ffi.Native<ffi.Pointer<NativeCodecResult> Function(ffi.Uint64)>()
external ffi.Pointer<NativeCodecResult> charset_codec_incremental_session_reset(
  int handle,
);

@ffi.Native<ffi.Void Function(ffi.Uint64)>()
external void charset_codec_incremental_session_destroy(int handle);

@ffi.Native<ffi.Void Function(ffi.Pointer<NativeCodecResult>)>()
external void charset_codec_free_result(ffi.Pointer<NativeCodecResult> result);
