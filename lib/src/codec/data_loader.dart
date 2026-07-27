// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import '../generated/codec_mbcs_data.g.dart';
import '../generated/codec_sbcs_data.g.dart';
import 'resolver.dart';

const int invalidCodePoint = 0xFFFFFFFF;
const int multiCodePoint = 0xFFFFFFFE;

final class DenseDecodeTable {
  DenseDecodeTable(
    this.values,
    this._multiKeys,
    this._multiOffsets,
    this._multiLengths,
    this._stringBytes,
  ) : _multiCache = List<String?>.filled(_multiKeys.length, null);

  final Uint32List values;
  final Uint32List _multiKeys;
  final Uint32List _multiOffsets;
  final Uint16List _multiLengths;
  final Uint8List _stringBytes;
  final List<String?> _multiCache;

  String? lookupMultiRune(int key) {
    final int idx = _binarySearchInt(_multiKeys, key);
    if (idx < 0) {
      return null;
    }
    return _materialize(idx);
  }

  String _materialize(int index) {
    final String? cached = _multiCache[index];
    if (cached != null) {
      return cached;
    }
    final int start = _multiOffsets[index];
    final int end = start + _multiLengths[index];
    final String value = utf8.decoder.convert(_stringBytes, start, end);
    _multiCache[index] = value;
    return value;
  }
}

final class RowCompressedDecodeTable {
  RowCompressedDecodeTable(
    this.leadToRowIndex,
    this.values,
    this._multiKeys,
    this._multiOffsets,
    this._multiLengths,
    this._stringBytes,
  ) : _multiCache = List<String?>.filled(_multiKeys.length, null);

  final Uint8List leadToRowIndex;
  final Uint32List values;
  final Uint32List _multiKeys;
  final Uint32List _multiOffsets;
  final Uint16List _multiLengths;
  final Uint8List _stringBytes;
  final List<String?> _multiCache;

  int lookupCodePoint(int b0, int b1) {
    final int row = leadToRowIndex[b0 & 0xFF];
    if (row == 0xFF) {
      return invalidCodePoint;
    }
    return values[(row << 8) | (b1 & 0xFF)];
  }

  bool hasLeadByte(int b0) => leadToRowIndex[b0 & 0xFF] != 0xFF;

  String? lookupMultiRune(int key) {
    final int idx = _binarySearchInt(_multiKeys, key);
    if (idx < 0) {
      return null;
    }
    final String? cached = _multiCache[idx];
    if (cached != null) {
      return cached;
    }
    final int start = _multiOffsets[idx];
    final int end = start + _multiLengths[idx];
    final String value = utf8.decoder.convert(_stringBytes, start, end);
    _multiCache[idx] = value;
    return value;
  }
}

final class SparseDecodeTable {
  SparseDecodeTable(
    this.keys,
    this.values,
    this._multiKeys,
    this._multiOffsets,
    this._multiLengths,
    this._stringBytes,
  ) : _multiCache = List<String?>.filled(_multiKeys.length, null);

  final Uint32List keys;
  final Uint32List values;
  final Uint32List _multiKeys;
  final Uint32List _multiOffsets;
  final Uint16List _multiLengths;
  final Uint8List _stringBytes;
  final List<String?> _multiCache;

  int lookupCodePoint(int key) {
    final int idx = _binarySearchInt(keys, key);
    if (idx < 0) {
      return invalidCodePoint;
    }
    return values[idx];
  }

  bool hasLeadByte(int b0) {
    final int lower = (b0 & 0xFF) << 16;
    return _containsIntInRange(keys, lower, lower | 0xFFFF);
  }

  bool hasLeadPair(int b0, int b1) {
    final int lower = ((b0 & 0xFF) << 16) | ((b1 & 0xFF) << 8);
    return _containsIntInRange(keys, lower, lower | 0xFF);
  }

  String? lookupMultiRune(int key) {
    final int idx = _binarySearchInt(_multiKeys, key);
    if (idx < 0) {
      return null;
    }
    final String? cached = _multiCache[idx];
    if (cached != null) {
      return cached;
    }
    final int start = _multiOffsets[idx];
    final int end = start + _multiLengths[idx];
    final String value = utf8.decoder.convert(_stringBytes, start, end);
    _multiCache[idx] = value;
    return value;
  }
}

