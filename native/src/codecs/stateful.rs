// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use std::sync::OnceLock;

use super::blob_reader::{BlobReader, checked_slice};
use crate::backend::{NativeResult, err};
use crate::generated::{blobs, codec_index};

const INVALID_CP: u32 = 0xFFFF_FFFF;
const MULTI_CP: u32 = 0xFFFF_FFFE;
const HZ_CODEC_NAME: &str = "hz-gb-2312";
const ISO2022_KR_CODEC_NAME: &str = "iso-2022-kr";
const ASCII_RESET_ESCAPE: [u8; 3] = [0x1B, 0x28, 0x42];
const ISO2022_SINGLE_SHIFT_G2_ESCAPE: [u8; 2] = [0x1B, 0x4E];
const ESC_GB2312: [u8; 4] = [0x1B, 0x24, 0x28, 0x41];
const ESC_ISO8859_1_G2: [u8; 3] = [0x1B, 0x2E, 0x41];
const ESC_ISO8859_7_G2: [u8; 3] = [0x1B, 0x2E, 0x46];
const ESC_JISX0201_K: [u8; 3] = [0x1B, 0x28, 0x49];
const ESC_JISX0201_R: [u8; 3] = [0x1B, 0x28, 0x4A];
const ESC_JISX0208: [u8; 3] = [0x1B, 0x24, 0x42];
const ESC_JISX0208_O: [u8; 4] = [0x1B, 0x24, 0x28, 0x40];
const ESC_JISX0212: [u8; 4] = [0x1B, 0x24, 0x28, 0x44];
const ESC_JISX0213_2: [u8; 4] = [0x1B, 0x24, 0x28, 0x50];
const ESC_JISX0213_2004_1: [u8; 4] = [0x1B, 0x24, 0x28, 0x51];
const ESC_KSX1001: [u8; 4] = [0x1B, 0x24, 0x28, 0x43];

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

struct Iso2022SetTables {
    decode: DenseDecodeTable,
    encode: PagedEncodeTable,
    width: u8,
    is_g2: bool,
}

struct Iso2022NamedSetIndexes {
    gb2312: usize,
    iso8859_1_g2: usize,
    iso8859_7_g2: usize,
    jisx0201_k: usize,
    jisx0201_r: usize,
    jisx0208: usize,
    jisx0208_o: usize,
    jisx0212: usize,
    jisx0213_2: usize,
    jisx0213_2004_1: usize,
    ksx1001: usize,
}

struct StatefulTables {
    hz_decode: DenseDecodeTable,
    hz_encode: PagedEncodeTable,
    iso2022_kr_decode: DenseDecodeTable,
    iso2022_kr_encode: PagedEncodeTable,
    iso2022_sets: Vec<Iso2022SetTables>,
    iso2022_named: Iso2022NamedSetIndexes,
}

#[derive(Clone, Copy)]
struct Iso2022CodecConfig {
    use_g2: bool,
    set_order_offset: usize,
    set_order_len: usize,
}

#[derive(Clone, Copy)]
enum DesignationTarget {
    Unchanged,
    Ascii,
    Set(usize),
}

static STATEFUL_TABLES: OnceLock<NativeResult<StatefulTables>> = OnceLock::new();

pub fn supports(codec_id: u32) -> bool {
    codec_index::stateful_native_family_index(codec_id).is_some()
}

pub fn decode(codec_id: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    if iso2022_jp_config(codec_id).is_some() {
        return decode_iso2022_jp_family(codec_id, bytes);
    }
    match codec_index::canonical_name(codec_id) {
        HZ_CODEC_NAME => decode_hz(bytes),
        ISO2022_KR_CODEC_NAME => decode_iso2022_kr(bytes),
        _ => Err(err(0, "codec is not mapped to native stateful tables")),
    }
}

