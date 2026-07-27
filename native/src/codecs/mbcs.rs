// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use std::sync::OnceLock;

use super::blob_reader::{BlobReader, checked_slice};
use crate::backend::{NativeResult, err};
use crate::generated::{blobs, codec_index};

const INVALID_CP: u32 = 0xFFFF_FFFF;
const MULTI_CP: u32 = 0xFFFF_FFFE;

struct DenseDecodeTable {
    values: Vec<u32>,
    side_keys: Vec<u32>,
    side_strings: Vec<String>,
}

struct RowCompressedDecodeTable {
    lead_to_row_index: [u8; 256],
    values: Vec<u32>,
    side_keys: Vec<u16>,
    side_strings: Vec<String>,
}

struct SparseDecodeTable {
    keys: Vec<u32>,
    values: Vec<u32>,
    side_keys: Vec<u32>,
    side_strings: Vec<String>,
}

struct PagedEncodeTable {
    page_directory: [u16; 256],
    pages: Vec<u32>,
    supplementary_keys: Vec<u32>,
    supplementary_values: Vec<u32>,
}

struct MbcsCodecTables {
    max_sequence_length: u8,
    single: DenseDecodeTable,
    double: RowCompressedDecodeTable,
    triple: SparseDecodeTable,
    encode: PagedEncodeTable,
}

enum MbcsStorage {
    Hot(usize),
    Cold(usize),
}

static HOT_MBCS_TABLES: OnceLock<Vec<NativeResult<MbcsCodecTables>>> = OnceLock::new();
static COLD_MBCS_TABLES: OnceLock<Vec<NativeResult<MbcsCodecTables>>> = OnceLock::new();

pub fn supports(codec_id: u32) -> bool {
    resolve_storage(codec_id).is_some()
}

pub fn decode(codec_id: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let table = table_for_codec(codec_id)?;
    let mut out = String::with_capacity(bytes.len());
    let mut index = 0usize;
    while index < bytes.len() {
        let b0 = bytes[index];
        let cp = table.single.values[b0 as usize];
        if cp != INVALID_CP {
            if cp == MULTI_CP {
                let text = table.single.lookup_multi_rune(b0 as u32).ok_or_else(|| {
                    err(
                        index as u32,
                        "missing single-byte multi-rune decode mapping",
                    )
                })?;
                out.push_str(text);
            } else {
                let ch = char::from_u32(cp)
                    .ok_or_else(|| err(index as u32, "invalid Unicode scalar in MBCS table"))?;
                out.push(ch);
            }
            index += 1;
            continue;
        }

        if table.max_sequence_length >= 3 && index + 2 < bytes.len() {
            let b1 = bytes[index + 1];
            let b2 = bytes[index + 2];
            let key = ((b0 as u32) << 16) | ((b1 as u32) << 8) | b2 as u32;
            let cp3 = table.triple.lookup_code_point(key);
            if cp3 != INVALID_CP {
                if cp3 == MULTI_CP {
                    let text = table.triple.lookup_multi_rune(key).ok_or_else(|| {
                        err(
                            index as u32,
                            "missing triple-byte multi-rune decode mapping",
                        )
                    })?;
                    out.push_str(text);
                } else {
                    let ch = char::from_u32(cp3).ok_or_else(|| {
                        err(index as u32, "invalid Unicode scalar in triple-byte table")
                    })?;
                    out.push(ch);
                }
                index += 3;
                continue;
            }
        }

        if index + 1 < bytes.len() {
            let b1 = bytes[index + 1];
            let key = ((b0 as u16) << 8) | b1 as u16;
            let cp2 = table.double.lookup_code_point(b0, b1);
            if cp2 != INVALID_CP {
                if cp2 == MULTI_CP {
                    let text = table.double.lookup_multi_rune(key).ok_or_else(|| {
                        err(
                            index as u32,
                            "missing double-byte multi-rune decode mapping",
                        )
                    })?;
                    out.push_str(text);
                } else {
                    let ch = char::from_u32(cp2).ok_or_else(|| {
                        err(index as u32, "invalid Unicode scalar in double-byte table")
                    })?;
                    out.push(ch);
                }
                index += 2;
                continue;
            }
        }

        let incomplete = index + 1 >= bytes.len();
        return Err(err(
            index as u32,
            if incomplete {
                "incomplete multibyte sequence"
            } else {
                "invalid multibyte sequence"
            },
        ));
    }
    Ok(out.into_bytes())
}

