// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use std::sync::OnceLock;

use super::blob_reader::{BlobReader, checked_slice};
use crate::backend::{NativeResult, err};
use crate::generated::{blobs, codec_index};

const INVALID_CP: u32 = 0xFFFF_FFFF;
const MULTI_CP: u32 = 0xFFFF_FFFE;
const GB18030_CODEC_NAME: &str = "gb18030";
const GB18030_BMP_POINTER_LIMIT: u32 = 39_420;

struct DenseDecodeTable {
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

#[derive(Clone, Copy)]
struct Gb18030Range {
    first: u32,
    last: u32,
    base: u32,
}

struct Gb18030Tables {
    double_decode: DenseDecodeTable,
    double_encode: PagedEncodeTable,
    bmp_ranges: Vec<Gb18030Range>,
}

static GB18030_TABLES: OnceLock<NativeResult<Gb18030Tables>> = OnceLock::new();

pub fn supports(codec_id: u32) -> bool {
    codec_index::canonical_name(codec_id) == GB18030_CODEC_NAME
}

pub fn decode(codec_id: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let (decoded, consumed) = decode_prefix(codec_id, bytes, true)?;
    if consumed != bytes.len() {
        return Err(err(
            consumed as u32,
            "native gb18030 decoder left unconsumed input",
        ));
    }
    Ok(decoded)
}

pub fn decode_prefix(
    codec_id: u32,
    bytes: &[u8],
    final_chunk: bool,
) -> NativeResult<(Vec<u8>, usize)> {
    if !supports(codec_id) {
        return Err(err(0, "codec is not mapped to native gb18030 tables"));
    }
    let table = tables()?;
    let mut out = String::with_capacity(bytes.len());
    let mut index = 0usize;
    while index < bytes.len() {
        let b1 = bytes[index];
        if b1 < 0x80 {
            out.push(char::from(b1));
            index += 1;
            continue;
        }
        if index + 1 >= bytes.len() {
            if final_chunk {
                return Err(err(index as u32, "incomplete multibyte sequence"));
            }
            break;
        }

        let b2 = bytes[index + 1];
        if (0x30..=0x39).contains(&b2) {
            if index + 3 >= bytes.len() {
                if final_chunk {
                    return Err(err(index as u32, "incomplete multibyte sequence"));
                }
                break;
            }
            let b3 = bytes[index + 2];
            let b4 = bytes[index + 3];
            if !(0x81..=0xFE).contains(&b1)
                || !(0x81..=0xFE).contains(&b3)
                || !(0x30..=0x39).contains(&b4)
            {
                return Err(err(index as u32, "invalid multibyte sequence"));
            }

            let c1 = (b1 - 0x81) as u32;
            let c2 = (b2 - 0x30) as u32;
            let c3 = (b3 - 0x81) as u32;
            let c4 = (b4 - 0x30) as u32;
            if c1 < 4 {
                let pointer = ((c1 * 10 + c2) * 126 + c3) * 10 + c4;
                if pointer < GB18030_BMP_POINTER_LIMIT
                    && let Some(cp) = bmp_code_point_from_pointer(&table.bmp_ranges, pointer)
                {
                    let ch = char::from_u32(cp)
                        .ok_or_else(|| err(index as u32, "invalid Unicode scalar"))?;
                    out.push(ch);
                    index += 4;
                    continue;
                }
            } else if c1 >= 15 {
                let cp = 0x10000 + (((c1 - 15) * 10 + c2) * 126 + c3) * 10 + c4;
                if cp <= 0x10FFFF {
                    let ch = char::from_u32(cp)
                        .ok_or_else(|| err(index as u32, "invalid Unicode scalar"))?;
                    out.push(ch);
                    index += 4;
                    continue;
                }
            }
            return Err(err(index as u32, "invalid multibyte sequence"));
        }

        let key = ((b1 as u32) << 8) | b2 as u32;
        let cp = table.double_decode.values[key as usize];
        if cp != INVALID_CP {
            if cp == MULTI_CP {
                let text = table.double_decode.lookup_multi_rune(key).ok_or_else(|| {
                    err(index as u32, "missing gb18030 multi-rune decode mapping")
                })?;
                out.push_str(text);
            } else {
                let ch = char::from_u32(cp)
                    .ok_or_else(|| err(index as u32, "invalid Unicode scalar"))?;
                out.push(ch);
            }
            index += 2;
            continue;
        }

        return Err(err(index as u32, "invalid multibyte sequence"));
    }
    Ok((out.into_bytes(), index))
}

pub fn encode(codec_id: u32, utf8_bytes: &[u8]) -> NativeResult<Vec<u8>> {
    if !supports(codec_id) {
        return Err(err(0, "codec is not mapped to native gb18030 tables"));
    }
    let text = std::str::from_utf8(utf8_bytes)
        .map_err(|error| err(error.valid_up_to() as u32, "input text was not valid UTF-8"))?;
    let table = tables()?;
    let mut out = Vec::with_capacity(text.len());
    for (index, ch) in text.chars().enumerate() {
        let cp = ch as u32;
        if cp < 0x80 {
            out.push(cp as u8);
            continue;
        }
        if cp >= 0x10000 {
            append_pointer_sequence(cp - 0x10000, 0x90, &mut out);
            continue;
        }
        if let Some(packed) = lookup_paged_encode(&table.double_encode, cp) {
            unpack_sequence(packed, &mut out);
            continue;
        }
        if let Some(pointer) = bmp_pointer_from_code_point(&table.bmp_ranges, cp) {
            append_pointer_sequence(pointer, 0x81, &mut out);
            continue;
        }
        return Err(err(
            index as u32,
            "character is not encodable in this codec",
        ));
    }
    Ok(out)
}

pub fn validate(codec_id: u32, bytes: &[u8]) -> bool {
    if !supports(codec_id) {
        return false;
    }
    let Ok(table) = tables() else {
        return false;
    };
    let mut index = 0usize;
    while index < bytes.len() {
        let b1 = bytes[index];
        if b1 < 0x80 {
            index += 1;
            continue;
        }
        if index + 1 >= bytes.len() {
            return false;
        }

        let b2 = bytes[index + 1];
        if (0x30..=0x39).contains(&b2) {
            if index + 3 >= bytes.len() {
                return false;
            }
            let b3 = bytes[index + 2];
            let b4 = bytes[index + 3];
            if !(0x81..=0xFE).contains(&b1)
                || !(0x81..=0xFE).contains(&b3)
                || !(0x30..=0x39).contains(&b4)
            {
                return false;
            }

            let c1 = (b1 - 0x81) as u32;
            let c2 = (b2 - 0x30) as u32;
            let c3 = (b3 - 0x81) as u32;
            let c4 = (b4 - 0x30) as u32;
            if c1 < 4 {
                let pointer = ((c1 * 10 + c2) * 126 + c3) * 10 + c4;
                if pointer < GB18030_BMP_POINTER_LIMIT
                    && bmp_code_point_from_pointer(&table.bmp_ranges, pointer).is_some()
                {
                    index += 4;
                    continue;
                }
            } else if c1 >= 15 {
                let cp = 0x10000 + (((c1 - 15) * 10 + c2) * 126 + c3) * 10 + c4;
                if cp <= 0x10FFFF {
                    index += 4;
                    continue;
                }
            }
            return false;
        }

        let key = ((b1 as u32) << 8) | b2 as u32;
        let cp = table.double_decode.values[key as usize];
        if cp == INVALID_CP {
            return false;
        }
        if cp == MULTI_CP && table.double_decode.lookup_multi_rune(key).is_none() {
            return false;
        }
        index += 2;
    }
    true
}

fn tables() -> NativeResult<&'static Gb18030Tables> {
    match GB18030_TABLES.get_or_init(|| {
        let blob = blobs::MBCS_GB18030_TABLES;
        Ok(Gb18030Tables {
            double_decode: parse_dense_decode(checked_slice(
                blob,
                codec_index::GB18030_DOUBLE_DECODE_OFFSET as usize,
                codec_index::GB18030_DOUBLE_DECODE_LENGTH as usize,
                "gb18030 decode table",
            )?)?,
            double_encode: parse_paged_encode(checked_slice(
                blob,
                codec_index::GB18030_DOUBLE_ENCODE_OFFSET as usize,
                codec_index::GB18030_DOUBLE_ENCODE_LENGTH as usize,
                "gb18030 encode table",
            )?)?,
            bmp_ranges: parse_ranges(checked_slice(
                blob,
                codec_index::GB18030_RANGES_OFFSET as usize,
                codec_index::GB18030_RANGES_LENGTH as usize,
                "gb18030 range table",
            )?)?,
        })
    }) {
        Ok(table) => Ok(table),
        Err(error) => Err(error.clone()),
    }
}

