// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:charset_codec/charset_codec.dart';

void main() {
  final String decoded = decodeBytes(const <int>[
    0xE4,
    0xB8,
    0xAD,
  ], encoding: 'utf-8');
  print(decoded);

  final List<int> encoded = encodeString('A中B', encoding: 'gb18030');
  print(encoded);

  final IncrementalDecoder decoder = codec('gb18030').newDecoder();
  final String first = decoder.feed(const <int>[0xD6]);
  final String second = decoder.feed(const <int>[0xD0]);
  final String last = decoder.close();
  print('$first$second$last');
}