final class PagedEncodeTable {
  const PagedEncodeTable(
    this.pageDirectory,
    this.pageValues,
    this.supplementaryKeys,
    this.supplementaryPackedValues,
  );

  final Uint16List pageDirectory;
  final Uint32List pageValues;
  final Uint32List supplementaryKeys;
  final Uint32List supplementaryPackedValues;

  int? lookupPacked(int codePoint) {
    if (codePoint <= 0xFFFF) {
      final int pageRef = pageDirectory[(codePoint >>> 8) & 0xFF];
      if (pageRef == 0) {
        return null;
      }
      final int packed = pageValues[((pageRef - 1) << 8) | (codePoint & 0xFF)];
      return packed == 0 ? null : packed;
    }
    final int idx = _binarySearchInt(supplementaryKeys, codePoint);
    if (idx < 0) {
      return null;
    }
    return supplementaryPackedValues[idx];
  }
}

final class CodecCache {
  CodecCache._();

  static Uint8List? sbcsPayload;
  static Uint8List? mbcsTablePayload;
  static Uint8List? statefulMbcsPayload;

  static final List<DenseDecodeTable?> sbcsDecode =
      List<DenseDecodeTable?>.filled(generatedSbcsCanonicalNames.length, null);
  static final List<PagedEncodeTable?> sbcsEncode =
      List<PagedEncodeTable?>.filled(generatedSbcsCanonicalNames.length, null);

  static final List<DenseDecodeTable?> mbcsSingleDecode =
      List<DenseDecodeTable?>.filled(
        generatedMultibyteDecodeTableCanonicalNames.length,
        null,
      );
  static final List<RowCompressedDecodeTable?> mbcsDoubleDecode =
      List<RowCompressedDecodeTable?>.filled(
        generatedMultibyteDecodeTableCanonicalNames.length,
        null,
      );
  static final List<SparseDecodeTable?> mbcsTripleDecode =
      List<SparseDecodeTable?>.filled(
        generatedMultibyteDecodeTableCanonicalNames.length,
        null,
      );
  static final List<PagedEncodeTable?> mbcsEncode =
      List<PagedEncodeTable?>.filled(
        generatedMultibyteDecodeTableCanonicalNames.length,
        null,
      );

  static DenseDecodeTable? gb18030DoubleDecode;
  static PagedEncodeTable? gb18030DoubleEncode;
  static final List<DenseDecodeTable?> iso2022SetDecode =
      List<DenseDecodeTable?>.filled(generatedIso2022SetIds.length, null);
  static final List<PagedEncodeTable?> iso2022SetEncode =
      List<PagedEncodeTable?>.filled(generatedIso2022SetIds.length, null);
  static DenseDecodeTable? hzDecode;
  static PagedEncodeTable? hzEncode;
  static DenseDecodeTable? iso2022KrDecode;
  static PagedEncodeTable? iso2022KrEncode;

  static void resetForTesting() {
    sbcsPayload = null;
    mbcsTablePayload = null;
    statefulMbcsPayload = null;

    for (int i = 0; i < sbcsDecode.length; i++) {
      sbcsDecode[i] = null;
      sbcsEncode[i] = null;
    }
    for (int i = 0; i < mbcsSingleDecode.length; i++) {
      mbcsSingleDecode[i] = null;
      mbcsDoubleDecode[i] = null;
      mbcsTripleDecode[i] = null;
      mbcsEncode[i] = null;
    }
    gb18030DoubleDecode = null;
    gb18030DoubleEncode = null;
    for (int i = 0; i < iso2022SetDecode.length; i++) {
      iso2022SetDecode[i] = null;
      iso2022SetEncode[i] = null;
    }
    hzDecode = null;
    hzEncode = null;
    iso2022KrDecode = null;
    iso2022KrEncode = null;
  }
}

final class CodecDataLoader {
  CodecDataLoader._();