pub fn encode(codec_id: u32, utf8_bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let text = std::str::from_utf8(utf8_bytes)
        .map_err(|error| err(error.valid_up_to() as u32, "input text was not valid UTF-8"))?;
    if iso2022_jp_config(codec_id).is_some() {
        return encode_iso2022_jp_family(codec_id, text);
    }
    match codec_index::canonical_name(codec_id) {
        HZ_CODEC_NAME => encode_hz(text),
        ISO2022_KR_CODEC_NAME => encode_iso2022_kr(text),
        _ => Err(err(0, "codec is not mapped to native stateful tables")),
    }
}

pub fn validate(codec_id: u32, bytes: &[u8]) -> bool {
    if iso2022_jp_config(codec_id).is_some() {
        return decode_iso2022_jp_family(codec_id, bytes).is_ok();
    }
    match codec_index::canonical_name(codec_id) {
        HZ_CODEC_NAME => validate_hz(bytes),
        ISO2022_KR_CODEC_NAME => validate_iso2022_kr(bytes),
        _ => false,
    }
}

fn tables() -> NativeResult<&'static StatefulTables> {
    match STATEFUL_TABLES.get_or_init(|| {
        let blob = blobs::MBCS_STATEFUL_TABLES;
        let iso2022_sets = (0..codec_index::ISO2022_SET_IDS.len())
            .map(|set_index| {
                Ok(Iso2022SetTables {
                    decode: parse_dense_decode(checked_slice(
                        blob,
                        codec_index::ISO2022_SET_DECODE_OFFSETS[set_index] as usize,
                        codec_index::ISO2022_SET_DECODE_LENGTHS[set_index] as usize,
                        "ISO-2022 set decode table",
                    )?)?,
                    encode: parse_paged_encode(checked_slice(
                        blob,
                        codec_index::ISO2022_SET_ENCODE_OFFSETS[set_index] as usize,
                        codec_index::ISO2022_SET_ENCODE_LENGTHS[set_index] as usize,
                        "ISO-2022 set encode table",
                    )?)?,
                    width: codec_index::ISO2022_SET_WIDTHS[set_index],
                    is_g2: codec_index::ISO2022_SET_IS_G2[set_index] != 0,
                })
            })
            .collect::<NativeResult<Vec<_>>>()?;
        if codec_index::ISO2022_JP_CODEC_SET_ORDER_VALUES
            .iter()
            .any(|set_index| *set_index as usize >= iso2022_sets.len())
        {
            return Err(err(
                0,
                "generated ISO-2022 codec order references an unknown set",
            ));
        }
        Ok(StatefulTables {
            hz_decode: parse_dense_decode(checked_slice(
                blob,
                codec_index::HZ_DECODE_OFFSET as usize,
                codec_index::HZ_DECODE_LENGTH as usize,
                "HZ decode table",
            )?)?,
            hz_encode: parse_paged_encode(checked_slice(
                blob,
                codec_index::HZ_ENCODE_OFFSET as usize,
                codec_index::HZ_ENCODE_LENGTH as usize,
                "HZ encode table",
            )?)?,
            iso2022_kr_decode: parse_dense_decode(checked_slice(
                blob,
                codec_index::ISO2022_KR_DECODE_OFFSET as usize,
                codec_index::ISO2022_KR_DECODE_LENGTH as usize,
                "ISO-2022-KR decode table",
            )?)?,
            iso2022_kr_encode: parse_paged_encode(checked_slice(
                blob,
                codec_index::ISO2022_KR_ENCODE_OFFSET as usize,
                codec_index::ISO2022_KR_ENCODE_LENGTH as usize,
                "ISO-2022-KR encode table",
            )?)?,
            iso2022_sets,
            iso2022_named: Iso2022NamedSetIndexes {
                gb2312: resolve_iso2022_set_index("gb2312")?,
                iso8859_1_g2: resolve_iso2022_set_index("iso8859_1_g2")?,
                iso8859_7_g2: resolve_iso2022_set_index("iso8859_7_g2")?,
                jisx0201_k: resolve_iso2022_set_index("jisx0201_k")?,
                jisx0201_r: resolve_iso2022_set_index("jisx0201_r")?,
                jisx0208: resolve_iso2022_set_index("jisx0208")?,
                jisx0208_o: resolve_iso2022_set_index("jisx0208_o")?,
                jisx0212: resolve_iso2022_set_index("jisx0212")?,
                jisx0213_2: resolve_iso2022_set_index("jisx0213_2")?,
                jisx0213_2004_1: resolve_iso2022_set_index("jisx0213_2004_1")?,
                ksx1001: resolve_iso2022_set_index("ksx1001")?,
            },
        })
    }) {
        Ok(table) => Ok(table),
        Err(error) => Err(error.clone()),
    }
}