pub fn encode(codec_id: u32, utf8_bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let text = std::str::from_utf8(utf8_bytes)
        .map_err(|error| err(error.valid_up_to() as u32, "input text was not valid UTF-8"))?;
    let table = table_for_codec(codec_id)?;
    let mut out = Vec::with_capacity(text.len());
    for (index, ch) in text.chars().enumerate() {
        let packed = lookup_paged_encode(&table.encode, ch as u32)
            .ok_or_else(|| err(index as u32, "character is not encodable in this codec"))?;
        unpack_sequence(packed, &mut out);
    }
    Ok(out)
}

pub fn validate(codec_id: u32, bytes: &[u8]) -> bool {
    match table_for_codec(codec_id) {
        Ok(table) => validate_table_backed(bytes, table),
        Err(_) => false,
    }
}

fn hot_tables() -> &'static [NativeResult<MbcsCodecTables>] {
    HOT_MBCS_TABLES
        .get_or_init(|| {
            let mut out = Vec::with_capacity(codec_index::MBCS_HOT_CANONICAL_NAMES.len());
            for family_index in 0..codec_index::MBCS_HOT_CANONICAL_NAMES.len() {
                out.push(parse_hot_mbcs_tables(family_index));
            }
            out
        })
        .as_slice()
}

fn cold_tables() -> &'static [NativeResult<MbcsCodecTables>] {
    COLD_MBCS_TABLES
        .get_or_init(|| {
            let mut out = Vec::with_capacity(codec_index::MBCS_COLD_CANONICAL_NAMES.len());
            for family_index in 0..codec_index::MBCS_COLD_CANONICAL_NAMES.len() {
                out.push(parse_cold_mbcs_tables(family_index));
            }
            out
        })
        .as_slice()
}

fn parse_hot_mbcs_tables(family_index: usize) -> NativeResult<MbcsCodecTables> {
    let blob = hot_blob(family_index)?;
    let single = parse_dense_decode(checked_slice(
        blob,
        codec_index::MBCS_HOT_SINGLE_OFFSETS[family_index] as usize,
        codec_index::MBCS_HOT_SINGLE_LENGTHS[family_index] as usize,
        "hot MBCS single-byte table",
    )?)?;
    let double = parse_row_compressed_decode(checked_slice(
        blob,
        codec_index::MBCS_HOT_DOUBLE_OFFSETS[family_index] as usize,
        codec_index::MBCS_HOT_DOUBLE_LENGTHS[family_index] as usize,
        "hot MBCS double-byte table",
    )?)?;
    let triple = parse_sparse_decode(checked_slice(
        blob,
        codec_index::MBCS_HOT_TRIPLE_OFFSETS[family_index] as usize,
        codec_index::MBCS_HOT_TRIPLE_LENGTHS[family_index] as usize,
        "hot MBCS triple-byte table",
    )?)?;
    let encode = parse_paged_encode(checked_slice(
        blob,
        codec_index::MBCS_HOT_ENCODE_OFFSETS[family_index] as usize,
        codec_index::MBCS_HOT_ENCODE_LENGTHS[family_index] as usize,
        "hot MBCS encode table",
    )?)?;
    Ok(MbcsCodecTables {
        max_sequence_length: codec_index::MBCS_HOT_MAX_SEQUENCE_LENGTHS[family_index],
        single,
        double,
        triple,
        encode,
    })
}

