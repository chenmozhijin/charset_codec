# charset_codec

[English](README.md) | [简体中文](README_zh.md)

Cross-platform character encoding codecs for Dart and Flutter, with behavior
aligned with CPython's codec stack.

## Features

- Decode and encode the broad set of codecs exposed by CPython.
- Resolve canonical names and common aliases such as `utf8`, `gbk`, and
  `shift_jis`.
- Use strict, replace, ignore, backslash, XML character reference, name, and
  surrogate error modes where the selected codec supports them.
- Process large inputs asynchronously and process chunked streams with
  bounded incremental decoder and encoder state.
- Use the same public API on Dart VM, Flutter desktop/mobile, and Web.

## Installation

```bash
dart pub add charset_codec
```

## Quick Start

```dart
import 'package:charset_codec/charset_codec.dart';

void main() {
  final text = decodeBytes(
    [0xE4, 0xB8, 0xAD],
    encoding: 'utf-8',
  );
  print(text); // 中

  final bytes = encodeString('A中B', encoding: 'gb18030');
  print(bytes); // [65, 214, 208, 66]

  final maybeText = tryDecodeBytes([0xFF], encoding: 'utf-8');
  print(maybeText); // null
}
```

## Incremental Processing

Use an incremental decoder or encoder when input arrives in chunks. Call
`close()` when the stream ends so incomplete input is reported according to the
selected error mode.

```dart
import 'package:charset_codec/charset_codec.dart';

void main() {
  final decoder = codec('gb18030').newDecoder();
  final first = decoder.feed([0xD6], finalChunk: false);
  final second = decoder.feed([0xD0], finalChunk: true);
  print(first + second);
}
```

Incremental state is bounded and can be reset or transferred with `getState`
and `setState`. One-shot UTF-7 error handling follows CPython. For incremental
UTF-7 with `backslashreplace`, already emitted text is not replayed after a
later padding error; only the current offending byte is escaped so memory use
stays bounded.

## Public API

- `codec(String encoding)`: resolve a codec by canonical name or alias.
- `decodeBytes(...)` and `encodeString(...)`: strict one-shot operations by
  default.
- `tryDecodeBytes(...)` and `tryEncodeString(...)`: return `null` on failure.
- `decodeBytesAsync(...)`, `encodeStringAsync(...)`, and
  `isValidDataForEncodingAsync(...)`: asynchronous helpers for large work.
- `isValidDataForEncoding(...)`: validate bytes without returning decoded text.
- `CodecErrorMode`, `CodecException`, `CharsetCodec`, `IncrementalDecoder`,
  and `IncrementalEncoder`: public types for custom workflows.
- `lookupCodecInfo(...)` and `supportedPythonCodecNames`: inspect supported
  codec names.

## Compatibility

The package follows CPython's observable codec behavior for aliases, malformed
input, error modes, and surrogate handling. Unsupported names and strict
conversion failures throw `CodecException` with the codec, operation, and byte
or character position.

## Related Package

For charset detection rather than direct encoding and decoding, see
[`charset_normalizer_dart`](https://pub.dev/packages/charset_normalizer_dart).

## License

The package is distributed under the license in `LICENSE`. CPython-derived
metadata and other third-party materials are listed in
`THIRD_PARTY_NOTICES.md`.