  static DenseDecodeTable? loadSbcsDecodeTable(int codecId) {
    final int familyIndex = generatedSbcsFamilyIndexByCodecId[codecId];
    if (familyIndex < 0) {
      return null;
    }
    final DenseDecodeTable? cached = CodecCache.sbcsDecode[familyIndex];
    if (cached != null) {
      return cached;
    }
    final Uint8List payload = _loadSbcsPayload();
    final DenseDecodeTable parsed = _parseDenseDecode(
      payload,
      generatedSbcsDecodeOffsets[familyIndex],
      generatedSbcsDecodeLengths[familyIndex],
    );
    CodecCache.sbcsDecode[familyIndex] = parsed;
    return parsed;
  }

  static PagedEncodeTable? loadSbcsEncodeTable(int codecId) {
    final int familyIndex = generatedSbcsFamilyIndexByCodecId[codecId];
    if (familyIndex < 0) {
      return null;
    }
    final PagedEncodeTable? cached = CodecCache.sbcsEncode[familyIndex];
    if (cached != null) {
      return cached;
    }
    final Uint8List payload = _loadSbcsPayload();
    final PagedEncodeTable parsed = _parsePagedEncode(
      payload,
      generatedSbcsEncodeOffsets[familyIndex],
      generatedSbcsEncodeLengths[familyIndex],
    );
    CodecCache.sbcsEncode[familyIndex] = parsed;
    return parsed;
  }

  static DenseDecodeTable? loadMbcsSingleByteDecodeTable(int codecId) {
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    if (familyIndex < 0) {
      return null;
    }
    final DenseDecodeTable? cached = CodecCache.mbcsSingleDecode[familyIndex];
    if (cached != null) {
      return cached;
    }
    final Uint8List payload = _loadMbcsTablePayload();
    final DenseDecodeTable parsed = _parseDenseDecode(
      payload,
      generatedMbcsSingleDecodeOffsets[familyIndex],
      generatedMbcsSingleDecodeLengths[familyIndex],
    );
    CodecCache.mbcsSingleDecode[familyIndex] = parsed;
    return parsed;
  }

  static RowCompressedDecodeTable? loadMbcsDoubleByteDecodeTable(int codecId) {
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    if (familyIndex < 0) {
      return null;
    }
    final RowCompressedDecodeTable? cached =
        CodecCache.mbcsDoubleDecode[familyIndex];
    if (cached != null) {
      return cached;
    }
    final Uint8List payload = _loadMbcsTablePayload();
    final RowCompressedDecodeTable parsed = _parseRowCompressedDoubleDecode(
      payload,
      generatedMbcsDoubleDecodeOffsets[familyIndex],
      generatedMbcsDoubleDecodeLengths[familyIndex],
    );
    CodecCache.mbcsDoubleDecode[familyIndex] = parsed;
    return parsed;
  }

  static SparseDecodeTable? loadMbcsTripleByteDecodeTable(int codecId) {
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    if (familyIndex < 0) {
      return null;
    }
    final SparseDecodeTable? cached = CodecCache.mbcsTripleDecode[familyIndex];
    if (cached != null) {
      return cached;
    }
    final Uint8List payload = _loadMbcsTablePayload();
    final SparseDecodeTable parsed = _parseSparseDecode(
      payload,
      generatedMbcsTripleDecodeOffsets[familyIndex],
      generatedMbcsTripleDecodeLengths[familyIndex],
    );
    CodecCache.mbcsTripleDecode[familyIndex] = parsed;
    return parsed;
  }

  static PagedEncodeTable? loadMbcsEncodeTable(int codecId) {
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    if (familyIndex < 0) {
      return null;
    }
    final PagedEncodeTable? cached = CodecCache.mbcsEncode[familyIndex];
    if (cached != null) {
      return cached;
    }
    final Uint8List payload = _loadMbcsTablePayload();
    final PagedEncodeTable parsed = _parsePagedEncode(
      payload,
      generatedMbcsEncodeOffsets[familyIndex],
      generatedMbcsEncodeLengths[familyIndex],
    );
    CodecCache.mbcsEncode[familyIndex] = parsed;
    return parsed;
  }

  static DenseDecodeTable loadGb18030DoubleByteDecodeTable() {
    final DenseDecodeTable? cached = CodecCache.gb18030DoubleDecode;
    if (cached != null) {
      return cached;
    }
    final DenseDecodeTable parsed = _parseDenseDecode(
      _loadStatefulMbcsPayload(),
      generatedGb18030DoubleDecodeOffset,
      generatedGb18030DoubleDecodeLength,
    );
    CodecCache.gb18030DoubleDecode = parsed;
    return parsed;
  }