fn decode_hz(bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let table = &tables()?.hz_decode;
    let mut out = String::with_capacity(bytes.len());
    let mut in_gb = false;
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte == 0x7E {
            if index + 1 >= bytes.len() {
                return Err(err(index as u32, "incomplete multibyte sequence"));
            }
            match bytes[index + 1] {
                0x7B => {
                    in_gb = true;
                    index += 2;
                }
                0x7D => {
                    in_gb = false;
                    index += 2;
                }
                0x7E => {
                    out.push('~');
                    index += 2;
                }
                0x0A => {
                    index += 2;
                }
                0x0D => {
                    index += if index + 2 < bytes.len() && bytes[index + 2] == 0x0A {
                        3
                    } else {
                        2
                    };
                }
                _ => return Err(err(index as u32, "invalid multibyte sequence")),
            }
            continue;
        }

        if !in_gb {
            if byte < 0x80 {
                out.push(char::from(byte));
                index += 1;
                continue;
            }
            return Err(err(index as u32, "invalid multibyte sequence"));
        }

        if index + 1 >= bytes.len() {
            return Err(err(index as u32, "incomplete multibyte sequence"));
        }
        let b1 = byte;
        let b2 = bytes[index + 1];
        if !(0x21..=0x7E).contains(&b1) || !(0x21..=0x7E).contains(&b2) {
            return Err(err(index as u32, "invalid multibyte sequence"));
        }
        append_dense_decode_by_index(&mut out, table, pair94_index(b1, b2), index)?;
        index += 2;
    }
    Ok(out.into_bytes())
}

fn encode_hz(text: &str) -> NativeResult<Vec<u8>> {
    let table = &tables()?.hz_encode;
    let mut out = Vec::with_capacity(text.len());
    let mut in_gb = false;
    for (index, ch) in text.chars().enumerate() {
        let scalar = ch as u32;
        if scalar < 0x80 {
            if in_gb {
                out.extend_from_slice(&[0x7E, 0x7D]);
                in_gb = false;
            }
            if scalar == 0x7E {
                out.extend_from_slice(&[0x7E, 0x7E]);
            } else {
                out.push(scalar as u8);
            }
            continue;
        }
        let packed = lookup_paged_encode(table, scalar)
            .ok_or_else(|| err(index as u32, "character is not encodable in this codec"))?;
        if !in_gb {
            out.extend_from_slice(&[0x7E, 0x7B]);
            in_gb = true;
        }
        unpack_sequence(packed, &mut out);
    }
    if in_gb {
        out.extend_from_slice(&[0x7E, 0x7D]);
    }
    Ok(out)
}

fn validate_hz(bytes: &[u8]) -> bool {
    let Ok(stateful) = tables() else {
        return false;
    };
    let table = &stateful.hz_decode;
    let mut in_gb = false;
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte == 0x7E {
            if index + 1 >= bytes.len() {
                return false;
            }
            match bytes[index + 1] {
                0x7B => {
                    in_gb = true;
                    index += 2;
                }
                0x7D => {
                    in_gb = false;
                    index += 2;
                }
                0x7E | 0x0A => {
                    index += 2;
                }
                0x0D => {
                    index += if index + 2 < bytes.len() && bytes[index + 2] == 0x0A {
                        3
                    } else {
                        2
                    };
                }
                _ => return false,
            }
            continue;
        }

        if !in_gb {
            if byte < 0x80 {
                index += 1;
                continue;
            }
            return false;
        }

        if index + 1 >= bytes.len() {
            return false;
        }
        let b1 = byte;
        let b2 = bytes[index + 1];
        if !(0x21..=0x7E).contains(&b1) || !(0x21..=0x7E).contains(&b2) {
            return false;
        }
        if !is_valid_dense_index(table, pair94_index(b1, b2)) {
            return false;
        }
        index += 2;
    }
    true
}

