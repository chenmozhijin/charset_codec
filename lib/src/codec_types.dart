// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

enum CodecOperation { encode, decode }

enum CodecErrorMode {
  strict,
  ignore,
  replace,
  backslashReplace,
  xmlCharRefReplace,
  nameReplace,
  surrogateEscape,
  surrogatePass,
}

final class CodecException implements Exception {
  const CodecException({
    required this.encoding,
    required this.operation,
    required this.position,
    required this.reason,
  });

  final String encoding;
  final CodecOperation operation;
  final int position;
  final String reason;

  @override
  String toString() {
    final String op = operation == CodecOperation.encode ? 'encode' : 'decode';
    return 'CodecException($op, encoding=$encoding, position=$position, reason=$reason)';
  }
}

abstract interface class IncrementalDecoder {
  String feed(List<int> chunk, {bool finalChunk = false});
  String close();
  void reset();
  Object getState();
  void setState(Object state);
}

abstract interface class IncrementalEncoder {
  List<int> feed(String chunk, {bool finalChunk = false});
  List<int> close();
  void reset();
  Object getState();
  void setState(Object state);
}

abstract interface class CharsetCodec {
  String get name;
  String decode(
    List<int> bytes, {
    CodecErrorMode errors = CodecErrorMode.strict,
  });
  List<int> encode(
    String text, {
    CodecErrorMode errors = CodecErrorMode.strict,
  });
  IncrementalDecoder newDecoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  });
  IncrementalEncoder newEncoder({
    CodecErrorMode errors = CodecErrorMode.strict,
  });
}