  static PagedEncodeTable loadGb18030DoubleByteEncodeTable() {
    final PagedEncodeTable? cached = CodecCache.gb18030DoubleEncode;
    if (cached != null) {
      return cached;
    }
    final PagedEncodeTable parsed = _parsePagedEncode(
      _loadStatefulMbcsPayload(),
      generatedGb18030DoubleEncodeOffset,
      generatedGb18030DoubleEncodeLength,
    );
    CodecCache.gb18030DoubleEncode = parsed;
    return parsed;
  }

  static DenseDecodeTable? loadIso2022SetDecodeTable(String setId) {
    final int setIndex = generatedIso2022SetIds.indexOf(setId);
    if (setIndex < 0) {
      return null;
    }
    final DenseDecodeTable? cached = CodecCache.iso2022SetDecode[setIndex];
    if (cached != null) {
      return cached;
    }
    final DenseDecodeTable parsed = _parseDenseDecode(
      _loadStatefulMbcsPayload(),
      generatedIso2022SetDecodeOffsets[setIndex],
      generatedIso2022SetDecodeLengths[setIndex],
    );
    CodecCache.iso2022SetDecode[setIndex] = parsed;
    return parsed;
  }

  static PagedEncodeTable? loadIso2022SetEncodeTable(String setId) {
    final int setIndex = generatedIso2022SetIds.indexOf(setId);
    if (setIndex < 0) {
      return null;
    }
    final PagedEncodeTable? cached = CodecCache.iso2022SetEncode[setIndex];
    if (cached != null) {
      return cached;
    }
    final PagedEncodeTable parsed = _parsePagedEncode(
      _loadStatefulMbcsPayload(),
      generatedIso2022SetEncodeOffsets[setIndex],
      generatedIso2022SetEncodeLengths[setIndex],
    );
    CodecCache.iso2022SetEncode[setIndex] = parsed;
    return parsed;
  }

  static DenseDecodeTable loadHzDecodeTable() {
    final DenseDecodeTable? cached = CodecCache.hzDecode;
    if (cached != null) {
      return cached;
    }
    final DenseDecodeTable parsed = _parseDenseDecode(
      _loadStatefulMbcsPayload(),
      generatedHzDecodeOffset,
      generatedHzDecodeLength,
    );
    CodecCache.hzDecode = parsed;
    return parsed;
  }

  static PagedEncodeTable loadHzEncodeTable() {
    final PagedEncodeTable? cached = CodecCache.hzEncode;
    if (cached != null) {
      return cached;
    }
    final PagedEncodeTable parsed = _parsePagedEncode(
      _loadStatefulMbcsPayload(),
      generatedHzEncodeOffset,
      generatedHzEncodeLength,
    );
    CodecCache.hzEncode = parsed;
    return parsed;
  }

  static DenseDecodeTable loadIso2022KrDecodeTable() {
    final DenseDecodeTable? cached = CodecCache.iso2022KrDecode;
    if (cached != null) {
      return cached;
    }
    final DenseDecodeTable parsed = _parseDenseDecode(
      _loadStatefulMbcsPayload(),
      generatedIso2022KrDecodeOffset,
      generatedIso2022KrDecodeLength,
    );
    CodecCache.iso2022KrDecode = parsed;
    return parsed;
  }

  static PagedEncodeTable loadIso2022KrEncodeTable() {
    final PagedEncodeTable? cached = CodecCache.iso2022KrEncode;
    if (cached != null) {
      return cached;
    }
    final PagedEncodeTable parsed = _parsePagedEncode(
      _loadStatefulMbcsPayload(),
      generatedIso2022KrEncodeOffset,
      generatedIso2022KrEncodeLength,
    );
    CodecCache.iso2022KrEncode = parsed;
    return parsed;
  }

  static int packedLength(int packed) => (packed >>> 24) & 0xFF;

  static int packedByteAt(int packed, int index) {
    switch (index) {
      case 0:
        return (packed >>> 16) & 0xFF;
      case 1:
        return (packed >>> 8) & 0xFF;
      case 2:
        return packed & 0xFF;
      default:
        throw RangeError.range(index, 0, 2, 'index');
    }
  }

