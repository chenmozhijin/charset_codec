// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

/// The conversion direction associated with a [CodecException].
enum CodecOperation {
  /// Text-to-bytes conversion.
  encode,

  /// Bytes-to-text conversion.
  decode,
}

/// Selects how malformed input or unrepresentable text is handled.
///
/// Semantics align with CPython error handlers of the same name. Some modes
/// apply only to encoding or decoding, depending on the selected codec.
enum CodecErrorMode {
  /// Throws [CodecException] at the first conversion error.
  strict,

  /// Omits malformed bytes or unrepresentable characters.
  ignore,

  /// Emits the codec's replacement character or replacement byte sequence.
  replace,

  /// Emits Python-style backslash escape sequences for invalid input.
  backslashReplace,

  /// Emits XML numeric character references while encoding.
  xmlCharRefReplace,

  /// Emits Unicode character-name escapes while encoding.
  nameReplace,

  /// Maps undecodable bytes to low surrogate code units and back.
  surrogateEscape,

  /// Allows surrogate code units where the selected Unicode codec supports it.
  surrogatePass,
}

/// A structured codec lookup or conversion failure.
/// Contains the encoding name, operation, error position, and readable reason
/// for display or logging by callers.
final class CodecException implements Exception {
  /// Creates a codec failure description.
  const CodecException({
    required this.encoding,
    required this.operation,
    required this.position,
    required this.reason,
  });

  /// The requested or resolved encoding name.
  final String encoding;

  /// Whether the failure happened while encoding or decoding.
  final CodecOperation operation;

  /// The input byte offset for decoding or text position for encoding.
  final int position;

  /// A human-readable explanation of the failure.
  final String reason;

  /// Formats all structured fields as a concise diagnostic string.
  @override
  String toString() {
    final String op = operation == CodecOperation.encode ? 'encode' : 'decode';
    return 'CodecException($op, encoding=$encoding, position=$position, reason=$reason)';
  }
}

/// Decodes a byte stream while retaining only bounded codec state.
///
/// Each [feed] call returns text that is complete at that boundary. Call
/// [close] at the end of the stream to process trailing bytes or final state.
abstract interface class IncrementalDecoder {
  /// Decodes [chunk] and returns text that is complete at this boundary.
  /// When [finalChunk] is `true`, also validates the end of the stream.
  String feed(List<int> chunk, {bool finalChunk = false});

  /// Finalizes the stream and returns any remaining text.
  /// May be called repeatedly. After the first call, [feed], [reset],
  /// [getState], and [setState] are no longer available.
  String close();

  /// Clears buffered input and shift state without closing the decoder.
  /// Clears the current decoding state so a new stream with the same codec can
  /// begin.
  void reset();

  /// Returns an opaque snapshot of the current bounded state.
  /// Pass the snapshot only to a compatible decoder created with the same codec
  /// and error mode.
  Object getState();

  /// Restores a snapshot previously returned by a compatible decoder.
  /// Throws [ArgumentError] when the state type or codec does not match.
  void setState(Object state);
}

/// Encodes a text stream while retaining only bounded codec state.
///
/// Each [feed] call returns bytes that are complete at that boundary. Call
/// [close] at the end of the stream to write trailing surrogate units or final
/// sequences.
abstract interface class IncrementalEncoder {
  /// Encodes [chunk] and returns bytes that are complete at this boundary.
  /// When [finalChunk] is `true`, finalizes the end of the stream.
  List<int> feed(String chunk, {bool finalChunk = false});

  /// Finalizes the stream and returns any remaining bytes.
  /// May be called repeatedly. After the first call, [feed], [reset],
  /// [getState], and [setState] are no longer available.
  List<int> close();

  /// Clears buffered text and shift state without closing the encoder.
  /// Clears the current encoding state so a new stream with the same codec can
  /// begin.
  void reset();

  /// Returns an opaque snapshot of the current bounded state.
  /// Pass the snapshot only to a compatible encoder created with the same codec
  /// and error mode.
  Object getState();

  /// Restores a snapshot previously returned by a compatible encoder.
  /// Throws [ArgumentError] when the state type or codec does not match.
  void setState(Object state);
}

/// Encodes, decodes, and creates incremental processors for one charset.
/// Obtain instances through the top-level `codec` function and reuse them
/// across calls. Codec tables are loaded on demand.
abstract interface class CharsetCodec {
  /// The normalized canonical codec name.
  String get name;

  /// Decodes [bytes] using this codec and [errors].
  /// Throws [CodecException] when strict conversion fails.
  String decode(
    List<int> bytes, {
    CodecErrorMode errors = CodecErrorMode.strict,
  });

  /// Encodes [text] using this codec and [errors].
  /// Returns a new byte list and throws [CodecException] when strict conversion
  /// fails.
  List<int> encode(
    String text, {
    CodecErrorMode errors = CodecErrorMode.strict,
  });

  /// Creates a bounded incremental decoder using [errors].
  /// Call [IncrementalDecoder.close] when processing is complete.
  IncrementalDecoder newDecoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  });

  /// Creates a bounded incremental encoder using [errors].
  /// Call [IncrementalEncoder.close] when processing is complete.
  IncrementalEncoder newEncoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  });
}
