// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use std::sync::OnceLock;

use super::blob_reader::{BlobReader, checked_slice};
use crate::backend::{NativeResult, err};
use crate::generated::{blobs, codec_index};

const INVALID_CP: u32 = 0xFFFF_FFFF;
const MULTI_CP: u32 = 0xFFFF_FFFE;

struct DenseDecodeTable {
    values: [u32; 256],
    side_strings: Vec<Option<String>>,
}

struct PagedEncodeTable {
    page_directory: [u16; 256],
    pages: Vec<u32>,
    supplementary_keys: Vec<u32>,
    supplementary_values: Vec<u32>,
}

struct SbcsCodecTables {
    decode: DenseDecodeTable,
    encode: PagedEncodeTable,
}

static SBCS_TABLES: OnceLock<Vec<NativeResult<SbcsCodecTables>>> = OnceLock::new();

pub fn supports(codec_id: u32) -> bool {
    codec_index::sbcs_family_index(codec_id).is_some()
}

pub fn decode(codec_id: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let table = table_for_codec(codec_id)?;
    let mut out = String::with_capacity(bytes.len());
    for (index, byte) in bytes.iter().copied().enumerate() {
        let value = table.decode.values[byte as usize];
        if value == INVALID_CP {
            return Err(err(index as u32, "invalid single-byte mapping"));
        }
        if value == MULTI_CP {
            match &table.decode.side_strings[byte as usize] {
                Some(text) => out.push_str(text),
                None => return Err(err(index as u32, "missing multi-character decode mapping")),
            }
            continue;
        }
        let ch = char::from_u32(value)
            .ok_or_else(|| err(index as u32, "invalid Unicode scalar in decode table"))?;
        out.push(ch);
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
    decode(codec_id, bytes).is_ok()
}

fn tables() -> &'static [NativeResult<SbcsCodecTables>] {
    SBCS_TABLES
        .get_or_init(|| {
            let mut out = Vec::with_capacity(codec_index::SBCS_CANONICAL_NAMES.len());
            for family_index in 0..codec_index::SBCS_CANONICAL_NAMES.len() {
                out.push(parse_sbcs_tables(family_index));
            }
            out
        })
        .as_slice()
}

fn table_for_codec(codec_id: u32) -> NativeResult<&'static SbcsCodecTables> {
    let family_index = codec_index::sbcs_family_index(codec_id)
        .ok_or_else(|| err(0, "codec is not mapped to SBCS native tables"))?;
    match tables().get(family_index) {
        Some(Ok(table)) => Ok(table),
        Some(Err(error)) => Err(error.clone()),
        None => Err(err(0, "SBCS family index is outside generated metadata")),
    }
}

fn parse_sbcs_tables(family_index: usize) -> NativeResult<SbcsCodecTables> {
    let decode = parse_dense_decode(checked_slice(
        blobs::SBCS_TABLES,
        codec_index::SBCS_DECODE_OFFSETS[family_index] as usize,
        codec_index::SBCS_DECODE_LENGTHS[family_index] as usize,
        "SBCS decode table",
    )?)?;
    let encode = parse_paged_encode(checked_slice(
        blobs::SBCS_TABLES,
        codec_index::SBCS_ENCODE_OFFSETS[family_index] as usize,
        codec_index::SBCS_ENCODE_LENGTHS[family_index] as usize,
        "SBCS encode table",
    )?)?;
    Ok(SbcsCodecTables { decode, encode })
}

fn parse_dense_decode(blob: &[u8]) -> NativeResult<DenseDecodeTable> {
    let mut reader = BlobReader::new(blob, "SBCS dense decode table");
    let count = reader.read_u32()? as usize;
    if count != 256 {
        return Err(err(0, "corrupt SBCS decode table: expected 256 entries"));
    }
    let mut values = [INVALID_CP; 256];
    for value in &mut values {
        *value = reader.read_u32()?;
    }
    let side_count = reader.read_u32()? as usize;
    let mut side_strings = vec![None; 256];
    for _ in 0..side_count {
        let key = reader.read_u32()? as usize;
        let utf8_len = reader.read_u16()? as usize;
        let text = reader.read_utf8_string(utf8_len)?;
        let slot = side_strings
            .get_mut(key)
            .ok_or_else(|| err(0, "corrupt SBCS decode table: side key is out of range"))?;
        *slot = Some(text);
    }
    reader.finish()?;
    Ok(DenseDecodeTable {
        values,
        side_strings,
    })
}

fn parse_paged_encode(blob: &[u8]) -> NativeResult<PagedEncodeTable> {
    let mut reader = BlobReader::new(blob, "SBCS paged encode table");
    let mut page_directory = [0u16; 256];
    for entry in &mut page_directory {
        *entry = reader.read_u16()?;
    }
    let page_count = reader.read_u32()? as usize;
    let page_value_count = page_count
        .checked_mul(256)
        .ok_or_else(|| err(0, "corrupt SBCS encode table: page count overflow"))?;
    let pages = reader.read_u32_vec(page_value_count)?;
    if page_directory
        .iter()
        .any(|page| *page != 0 && *page as usize > page_count)
    {
        return Err(err(
            0,
            "corrupt SBCS encode table: page directory index is out of range",
        ));
    }
    let supplementary_count = reader.read_u32()? as usize;
    let supplementary_keys = reader.read_u32_vec(supplementary_count)?;
    let supplementary_values = reader.read_u32_vec(supplementary_count)?;
    if !supplementary_keys.windows(2).all(|pair| pair[0] < pair[1]) {
        return Err(err(
            0,
            "corrupt SBCS encode table: supplementary keys are not sorted",
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