  static void appendPackedBytes(List<int> out, int packed) {
    final int len = packedLength(packed);
    if (len >= 1) {
      out.add(packedByteAt(packed, 0));
    }
    if (len >= 2) {
      out.add(packedByteAt(packed, 1));
    }
    if (len >= 3) {
      out.add(packedByteAt(packed, 2));
    }
  }

  static bool isSbcsEncodeLoaded(String codec) {
    final int? codecId = resolveCodecId(codec);
    if (codecId == null) {
      return false;
    }
    final int familyIndex = generatedSbcsFamilyIndexByCodecId[codecId];
    return familyIndex >= 0 && CodecCache.sbcsEncode[familyIndex] != null;
  }

  static bool isMbcsEncodeLoaded(String codec) {
    final int? codecId = resolveCodecId(codec);
    if (codecId == null) {
      return false;
    }
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    return familyIndex >= 0 && CodecCache.mbcsEncode[familyIndex] != null;
  }

  static bool isMbcsDecodeLoaded(String codec) {
    return isMbcsSingleDecodeLoaded(codec) ||
        isMbcsDoubleDecodeLoaded(codec) ||
        isMbcsTripleDecodeLoaded(codec);
  }

  static bool isMbcsSingleDecodeLoaded(String codec) {
    final int? codecId = resolveCodecId(codec);
    if (codecId == null) {
      return false;
    }
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    return familyIndex >= 0 && CodecCache.mbcsSingleDecode[familyIndex] != null;
  }

  static bool isMbcsDoubleDecodeLoaded(String codec) {
    final int? codecId = resolveCodecId(codec);
    if (codecId == null) {
      return false;
    }
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    return familyIndex >= 0 && CodecCache.mbcsDoubleDecode[familyIndex] != null;
  }

  static bool isMbcsTripleDecodeLoaded(String codec) {
    final int? codecId = resolveCodecId(codec);
    if (codecId == null) {
      return false;
    }
    final int familyIndex = generatedMbcsTableFamilyIndexByCodecId[codecId];
    return familyIndex >= 0 && CodecCache.mbcsTripleDecode[familyIndex] != null;
  }

  static void resetCachesForTesting() => CodecCache.resetForTesting();
}

Uint8List _decodePackedPayload(String payload) {
  if (payload.isEmpty) {
    return Uint8List(0);
  }
  final int groupCount = payload.length ~/ 5;
  if (groupCount * 5 != payload.length) {
    throw StateError('corrupt payload blob: invalid base85 length');
  }

  final Uint8List framed = Uint8List(groupCount * 4);
  int outIndex = 0;
  for (int i = 0; i < payload.length; i += 5) {
    int value = 0;
    for (int j = 0; j < 5; j++) {
      final int codeUnit = payload.codeUnitAt(i + j);
      if (codeUnit >= _base85DecodeTable.length) {
        throw StateError('corrupt payload blob: unsupported base85 byte');
      }
      final int digit = _base85DecodeTable[codeUnit];
      if (digit == 0xFF) {
        throw StateError('corrupt payload blob: invalid base85 digit');
      }
      value = (value * 85) + digit;
    }
    framed[outIndex++] = (value >>> 24) & 0xFF;
    framed[outIndex++] = (value >>> 16) & 0xFF;
    framed[outIndex++] = (value >>> 8) & 0xFF;
    framed[outIndex++] = value & 0xFF;
  }

  if (framed.length < 4) {
    throw StateError('corrupt payload blob: missing length header');
  }

  final int payloadLength =
      framed[0] | (framed[1] << 8) | (framed[2] << 16) | (framed[3] << 24);
  if (payloadLength < 0 || payloadLength > framed.length - 4) {
    throw StateError('corrupt payload blob: invalid decoded length');
  }
  return Uint8List.sublistView(framed, 4, 4 + payloadLength);
}

const String _base85Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    '!#\$%&()*+-;<=>?@^_`{|}~';