fn decode_iso2022_kr(bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let table = &tables()?.iso2022_kr_decode;
    let mut out = String::with_capacity(bytes.len());
    let mut designated = false;
    let mut shifted = false;
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte == 0x1B {
            if index + 3 >= bytes.len() {
                return Err(err(index as u32, "incomplete multibyte sequence"));
            }
            if bytes[index + 1] == 0x24 && bytes[index + 2] == 0x29 && bytes[index + 3] == 0x43 {
                designated = true;
                index += 4;
                continue;
            }
            return Err(err(index as u32, "invalid multibyte sequence"));
        }
        if byte == 0x0E {
            shifted = true;
            index += 1;
            continue;
        }
        if byte == 0x0F {
            shifted = false;
            index += 1;
            continue;
        }

        if !shifted {
            if byte < 0x80 {
                out.push(char::from(byte));
                index += 1;
                continue;
            }
            return Err(err(index as u32, "invalid multibyte sequence"));
        }

        if !designated {
            return Err(err(index as u32, "invalid multibyte sequence"));
        }
        if index + 1 >= bytes.len() {
            return Err(err(index as u32, "incomplete multibyte sequence"));
        }
        let b1 = byte;
        let b2 = bytes[index + 1];
        if !(0x21..=0x7E).contains(&b1) || !(0x21..=0x7E).contains(&b2) {
            return Err(err(index as u32, "invalid multibyte sequence"));
        }
        append_dense_decode_by_index(&mut out, table, pair94_index(b1, b2), index)?;
        index += 2;
    }
    Ok(out.into_bytes())
}

fn encode_iso2022_kr(text: &str) -> NativeResult<Vec<u8>> {
    let table = &tables()?.iso2022_kr_encode;
    let mut out = Vec::with_capacity(text.len());
    let mut designated = false;
    let mut shifted = false;
    for (index, ch) in text.chars().enumerate() {
        let scalar = ch as u32;
        if scalar < 0x80 {
            if shifted {
                out.push(0x0F);
                shifted = false;
            }
            out.push(scalar as u8);
            continue;
        }
        let packed = lookup_paged_encode(table, scalar)
            .ok_or_else(|| err(index as u32, "character is not encodable in this codec"))?;
        if !designated {
            out.extend_from_slice(&[0x1B, 0x24, 0x29, 0x43]);
            designated = true;
        }
        if !shifted {
            out.push(0x0E);
            shifted = true;
        }
        unpack_sequence(packed, &mut out);
    }
    if shifted {
        out.push(0x0F);
    }
    Ok(out)
}

fn validate_iso2022_kr(bytes: &[u8]) -> bool {
    let Ok(stateful) = tables() else {
        return false;
    };
    let table = &stateful.iso2022_kr_decode;
    let mut designated = false;
    let mut shifted = false;
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte == 0x1B {
            if index + 3 >= bytes.len() {
                return false;
            }
            if bytes[index + 1] == 0x24 && bytes[index + 2] == 0x29 && bytes[index + 3] == 0x43 {
                designated = true;
                index += 4;
                continue;
            }
            return false;
        }
        if byte == 0x0E {
            shifted = true;
            index += 1;
            continue;
        }
        if byte == 0x0F {
            shifted = false;
            index += 1;
            continue;
        }

        if !shifted {
            if byte < 0x80 {
                index += 1;
                continue;
            }
            return false;
        }

        if !designated || index + 1 >= bytes.len() {
            return false;
        }
        let b1 = byte;
        let b2 = bytes[index + 1];
        if !(0x21..=0x7E).contains(&b1) || !(0x21..=0x7E).contains(&b2) {
            return false;
        }
        if !is_valid_dense_index(table, pair94_index(b1, b2)) {
            return false;
        }
        index += 2;
    }
    true
}