fn parse_cold_mbcs_tables(family_index: usize) -> NativeResult<MbcsCodecTables> {
    let blob = blobs::MBCS_COLD_TABLES;
    let single = parse_dense_decode(checked_slice(
        blob,
        codec_index::MBCS_COLD_SINGLE_OFFSETS[family_index] as usize,
        codec_index::MBCS_COLD_SINGLE_LENGTHS[family_index] as usize,
        "cold MBCS single-byte table",
    )?)?;
    let double = parse_row_compressed_decode(checked_slice(
        blob,
        codec_index::MBCS_COLD_DOUBLE_OFFSETS[family_index] as usize,
        codec_index::MBCS_COLD_DOUBLE_LENGTHS[family_index] as usize,
        "cold MBCS double-byte table",
    )?)?;
    let triple = parse_sparse_decode(checked_slice(
        blob,
        codec_index::MBCS_COLD_TRIPLE_OFFSETS[family_index] as usize,
        codec_index::MBCS_COLD_TRIPLE_LENGTHS[family_index] as usize,
        "cold MBCS triple-byte table",
    )?)?;
    let encode = parse_paged_encode(checked_slice(
        blob,
        codec_index::MBCS_COLD_ENCODE_OFFSETS[family_index] as usize,
        codec_index::MBCS_COLD_ENCODE_LENGTHS[family_index] as usize,
        "cold MBCS encode table",
    )?)?;
    Ok(MbcsCodecTables {
        max_sequence_length: codec_index::MBCS_COLD_MAX_SEQUENCE_LENGTHS[family_index],
        single,
        double,
        triple,
        encode,
    })
}

fn hot_blob(family_index: usize) -> NativeResult<&'static [u8]> {
    match codec_index::MBCS_HOT_CANONICAL_NAMES
        .get(family_index)
        .copied()
    {
        Some("big5") => Ok(blobs::MBCS_HOT_BIG5_TABLES),
        Some("cp932") => Ok(blobs::MBCS_HOT_CP932_TABLES),
        Some("euc-jp") => Ok(blobs::MBCS_HOT_EUC_JP_TABLES),
        Some("euc-kr") => Ok(blobs::MBCS_HOT_EUC_KR_TABLES),
        Some("gbk") => Ok(blobs::MBCS_HOT_GBK_TABLES),
        Some("shift_jis") => Ok(blobs::MBCS_HOT_SHIFT_JIS_TABLES),
        Some(other) => Err(err(
            0,
            format!("generated metadata references unsupported hot MBCS blob: {other}"),
        )),
        None => Err(err(
            0,
            "hot MBCS family index is outside generated metadata",
        )),
    }
}

fn resolve_storage(codec_id: u32) -> Option<MbcsStorage> {
    if let Some(family_index) = codec_index::mbcs_hot_family_index(codec_id) {
        return Some(MbcsStorage::Hot(family_index));
    }
    codec_index::mbcs_cold_family_index(codec_id).map(MbcsStorage::Cold)
}

fn table_for_codec(codec_id: u32) -> NativeResult<&'static MbcsCodecTables> {
    let (tables, family_index) = match resolve_storage(codec_id) {
        Some(MbcsStorage::Hot(family_index)) => Ok((hot_tables(), family_index)),
        Some(MbcsStorage::Cold(family_index)) => Ok((cold_tables(), family_index)),
        None => Err(err(0, "codec is not mapped to native MBCS tables")),
    }?;
    match tables.get(family_index) {
        Some(Ok(table)) => Ok(table),
        Some(Err(error)) => Err(error.clone()),
        None => Err(err(0, "MBCS family index is outside generated metadata")),
    }
}

fn validate_table_backed(bytes: &[u8], table: &MbcsCodecTables) -> bool {
    let mut index = 0usize;
    while index < bytes.len() {
        let b0 = bytes[index];
        if is_complete_single_byte(&table.single, b0) {
            index += 1;
            continue;
        }

        if table.max_sequence_length >= 3
            && index + 2 < bytes.len()
            && is_complete_triple_byte(&table.triple, b0, bytes[index + 1], bytes[index + 2])
        {
            index += 3;
            continue;
        }

        if index + 1 < bytes.len() && is_complete_double_byte(&table.double, b0, bytes[index + 1]) {
            index += 2;
            continue;
        }

        return false;
    }
    true
}

fn is_complete_single_byte(table: &DenseDecodeTable, b0: u8) -> bool {
    let cp = table.values[b0 as usize];
    if cp == INVALID_CP {
        return false;
    }
    cp != MULTI_CP || table.lookup_multi_rune(b0 as u32).is_some()
}

fn is_complete_double_byte(table: &RowCompressedDecodeTable, b0: u8, b1: u8) -> bool {
    let key = ((b0 as u16) << 8) | b1 as u16;
    let cp = table.lookup_code_point(b0, b1);
    if cp == INVALID_CP {
        return false;
    }
    cp != MULTI_CP || table.lookup_multi_rune(key).is_some()
}