final Uint8List _base85DecodeTable = () {
  final Uint8List table = Uint8List(128);
  table.fillRange(0, table.length, 0xFF);
  for (int i = 0; i < _base85Alphabet.length; i++) {
    table[_base85Alphabet.codeUnitAt(i)] = i;
  }
  return table;
}();

Uint8List _loadSbcsPayload() =>
    CodecCache.sbcsPayload ??= _decodePackedPayload(generatedSbcsPayloadBase85);

Uint8List _loadMbcsTablePayload() => CodecCache.mbcsTablePayload ??=
    _decodePackedPayload(generatedMbcsTablePayloadBase85);

Uint8List _loadStatefulMbcsPayload() => CodecCache.statefulMbcsPayload ??=
    _decodePackedPayload(generatedStatefulMbcsPayloadBase85);

DenseDecodeTable _parseDenseDecode(Uint8List bytes, int offset, int length) {
  final ByteData bd = ByteData.sublistView(bytes, offset, offset + length);
  if (length < 8) {
    throw StateError('corrupt dense decode blob: too short');
  }
  final int count = bd.getUint32(0, Endian.little);
  int cursor = 4;
  final int tableBytes = count * 4;
  if (cursor + tableBytes + 4 > length) {
    throw StateError('corrupt dense decode blob: truncated table');
  }
  final Uint32List values = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    count,
  );
  cursor += tableBytes;
  final int sideCount = bd.getUint32(cursor, Endian.little);
  cursor += 4;
  final Uint32List sideKeys = Uint32List(sideCount);
  final Uint32List sideOffsets = Uint32List(sideCount);
  final Uint16List sideLengths = Uint16List(sideCount);
  for (int i = 0; i < sideCount; i++) {
    if (cursor + 6 > length) {
      throw StateError(
        'corrupt dense decode blob: truncated side entry header',
      );
    }
    sideKeys[i] = bd.getUint32(cursor, Endian.little);
    cursor += 4;
    final int sideLength = bd.getUint16(cursor, Endian.little);
    sideLengths[i] = sideLength;
    cursor += 2;
    if (cursor + sideLength > length) {
      throw StateError(
        'corrupt dense decode blob: truncated side entry payload',
      );
    }
    sideOffsets[i] = offset + cursor;
    cursor += sideLength;
  }
  return DenseDecodeTable(values, sideKeys, sideOffsets, sideLengths, bytes);
}

RowCompressedDecodeTable _parseRowCompressedDoubleDecode(
  Uint8List bytes,
  int offset,
  int length,
) {
  final ByteData bd = ByteData.sublistView(bytes, offset, offset + length);
  if (length < 2 + 256 + 2 + 4) {
    throw StateError('corrupt row-compressed decode blob: too short');
  }
  int cursor = 0;
  final int activeRowCount = bd.getUint16(cursor, Endian.little);
  cursor += 2;
  if (activeRowCount > 256) {
    throw StateError('corrupt row-compressed decode blob: too many rows');
  }
  final Uint8List leadToRowIndex = Uint8List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    256,
  );
  cursor += 256;
  cursor += 2;
  final int valuesCount = activeRowCount * 256;
  final int valuesBytes = valuesCount * 4;
  if (cursor + valuesBytes + 4 > length) {
    throw StateError('corrupt row-compressed decode blob: truncated rows');
  }
  final Uint32List values = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    valuesCount,
  );
  cursor += valuesBytes;
  final int sideCount = bd.getUint32(cursor, Endian.little);
  cursor += 4;
  final Uint32List sideKeys = Uint32List(sideCount);
  final Uint32List sideOffsets = Uint32List(sideCount);
  final Uint16List sideLengths = Uint16List(sideCount);
  for (int i = 0; i < sideCount; i++) {
    if (cursor + 4 > length) {
      throw StateError(
        'corrupt row-compressed decode blob: truncated side entry header',
      );
    }
    sideKeys[i] = bd.getUint16(cursor, Endian.little);
    cursor += 2;
    final int sideLength = bd.getUint16(cursor, Endian.little);
    sideLengths[i] = sideLength;
    cursor += 2;
    if (cursor + sideLength > length) {
      throw StateError(
        'corrupt row-compressed decode blob: truncated side entry payload',
      );
    }
    sideOffsets[i] = offset + cursor;
    cursor += sideLength;
  }
  return RowCompressedDecodeTable(
    leadToRowIndex,
    values,
    sideKeys,
    sideOffsets,
    sideLengths,
    bytes,
  );
}