fn decode_iso2022_jp_family(codec_id: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let config = iso2022_jp_config(codec_id)
        .ok_or_else(|| err(0, "codec is not mapped to native iso-2022-jp tables"))?;
    let stateful = tables()?;
    let mut out = String::with_capacity(bytes.len());
    let mut esc_throughout = false;
    let mut g0: Option<usize> = None;
    let mut g2: Option<usize> = None;
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        if esc_throughout {
            out.push(char::from(byte));
            index += 1;
            if is_esc_end_byte(byte) {
                esc_throughout = false;
            }
            continue;
        }
        if byte == 0x1B {
            if index + 1 >= bytes.len() {
                return Err(err(index as u32, "incomplete multibyte sequence"));
            }
            let next = bytes[index + 1];
            if config.use_g2 && next == 0x4E {
                if index + 2 >= bytes.len() {
                    return Err(err(index as u32, "incomplete multibyte sequence"));
                }
                let key = bytes[index + 2];
                if key >= 0x80 {
                    return Err(err(index as u32, "invalid multibyte sequence"));
                }
                let set_index =
                    g2.ok_or_else(|| err(index as u32, "invalid multibyte sequence"))?;
                append_iso2022_decode_unit(&mut out, set_index, key as u16, index)?;
                index += 3;
                continue;
            }
            if is_iso2022_esc_header(next) {
                let (consumed, next_g0, next_g2) =
                    parse_iso2022_designation(bytes, index, &config, &stateful.iso2022_named)
                        .ok_or_else(|| err(index as u32, "invalid multibyte sequence"))?;
                if let DesignationTarget::Set(set_index) = next_g0
                    && !codec_supports_iso2022_set(&config, set_index)
                {
                    return Err(err(index as u32, "invalid multibyte sequence"));
                }
                if let DesignationTarget::Set(set_index) = next_g2
                    && !codec_supports_iso2022_set(&config, set_index)
                {
                    return Err(err(index as u32, "invalid multibyte sequence"));
                }
                apply_designation_target(next_g0, &mut g0);
                apply_designation_target(next_g2, &mut g2);
                index += consumed;
                continue;
            }
            out.push('\u{001B}');
            esc_throughout = true;
            index += 1;
            continue;
        }

        if byte == 0x0A || byte == 0x0E || byte == 0x0F || byte < 0x20 {
            out.push(char::from(byte));
            index += 1;
            continue;
        }
        if byte >= 0x80 {
            return Err(err(index as u32, "invalid multibyte sequence"));
        }
        let Some(set_index) = g0 else {
            out.push(char::from(byte));
            index += 1;
            continue;
        };
        let width = stateful
            .iso2022_sets
            .get(set_index)
            .ok_or_else(|| err(index as u32, "ISO-2022 set index is out of range"))?
            .width;
        if width == 1 {
            append_iso2022_decode_unit(&mut out, set_index, byte as u16, index)?;
            index += 1;
            continue;
        }
        if index + 1 >= bytes.len() {
            return Err(err(index as u32, "incomplete multibyte sequence"));
        }
        let b_next = bytes[index + 1];
        if !(0x20..0x80).contains(&b_next) {
            return Err(err(index as u32, "invalid multibyte sequence"));
        }
        append_iso2022_decode_unit(
            &mut out,
            set_index,
            ((byte as u16) << 8) | b_next as u16,
            index,
        )?;
        index += 2;
    }
    Ok(out.into_bytes())
}