fn is_complete_triple_byte(table: &SparseDecodeTable, b0: u8, b1: u8, b2: u8) -> bool {
    let key = ((b0 as u32) << 16) | ((b1 as u32) << 8) | b2 as u32;
    let cp = table.lookup_code_point(key);
    if cp == INVALID_CP {
        return false;
    }
    cp != MULTI_CP || table.lookup_multi_rune(key).is_some()
}

impl DenseDecodeTable {
    fn lookup_multi_rune(&self, key: u32) -> Option<&str> {
        lookup_side_string_u32(&self.side_keys, &self.side_strings, key)
    }
}

impl RowCompressedDecodeTable {
    fn lookup_code_point(&self, b0: u8, b1: u8) -> u32 {
        let row = self.lead_to_row_index[b0 as usize];
        if row == 0xFF {
            return INVALID_CP;
        }
        self.values[((row as usize) << 8) | b1 as usize]
    }

    fn lookup_multi_rune(&self, key: u16) -> Option<&str> {
        lookup_side_string_u16(&self.side_keys, &self.side_strings, key)
    }
}

impl SparseDecodeTable {
    fn lookup_code_point(&self, key: u32) -> u32 {
        match self.keys.binary_search(&key) {
            Ok(index) => self.values[index],
            Err(_) => INVALID_CP,
        }
    }

    fn lookup_multi_rune(&self, key: u32) -> Option<&str> {
        lookup_side_string_u32(&self.side_keys, &self.side_strings, key)
    }
}

fn parse_dense_decode(blob: &[u8]) -> NativeResult<DenseDecodeTable> {
    let mut reader = BlobReader::new(blob, "MBCS dense decode table");
    let count = reader.read_u32()? as usize;
    if count != 256 {
        return Err(err(
            0,
            "corrupt MBCS single-byte table: expected 256 entries",
        ));
    }
    let values = reader.read_u32_vec(count)?;
    let side_count = reader.read_u32()? as usize;
    let mut side_keys = Vec::with_capacity(side_count);
    let mut side_strings = Vec::with_capacity(side_count);
    for _ in 0..side_count {
        let key = reader.read_u32()?;
        let utf8_len = reader.read_u16()? as usize;
        let text = reader.read_utf8_string(utf8_len)?;
        side_keys.push(key);
        side_strings.push(text);
    }
    validate_sorted_u32(&side_keys, "MBCS dense side keys")?;
    reader.finish()?;
    Ok(DenseDecodeTable {
        values,
        side_keys,
        side_strings,
    })
}

fn parse_row_compressed_decode(blob: &[u8]) -> NativeResult<RowCompressedDecodeTable> {
    let mut reader = BlobReader::new(blob, "MBCS row-compressed decode table");
    let active_row_count = reader.read_u16()? as usize;
    let mut lead_to_row_index = [0u8; 256];
    lead_to_row_index.copy_from_slice(reader.read_bytes(256)?);
    if reader.read_u16()? != 0 {
        return Err(err(
            0,
            "corrupt MBCS row table: alignment field is not zero",
        ));
    }
    if lead_to_row_index
        .iter()
        .any(|row| *row != 0xFF && *row as usize >= active_row_count)
    {
        return Err(err(0, "corrupt MBCS row table: row index is out of range"));
    }
    let value_count = active_row_count
        .checked_mul(256)
        .ok_or_else(|| err(0, "corrupt MBCS row table: row count overflow"))?;
    let values = reader.read_u32_vec(value_count)?;
    let side_count = reader.read_u32()? as usize;
    let mut side_keys = Vec::with_capacity(side_count);
    let mut side_strings = Vec::with_capacity(side_count);
    for _ in 0..side_count {
        let key = reader.read_u16()?;
        let utf8_len = reader.read_u16()? as usize;
        let text = reader.read_utf8_string(utf8_len)?;
        side_keys.push(key);
        side_strings.push(text);
    }
    validate_sorted_u16(&side_keys, "MBCS row-compressed side keys")?;
    reader.finish()?;
    Ok(RowCompressedDecodeTable {
        lead_to_row_index,
        values,
        side_keys,
        side_strings,
    })
}