impl DenseDecodeTable {
    fn lookup_multi_rune(&self, key: u32) -> Option<&str> {
        match self.side_keys.binary_search(&key) {
            Ok(index) => Some(self.side_strings[index].as_str()),
            Err(_) => None,
        }
    }
}

fn parse_dense_decode(blob: &[u8]) -> NativeResult<DenseDecodeTable> {
    let mut reader = BlobReader::new(blob, "gb18030 dense decode table");
    let count = reader.read_u32()? as usize;
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
    if !side_keys.windows(2).all(|pair| pair[0] < pair[1]) {
        return Err(err(
            0,
            "corrupt gb18030 decode table: side keys are not sorted",
        ));
    }
    reader.finish()?;
    Ok(DenseDecodeTable {
        values,
        side_keys,
        side_strings,
    })
}

fn parse_paged_encode(blob: &[u8]) -> NativeResult<PagedEncodeTable> {
    let mut reader = BlobReader::new(blob, "gb18030 paged encode table");
    let mut page_directory = [0u16; 256];
    for entry in &mut page_directory {
        *entry = reader.read_u16()?;
    }
    let page_count = reader.read_u32()? as usize;
    let page_value_count = page_count
        .checked_mul(256)
        .ok_or_else(|| err(0, "corrupt gb18030 encode table: page count overflow"))?;
    let pages = reader.read_u32_vec(page_value_count)?;
    if page_directory
        .iter()
        .any(|page| *page != 0 && *page as usize > page_count)
    {
        return Err(err(
            0,
            "corrupt gb18030 encode table: page directory index is out of range",
        ));
    }
    let supplementary_count = reader.read_u32()? as usize;
    let supplementary_keys = reader.read_u32_vec(supplementary_count)?;
    let supplementary_values = reader.read_u32_vec(supplementary_count)?;
    if !supplementary_keys.windows(2).all(|pair| pair[0] < pair[1]) {
        return Err(err(
            0,
            "corrupt gb18030 encode table: supplementary keys are not sorted",
        ));
    }
    reader.finish()?;
    Ok(PagedEncodeTable {
        page_directory,
        pages,
        supplementary_keys,
        supplementary_values,
    })
}