fn encode_iso2022_jp_family(codec_id: u32, text: &str) -> NativeResult<Vec<u8>> {
    let config = iso2022_jp_config(codec_id)
        .ok_or_else(|| err(0, "codec is not mapped to native iso-2022-jp tables"))?;
    let stateful = tables()?;
    let mut out = Vec::with_capacity(text.len());
    let mut g0: Option<usize> = None;
    let mut g2: Option<usize> = None;
    for (index, ch) in text.chars().enumerate() {
        let scalar = ch as u32;
        if scalar < 0x80 {
            if g0.is_some() {
                out.extend_from_slice(&ASCII_RESET_ESCAPE);
                g0 = None;
            }
            out.push(scalar as u8);
            continue;
        }

        let (set_index, packed) = iso2022_set_order(&config)?
            .iter()
            .copied()
            .find_map(|raw_index| {
                let set_index = raw_index as usize;
                stateful
                    .iso2022_sets
                    .get(set_index)
                    .and_then(|set| lookup_paged_encode(&set.encode, scalar))
                    .map(|packed| (set_index, packed))
            })
            .ok_or_else(|| err(index as u32, "character is not encodable in this codec"))?;

        let set = stateful
            .iso2022_sets
            .get(set_index)
            .ok_or_else(|| err(index as u32, "ISO-2022 set index is out of range"))?;
        if set.is_g2 {
            if g2 != Some(set_index) {
                out.extend_from_slice(iso2022_designation_escape(
                    set_index,
                    &stateful.iso2022_named,
                )?);
                g2 = Some(set_index);
            }
            out.extend_from_slice(&ISO2022_SINGLE_SHIFT_G2_ESCAPE);
            let packed_len = packed_length(packed);
            if packed_len != 1 {
                return Err(err(index as u32, "invalid iso-2022 g2 encode mapping"));
            }
            out.push(
                packed_byte_at(packed, 0)
                    .ok_or_else(|| err(index as u32, "invalid packed byte index"))?,
            );
            continue;
        }

        if g0 != Some(set_index) {
            out.extend_from_slice(iso2022_designation_escape(
                set_index,
                &stateful.iso2022_named,
            )?);
            g0 = Some(set_index);
        }
        unpack_sequence(packed, &mut out);
    }

    if g0.is_some() {
        out.extend_from_slice(&ASCII_RESET_ESCAPE);
    }
    Ok(out)
}

fn iso2022_jp_config(codec_id: u32) -> Option<Iso2022CodecConfig> {
    let family_index = codec_index::iso2022_jp_family_index(codec_id)?;
    let canonical_name = *codec_index::ISO2022_JP_CANONICAL_NAMES.get(family_index)?;
    Some(Iso2022CodecConfig {
        use_g2: canonical_name == "iso2022-jp-2",
        set_order_offset: *codec_index::ISO2022_JP_CODEC_SET_ORDER_OFFSETS.get(family_index)?
            as usize,
        set_order_len: *codec_index::ISO2022_JP_CODEC_SET_ORDER_LENGTHS.get(family_index)? as usize,
    })
}

fn iso2022_set_order(config: &Iso2022CodecConfig) -> NativeResult<&'static [u8]> {
    let start = config.set_order_offset;
    let end = start
        .checked_add(config.set_order_len)
        .ok_or_else(|| err(0, "generated ISO-2022 set order range overflow"))?;
    codec_index::ISO2022_JP_CODEC_SET_ORDER_VALUES
        .get(start..end)
        .ok_or_else(|| err(0, "generated ISO-2022 set order range is truncated"))
}

fn codec_supports_iso2022_set(config: &Iso2022CodecConfig, set_index: usize) -> bool {
    match iso2022_set_order(config) {
        Ok(order) => order
            .iter()
            .any(|&candidate| candidate as usize == set_index),
        Err(_) => false,
    }
}