fn parse_sparse_decode(blob: &[u8]) -> NativeResult<SparseDecodeTable> {
    let mut reader = BlobReader::new(blob, "MBCS sparse decode table");
    let count = reader.read_u32()? as usize;
    let keys = reader.read_u32_vec(count)?;
    let values = reader.read_u32_vec(count)?;
    validate_sorted_u32(&keys, "MBCS sparse keys")?;
    let side_count = reader.read_u32()? as usize;
    let mut side_keys = Vec::with_capacity(side_count);
    let mut side_strings = Vec::with_capacity(side_count);
    for _ in 0..side_count {
        let key = reader.read_u32()?;
        let utf8_len = reader.read_u16()? as usize;
        let text = reader.read_utf8_string(utf8_len)?;
        side_keys.push(key);
        side_strings.push(text);
    }
    validate_sorted_u32(&side_keys, "MBCS sparse side keys")?;
    reader.finish()?;
    Ok(SparseDecodeTable {
        keys,
        values,
        side_keys,
        side_strings,
    })
}

fn parse_paged_encode(blob: &[u8]) -> NativeResult<PagedEncodeTable> {
    let mut reader = BlobReader::new(blob, "MBCS paged encode table");
    let mut page_directory = [0u16; 256];
    for entry in &mut page_directory {
        *entry = reader.read_u16()?;
    }
    let page_count = reader.read_u32()? as usize;
    let page_value_count = page_count
        .checked_mul(256)
        .ok_or_else(|| err(0, "corrupt MBCS encode table: page count overflow"))?;
    let pages = reader.read_u32_vec(page_value_count)?;
    if page_directory
        .iter()
        .any(|page| *page != 0 && *page as usize > page_count)
    {
        return Err(err(
            0,
            "corrupt MBCS encode table: page directory index is out of range",
        ));
    }
    let supplementary_count = reader.read_u32()? as usize;
    let supplementary_keys = reader.read_u32_vec(supplementary_count)?;
    let supplementary_values = reader.read_u32_vec(supplementary_count)?;
    validate_sorted_u32(&supplementary_keys, "MBCS supplementary encode keys")?;
    reader.finish()?;
    Ok(PagedEncodeTable {
        page_directory,
        pages,
        supplementary_keys,
        supplementary_values,
    })
}

fn validate_sorted_u16(values: &[u16], context: &str) -> NativeResult<()> {
    if values.windows(2).all(|pair| pair[0] < pair[1]) {
        return Ok(());
    }
    Err(err(0, format!("corrupt {context}: keys are not sorted")))
}

fn validate_sorted_u32(values: &[u32], context: &str) -> NativeResult<()> {
    if values.windows(2).all(|pair| pair[0] < pair[1]) {
        return Ok(());
    }
    Err(err(0, format!("corrupt {context}: keys are not sorted")))
}

fn lookup_paged_encode(table: &PagedEncodeTable, scalar: u32) -> Option<u32> {
    if scalar <= 0xFFFF {
        let page = table.page_directory[(scalar >> 8) as usize];
        if page == 0 {
            return None;
        }
        let page_index = (page as usize - 1) * 256;
        let packed = table.pages[page_index + (scalar as usize & 0xFF)];
        return (packed != 0).then_some(packed);
    }
    match table.supplementary_keys.binary_search(&scalar) {
        Ok(index) => Some(table.supplementary_values[index]),
        Err(_) => None,
    }
}

fn unpack_sequence(packed: u32, out: &mut Vec<u8>) {
    let length = (packed >> 24) as usize;
    if length >= 1 {
        out.push(((packed >> 16) & 0xFF) as u8);
    }
    if length >= 2 {
        out.push(((packed >> 8) & 0xFF) as u8);
    }
    if length >= 3 {
        out.push((packed & 0xFF) as u8);
    }
}

fn lookup_side_string_u16<'a>(keys: &[u16], values: &'a [String], key: u16) -> Option<&'a str> {
    match keys.binary_search(&key) {
        Ok(index) => Some(values[index].as_str()),
        Err(_) => None,
    }
}

fn lookup_side_string_u32<'a>(keys: &[u32], values: &'a [String], key: u32) -> Option<&'a str> {
    match keys.binary_search(&key) {
        Ok(index) => Some(values[index].as_str()),
        Err(_) => None,
    }
}