SparseDecodeTable _parseSparseDecode(Uint8List bytes, int offset, int length) {
  final ByteData bd = ByteData.sublistView(bytes, offset, offset + length);
  if (length < 4) {
    throw StateError('corrupt sparse decode blob: too short');
  }
  final int count = bd.getUint32(0, Endian.little);
  int cursor = 4;
  final int keysBytes = count * 4;
  final int valuesBytes = count * 4;
  if (cursor + keysBytes + valuesBytes + 4 > length) {
    throw StateError('corrupt sparse decode blob: truncated arrays');
  }
  final Uint32List keys = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    count,
  );
  cursor += keysBytes;
  final Uint32List values = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    count,
  );
  cursor += valuesBytes;
  final int sideCount = bd.getUint32(cursor, Endian.little);
  cursor += 4;
  final Uint32List sideKeys = Uint32List(sideCount);
  final Uint32List sideOffsets = Uint32List(sideCount);
  final Uint16List sideLengths = Uint16List(sideCount);
  for (int i = 0; i < sideCount; i++) {
    if (cursor + 6 > length) {
      throw StateError(
        'corrupt sparse decode blob: truncated side entry header',
      );
    }
    sideKeys[i] = bd.getUint32(cursor, Endian.little);
    cursor += 4;
    final int sideLength = bd.getUint16(cursor, Endian.little);
    sideLengths[i] = sideLength;
    cursor += 2;
    if (cursor + sideLength > length) {
      throw StateError(
        'corrupt sparse decode blob: truncated side entry payload',
      );
    }
    sideOffsets[i] = offset + cursor;
    cursor += sideLength;
  }
  return SparseDecodeTable(
    keys,
    values,
    sideKeys,
    sideOffsets,
    sideLengths,
    bytes,
  );
}

PagedEncodeTable _parsePagedEncode(Uint8List bytes, int offset, int length) {
  final ByteData bd = ByteData.sublistView(bytes, offset, offset + length);
  if (length < (256 * 2) + 4 + 4) {
    throw StateError('corrupt paged encode blob: too short');
  }
  int cursor = 0;
  final Uint16List pageDirectory = Uint16List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    256,
  );
  cursor += 256 * 2;
  final int pageCount = bd.getUint32(cursor, Endian.little);
  cursor += 4;
  final int pageValuesCount = pageCount * 256;
  final int pageValuesBytes = pageValuesCount * 4;
  if (cursor + pageValuesBytes + 4 > length) {
    throw StateError('corrupt paged encode blob: truncated pages');
  }
  final Uint32List pageValues = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    pageValuesCount,
  );
  cursor += pageValuesBytes;
  final int supplementaryCount = bd.getUint32(cursor, Endian.little);
  cursor += 4;
  final int supplementaryBytes = supplementaryCount * 4;
  if (cursor + supplementaryBytes * 2 > length) {
    throw StateError('corrupt paged encode blob: truncated supplementary data');
  }
  final Uint32List supplementaryKeys = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    supplementaryCount,
  );
  cursor += supplementaryBytes;
  final Uint32List supplementaryValues = Uint32List.view(
    bytes.buffer,
    bytes.offsetInBytes + offset + cursor,
    supplementaryCount,
  );
  return PagedEncodeTable(
    pageDirectory,
    pageValues,
    supplementaryKeys,
    supplementaryValues,
  );
}

int _binarySearchInt(List<int> keys, int target) {
  int low = 0;
  int high = keys.length - 1;
  while (low <= high) {
    final int mid = (low + high) >>> 1;
    final int value = keys[mid];
    if (value == target) {
      return mid;
    }
    if (value < target) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

bool _containsIntInRange(List<int> keys, int lower, int upper) {
  int low = 0;
  int high = keys.length - 1;
  while (low <= high) {
    final int mid = (low + high) >>> 1;
    final int value = keys[mid];
    if (value < lower) {
      low = mid + 1;
      continue;
    }
    if (value > upper) {
      high = mid - 1;
      continue;
    }
    return true;
  }
  return false;
}