fn parse_iso2022_designation(
    bytes: &[u8],
    index: usize,
    config: &Iso2022CodecConfig,
    named: &Iso2022NamedSetIndexes,
) -> Option<(usize, DesignationTarget, DesignationTarget)> {
    let b2 = *bytes.get(index + 1)?;
    if b2 == 0x26
        && bytes.get(index + 2) == Some(&0x40)
        && bytes.get(index + 3) == Some(&0x1B)
        && bytes.get(index + 4) == Some(&0x24)
        && bytes.get(index + 5) == Some(&0x42)
    {
        return Some((
            6,
            DesignationTarget::Set(named.jisx0208),
            DesignationTarget::Unchanged,
        ));
    }

    if b2 == 0x28 {
        let mark = *bytes.get(index + 2)?;
        let next_g0 = match mark {
            0x42 => DesignationTarget::Ascii,
            0x4A => DesignationTarget::Set(named.jisx0201_r),
            0x49 => DesignationTarget::Set(named.jisx0201_k),
            _ => return None,
        };
        return Some((3, next_g0, DesignationTarget::Unchanged));
    }

    if b2 == 0x24 {
        let mark = *bytes.get(index + 2)?;
        if mark == 0x42 {
            return Some((
                3,
                DesignationTarget::Set(named.jisx0208),
                DesignationTarget::Unchanged,
            ));
        }
        if mark == 0x40 {
            return Some((
                3,
                DesignationTarget::Set(named.jisx0208_o),
                DesignationTarget::Unchanged,
            ));
        }
        if mark == 0x28 {
            let mark2 = *bytes.get(index + 3)?;
            let next_g0 = match mark2 {
                0x41 => DesignationTarget::Set(named.gb2312),
                0x43 => DesignationTarget::Set(named.ksx1001),
                0x44 => DesignationTarget::Set(named.jisx0212),
                0x50 => DesignationTarget::Set(named.jisx0213_2),
                0x51 => DesignationTarget::Set(named.jisx0213_2004_1),
                0x40 => DesignationTarget::Set(named.jisx0208_o),
                _ => return None,
            };
            return Some((4, next_g0, DesignationTarget::Unchanged));
        }
        return None;
    }

    if config.use_g2 && b2 == 0x2E {
        let mark = *bytes.get(index + 2)?;
        let next_g2 = match mark {
            0x41 => DesignationTarget::Set(named.iso8859_1_g2),
            0x46 => DesignationTarget::Set(named.iso8859_7_g2),
            0x42 => DesignationTarget::Ascii,
            _ => return None,
        };
        return Some((3, DesignationTarget::Unchanged, next_g2));
    }

    None
}

fn apply_designation_target(target: DesignationTarget, slot: &mut Option<usize>) {
    match target {
        DesignationTarget::Unchanged => {}
        DesignationTarget::Ascii => *slot = None,
        DesignationTarget::Set(set_index) => *slot = Some(set_index),
    }
}

fn append_iso2022_decode_unit(
    out: &mut String,
    set_index: usize,
    key: u16,
    position: usize,
) -> NativeResult<()> {
    let stateful = tables()?;
    let set = stateful
        .iso2022_sets
        .get(set_index)
        .ok_or_else(|| err(position as u32, "ISO-2022 set index is out of range"))?;
    if set.width == 1 {
        return append_dense_decode_by_index(out, &set.decode, key as usize, position);
    }
    let b1 = (key >> 8) as u8;
    let b2 = (key & 0xFF) as u8;
    if !(0x21..=0x7E).contains(&b1) || !(0x21..=0x7E).contains(&b2) {
        return Err(err(position as u32, "invalid multibyte sequence"));
    }
    append_dense_decode_by_index(out, &set.decode, pair94_index(b1, b2), position)
}

fn resolve_iso2022_set_index(name: &str) -> NativeResult<usize> {
    codec_index::ISO2022_SET_IDS
        .iter()
        .position(|candidate| *candidate == name)
        .ok_or_else(|| {
            err(
                0,
                format!("missing native ISO-2022 set metadata for {name}"),
            )
        })
}

fn iso2022_designation_escape(
    set_index: usize,
    named: &Iso2022NamedSetIndexes,
) -> NativeResult<&'static [u8]> {
    let escape: &'static [u8] = match set_index {
        value if value == named.gb2312 => &ESC_GB2312,
        value if value == named.iso8859_1_g2 => &ESC_ISO8859_1_G2,
        value if value == named.iso8859_7_g2 => &ESC_ISO8859_7_G2,
        value if value == named.jisx0201_k => &ESC_JISX0201_K,
        value if value == named.jisx0201_r => &ESC_JISX0201_R,
        value if value == named.jisx0208 => &ESC_JISX0208,
        value if value == named.jisx0208_o => &ESC_JISX0208_O,
        value if value == named.jisx0212 => &ESC_JISX0212,
        value if value == named.jisx0213_2 => &ESC_JISX0213_2,
        value if value == named.jisx0213_2004_1 => &ESC_JISX0213_2004_1,
        value if value == named.ksx1001 => &ESC_KSX1001,
        _ => {
            return Err(err(
                0,
                format!("missing ISO-2022 designation escape for set index {set_index}"),
            ));
        }
    };
    Ok(escape)
}