fn parse_ranges(blob: &[u8]) -> NativeResult<Vec<Gb18030Range>> {
    let mut reader = BlobReader::new(blob, "gb18030 range table");
    let count = reader.read_u32()? as usize;
    let mut ranges = Vec::with_capacity(count);
    for _ in 0..count {
        let range = Gb18030Range {
            first: reader.read_u32()?,
            last: reader.read_u32()?,
            base: reader.read_u32()?,
        };
        if range.first > range.last {
            return Err(err(0, "corrupt gb18030 range table: reversed range"));
        }
        ranges.push(range);
    }
    if !ranges
        .windows(2)
        .all(|pair| pair[0].last < pair[1].first && pair[0].base < pair[1].base)
    {
        return Err(err(0, "corrupt gb18030 range table: ranges are not sorted"));
    }
    reader.finish()?;
    Ok(ranges)
}

fn bmp_code_point_from_pointer(ranges: &[Gb18030Range], pointer: u32) -> Option<u32> {
    for range in ranges {
        let max_pointer = range.base + (range.last - range.first);
        if pointer < range.base {
            return None;
        }
        if pointer <= max_pointer {
            return Some(range.first + (pointer - range.base));
        }
    }
    None
}

fn bmp_pointer_from_code_point(ranges: &[Gb18030Range], code_point: u32) -> Option<u32> {
    for range in ranges {
        if code_point >= range.first && code_point <= range.last {
            return Some(range.base + (code_point - range.first));
        }
    }
    None
}

fn append_pointer_sequence(pointer: u32, first_byte_base: u8, out: &mut Vec<u8>) {
    let mut tc = pointer;
    let b4 = (tc % 10) as u8 + 0x30;
    tc /= 10;
    let b3 = (tc % 126) as u8 + 0x81;
    tc /= 126;
    let b2 = (tc % 10) as u8 + 0x30;
    tc /= 10;
    let b1 = tc as u8 + first_byte_base;
    out.extend_from_slice(&[b1, b2, b3, b4]);
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