fn is_iso2022_esc_header(byte: u8) -> bool {
    matches!(byte, 0x28 | 0x29 | 0x24 | 0x2E | 0x26)
}

fn is_esc_end_byte(byte: u8) -> bool {
    (0x41..=0x5A).contains(&byte) || byte == 0x40
}

impl DenseDecodeTable {
    fn lookup_multi_rune(&self, key: u32) -> Option<&str> {
        match self.side_keys.binary_search(&key) {
            Ok(index) => Some(self.side_strings[index].as_str()),
            Err(_) => None,
        }
    }
}

fn append_dense_decode_by_index(
    out: &mut String,
    table: &DenseDecodeTable,
    map_index: usize,
    position: usize,
) -> NativeResult<()> {
    let value = table.values.get(map_index).copied().unwrap_or(INVALID_CP);
    if value == INVALID_CP {
        return Err(err(position as u32, "invalid multibyte sequence"));
    }
    if value == MULTI_CP {
        let text = table
            .lookup_multi_rune(map_index as u32)
            .ok_or_else(|| err(position as u32, "missing multi-rune decode mapping"))?;
        out.push_str(text);
        return Ok(());
    }
    let ch = char::from_u32(value).ok_or_else(|| err(position as u32, "invalid Unicode scalar"))?;
    out.push(ch);
    Ok(())
}

fn is_valid_dense_index(table: &DenseDecodeTable, map_index: usize) -> bool {
    let value = table.values.get(map_index).copied().unwrap_or(INVALID_CP);
    if value == INVALID_CP {
        return false;
    }
    value != MULTI_CP || table.lookup_multi_rune(map_index as u32).is_some()
}

fn parse_dense_decode(blob: &[u8]) -> NativeResult<DenseDecodeTable> {
    let mut reader = BlobReader::new(blob, "stateful dense decode table");
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
            "corrupt stateful decode table: side keys are not sorted",
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
    let mut reader = BlobReader::new(blob, "stateful paged encode table");
    let mut page_directory = [0u16; 256];
    for entry in &mut page_directory {
        *entry = reader.read_u16()?;
    }
    let page_count = reader.read_u32()? as usize;
    let page_value_count = page_count
        .checked_mul(256)
        .ok_or_else(|| err(0, "corrupt stateful encode table: page count overflow"))?;
    let pages = reader.read_u32_vec(page_value_count)?;
    if page_directory
        .iter()
        .any(|page| *page != 0 && *page as usize > page_count)
    {
        return Err(err(
            0,
            "corrupt stateful encode table: page directory index is out of range",
        ));
    }
    let supplementary_count = reader.read_u32()? as usize;
    let supplementary_keys = reader.read_u32_vec(supplementary_count)?;
    let supplementary_values = reader.read_u32_vec(supplementary_count)?;
    if !supplementary_keys.windows(2).all(|pair| pair[0] < pair[1]) {
        return Err(err(
            0,
            "corrupt stateful encode table: supplementary keys are not sorted",
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

fn packed_length(packed: u32) -> usize {
    (packed >> 24) as usize
}

fn packed_byte_at(packed: u32, index: usize) -> Option<u8> {
    match index {
        0 => Some(((packed >> 16) & 0xFF) as u8),
        1 => Some(((packed >> 8) & 0xFF) as u8),
        2 => Some((packed & 0xFF) as u8),
        _ => None,
    }
}

fn pair94_index(b1: u8, b2: u8) -> usize {
    ((b1 - 0x21) as usize * 94) + (b2 - 0x21) as usize
}
