// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use crate::backend::{NativeResult, err};
use crate::generated::codec_index;

pub fn supports(codec_id: u32) -> bool {
    codec_index::is_utf(codec_id)
}

pub fn decode(codec_id: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let canonical = codec_index::canonical_name(codec_id);
    let output = match canonical {
        "utf-8" => decode_utf8(bytes)?,
        "utf-8-sig" => decode_utf8_sig(bytes)?,
        "utf-16" => decode_utf16_auto(bytes)?,
        "utf-16-le" => decode_utf16_endian(bytes, Endian::Little)?,
        "utf-16-be" => decode_utf16_endian(bytes, Endian::Big)?,
        "utf-32" => decode_utf32_auto(bytes)?,
        "utf-32-le" => decode_utf32_endian(bytes, Endian::Little)?,
        "utf-32-be" => decode_utf32_endian(bytes, Endian::Big)?,
        _ => return Err(err(0, format!("unsupported UTF codec: {canonical}"))),
    };
    Ok(output.into_bytes())
}

pub fn encode(codec_id: u32, utf8_bytes: &[u8]) -> NativeResult<Vec<u8>> {
    let text = std::str::from_utf8(utf8_bytes)
        .map_err(|error| err(error.valid_up_to() as u32, "input text was not valid UTF-8"))?;
    let canonical = codec_index::canonical_name(codec_id);
    match canonical {
        "utf-8" => Ok(text.as_bytes().to_vec()),
        "utf-8-sig" => {
            let mut out = vec![0xEF, 0xBB, 0xBF];
            out.extend_from_slice(text.as_bytes());
            Ok(out)
        }
        "utf-16" => Ok(encode_utf16(text, None)),
        "utf-16-le" => Ok(encode_utf16_with_endian(text, Endian::Little, false)),
        "utf-16-be" => Ok(encode_utf16_with_endian(text, Endian::Big, false)),
        "utf-32" => Ok(encode_utf32(text, None)),
        "utf-32-le" => Ok(encode_utf32_with_endian(text, Endian::Little, false)),
        "utf-32-be" => Ok(encode_utf32_with_endian(text, Endian::Big, false)),
        _ => Err(err(0, format!("unsupported UTF codec: {canonical}"))),
    }
}

pub fn validate(codec_id: u32, bytes: &[u8]) -> bool {
    if codec_index::canonical_name(codec_id) == "utf-7" {
        return decode_utf7_units(bytes).is_ok();
    }
    decode(codec_id, bytes).is_ok()
}

pub fn decode_utf16_units(codec_id: u32, bytes: &[u8]) -> NativeResult<Vec<u16>> {
    if codec_index::canonical_name(codec_id) == "utf-7" {
        return decode_utf7_units(bytes);
    }
    let decoded = decode(codec_id, bytes)?;
    let text = std::str::from_utf8(&decoded).map_err(|error| {
        err(
            error.valid_up_to() as u32,
            "native UTF output was not valid UTF-8",
        )
    })?;
    Ok(text.encode_utf16().collect())
}

pub fn encode_utf16_units(codec_id: u32, units: &[u16]) -> NativeResult<Vec<u8>> {
    if codec_index::canonical_name(codec_id) == "utf-7" {
        return Ok(encode_utf7_units(units));
    }
    let text = string_from_utf16_units(units)?;
    encode(codec_id, text.as_bytes())
}

fn decode_utf7_units(bytes: &[u8]) -> NativeResult<Vec<u16>> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut in_shift = false;
    let mut shift_start = 0usize;
    let mut base64_bits = 0usize;
    let mut base64_buffer = 0u32;
    let mut pending_high_surrogate: Option<u16> = None;
    let mut index = 0usize;

    while index < bytes.len() {
        let byte = bytes[index];
        if in_shift {
            if is_utf7_base64(byte) {
                base64_buffer = (base64_buffer << 6) | utf7_from_base64(byte) as u32;
                base64_bits += 6;
                index += 1;
                while base64_bits >= 16 {
                    let unit = ((base64_buffer >> (base64_bits - 16)) & 0xFFFF) as u16;
                    base64_bits -= 16;
                    base64_buffer &= low_bit_mask(base64_bits);
                    if let Some(high) = pending_high_surrogate.take() {
                        out.push(high);
                        if is_low_surrogate(unit) {
                            out.push(unit);
                            continue;
                        }
                    }
                    if is_high_surrogate(unit) {
                        pending_high_surrogate = Some(unit);
                    } else {
                        out.push(unit);
                    }
                }
                continue;
            }

            in_shift = false;
            if base64_bits > 0 {
                if base64_bits >= 6 {
                    return Err(err(
                        shift_start as u32,
                        "partial character in UTF-7 shift sequence",
                    ));
                }
                if base64_buffer != 0 {
                    return Err(err(
                        shift_start as u32,
                        "non-zero padding bits in UTF-7 shift sequence",
                    ));
                }
            }
            if let Some(high) = pending_high_surrogate.take()
                && is_utf7_decode_direct(byte)
            {
                out.push(high);
            }
            base64_bits = 0;
            base64_buffer = 0;
            if byte == b'-' {
                index += 1;
            }
            continue;
        }

        if byte == b'+' {
            shift_start = index;
            index += 1;
            if bytes.get(index) == Some(&b'-') {
                index += 1;
                out.push(b'+' as u16);
                continue;
            }
            if let Some(&next) = bytes.get(index)
                && !is_utf7_base64(next)
            {
                return Err(err(shift_start as u32, "ill-formed UTF-7 shift sequence"));
            }
            in_shift = true;
            base64_bits = 0;
            base64_buffer = 0;
            pending_high_surrogate = None;
            continue;
        }

        if is_utf7_decode_direct(byte) {
            out.push(byte as u16);
            index += 1;
            continue;
        }
        return Err(err(
            index as u32,
            "unexpected special character in UTF-7 input",
        ));
    }

    if in_shift {
        let inconsistent = pending_high_surrogate.is_some()
            || base64_bits >= 6
            || (base64_bits > 0 && base64_buffer != 0);
        if inconsistent {
            return Err(err(shift_start as u32, "unterminated UTF-7 shift sequence"));
        }
    }
    Ok(out)
}

fn encode_utf7_units(units: &[u16]) -> Vec<u8> {
    let mut out = Vec::with_capacity(units.len());
    let mut in_shift = false;
    let mut base64_bits = 0usize;
    let mut base64_buffer = 0u32;

    for &unit in units {
        if in_shift && is_utf7_encode_direct(unit) {
            flush_utf7_padding(&mut out, &mut base64_buffer, &mut base64_bits);
            in_shift = false;
            if is_utf7_base64(unit as u8) || unit == b'-' as u16 {
                out.push(b'-');
            }
            out.push(unit as u8);
            continue;
        }
        if in_shift {
            append_utf7_unit(&mut out, unit, &mut base64_buffer, &mut base64_bits);
            continue;
        }
        if unit == b'+' as u16 {
            out.extend_from_slice(b"+-");
            continue;
        }
        if is_utf7_encode_direct(unit) {
            out.push(unit as u8);
            continue;
        }
        out.push(b'+');
        in_shift = true;
        append_utf7_unit(&mut out, unit, &mut base64_buffer, &mut base64_bits);
    }

    flush_utf7_padding(&mut out, &mut base64_buffer, &mut base64_bits);
    if in_shift {
        out.push(b'-');
    }
    out
}

fn append_utf7_unit(
    out: &mut Vec<u8>,
    unit: u16,
    base64_buffer: &mut u32,
    base64_bits: &mut usize,
) {
    *base64_buffer = (*base64_buffer << 16) | unit as u32;
    *base64_bits += 16;
    while *base64_bits >= 6 {
        out.push(utf7_to_base64(*base64_buffer >> (*base64_bits - 6)));
        *base64_bits -= 6;
        *base64_buffer &= low_bit_mask(*base64_bits);
    }
}

fn flush_utf7_padding(out: &mut Vec<u8>, base64_buffer: &mut u32, base64_bits: &mut usize) {
    if *base64_bits > 0 {
        out.push(utf7_to_base64(*base64_buffer << (6 - *base64_bits)));
        *base64_bits = 0;
        *base64_buffer = 0;
    }
}

fn string_from_utf16_units(units: &[u16]) -> NativeResult<String> {
    let mut out = String::with_capacity(units.len());
    for (index, decoded) in std::char::decode_utf16(units.iter().copied()).enumerate() {
        match decoded {
            Ok(ch) => out.push(ch),
            Err(_) => {
                return Err(err(
                    index as u32,
                    "input contains invalid surrogate sequence",
                ));
            }
        }
    }
    Ok(out)
}

fn is_utf7_base64(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'+' || byte == b'/'
}

fn utf7_from_base64(byte: u8) -> u8 {
    match byte {
        b'A'..=b'Z' => byte - b'A',
        b'a'..=b'z' => byte - b'a' + 26,
        b'0'..=b'9' => byte - b'0' + 52,
        b'+' => 62,
        _ => 63,
    }
}

fn utf7_to_base64(value: u32) -> u8 {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    ALPHABET[(value & 0x3F) as usize]
}

fn is_utf7_decode_direct(byte: u8) -> bool {
    byte <= 0x7F && byte != b'+'
}

fn is_utf7_encode_direct(unit: u16) -> bool {
    if unit == 0 || unit >= 0x80 {
        return false;
    }
    if matches!(unit, 0x2B | 0x5C | 0x7E | 0x7F) {
        return false;
    }
    unit >= 0x20 || matches!(unit, 0x09 | 0x0A | 0x0D)
}

fn low_bit_mask(bits: usize) -> u32 {
    if bits == 0 { 0 } else { (1u32 << bits) - 1 }
}

fn is_high_surrogate(unit: u16) -> bool {
    (0xD800..=0xDBFF).contains(&unit)
}

fn is_low_surrogate(unit: u16) -> bool {
    (0xDC00..=0xDFFF).contains(&unit)
}

#[derive(Clone, Copy)]
enum Endian {
    Little,
    Big,
}

fn native_endian() -> Endian {
    if cfg!(target_endian = "little") {
        Endian::Little
    } else {
        Endian::Big
    }
}

fn decode_utf8(bytes: &[u8]) -> NativeResult<String> {
    std::str::from_utf8(bytes)
        .map(|value| value.to_owned())
        .map_err(|error| err(error.valid_up_to() as u32, "invalid UTF-8 byte sequence"))
}

fn decode_utf8_sig(bytes: &[u8]) -> NativeResult<String> {
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        decode_utf8(&bytes[3..])
    } else {
        decode_utf8(bytes)
    }
}

fn decode_utf16_auto(bytes: &[u8]) -> NativeResult<String> {
    if bytes.is_empty() {
        return Ok(String::new());
    }
    if bytes.len() >= 2 {
        match (bytes[0], bytes[1]) {
            (0xFF, 0xFE) => return decode_utf16_endian(&bytes[2..], Endian::Little),
            (0xFE, 0xFF) => return decode_utf16_endian(&bytes[2..], Endian::Big),
            _ => {}
        }
    }
    Err(err(
        0,
        "UTF-16 stream does not start with a byte-order mark",
    ))
}

fn decode_utf16_endian(bytes: &[u8], endian: Endian) -> NativeResult<String> {
    if !bytes.len().is_multiple_of(2) {
        return Err(err(
            bytes.len() as u32 - 1,
            "odd byte length for UTF-16 decode",
        ));
    }
    let mut units = Vec::with_capacity(bytes.len() / 2);
    for chunk in bytes.chunks_exact(2) {
        let unit = match endian {
            Endian::Little => u16::from_le_bytes([chunk[0], chunk[1]]),
            Endian::Big => u16::from_be_bytes([chunk[0], chunk[1]]),
        };
        units.push(unit);
    }
    let mut out = String::new();
    for (index, decoded) in std::char::decode_utf16(units.into_iter()).enumerate() {
        match decoded {
            Ok(ch) => out.push(ch),
            Err(_) => return Err(err((index * 2) as u32, "invalid UTF-16 surrogate pair")),
        }
    }
    Ok(out)
}

fn decode_utf32_auto(bytes: &[u8]) -> NativeResult<String> {
    if bytes.is_empty() {
        return Ok(String::new());
    }
    if bytes.len() >= 4 {
        match (bytes[0], bytes[1], bytes[2], bytes[3]) {
            (0xFF, 0xFE, 0x00, 0x00) => return decode_utf32_endian(&bytes[4..], Endian::Little),
            (0x00, 0x00, 0xFE, 0xFF) => return decode_utf32_endian(&bytes[4..], Endian::Big),
            _ => {}
        }
    }
    Err(err(
        0,
        "UTF-32 stream does not start with a byte-order mark",
    ))
}

fn decode_utf32_endian(bytes: &[u8], endian: Endian) -> NativeResult<String> {
    if !bytes.len().is_multiple_of(4) {
        return Err(err(
            (bytes.len() - (bytes.len() % 4)) as u32,
            "byte length not divisible by 4 for UTF-32 decode",
        ));
    }
    let mut out = String::with_capacity(bytes.len() / 4);
    for (index, chunk) in bytes.chunks_exact(4).enumerate() {
        let scalar = match endian {
            Endian::Little => u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]),
            Endian::Big => u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]),
        };
        if (0xD800..=0xDFFF).contains(&scalar) || scalar > 0x10FFFF {
            return Err(err((index * 4) as u32, "invalid UTF-32 scalar value"));
        }
        let ch = char::from_u32(scalar)
            .ok_or_else(|| err((index * 4) as u32, "invalid UTF-32 scalar value"))?;
        out.push(ch);
    }
    Ok(out)
}

fn encode_utf16(text: &str, endian: Option<Endian>) -> Vec<u8> {
    encode_utf16_with_endian(text, endian.unwrap_or_else(native_endian), true)
}

fn encode_utf16_with_endian(text: &str, endian: Endian, emit_bom: bool) -> Vec<u8> {
    let mut out = Vec::with_capacity((text.len() + if emit_bom { 1 } else { 0 }) * 2);
    if emit_bom {
        match endian {
            Endian::Little => out.extend_from_slice(&[0xFF, 0xFE]),
            Endian::Big => out.extend_from_slice(&[0xFE, 0xFF]),
        }
    }
    for unit in text.encode_utf16() {
        match endian {
            Endian::Little => out.extend_from_slice(&unit.to_le_bytes()),
            Endian::Big => out.extend_from_slice(&unit.to_be_bytes()),
        }
    }
    out
}

fn encode_utf32(text: &str, endian: Option<Endian>) -> Vec<u8> {
    encode_utf32_with_endian(text, endian.unwrap_or_else(native_endian), true)
}

fn encode_utf32_with_endian(text: &str, endian: Endian, emit_bom: bool) -> Vec<u8> {
    let mut out = Vec::with_capacity((text.chars().count() + if emit_bom { 1 } else { 0 }) * 4);
    if emit_bom {
        match endian {
            Endian::Little => out.extend_from_slice(&[0xFF, 0xFE, 0x00, 0x00]),
            Endian::Big => out.extend_from_slice(&[0x00, 0x00, 0xFE, 0xFF]),
        }
    }
    for ch in text.chars() {
        let scalar = ch as u32;
        match endian {
            Endian::Little => out.extend_from_slice(&scalar.to_le_bytes()),
            Endian::Big => out.extend_from_slice(&scalar.to_be_bytes()),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::{decode_utf7_units, encode_utf7_units};

    #[test]
    fn utf7_representative_vectors_round_trip() {
        let units = [0x0041, 0x2262, 0x0391, 0x002E];
        let encoded = encode_utf7_units(&units);
        assert_eq!(encoded, b"A+ImIDkQ.");
        assert!(matches!(
            decode_utf7_units(&encoded),
            Ok(ref decoded) if decoded == &units
        ));
    }

    #[test]
    fn utf7_preserves_lone_surrogate_units() {
        let units = [0xD801];
        let encoded = encode_utf7_units(&units);
        assert_eq!(encoded, b"+2AE-");
        assert!(matches!(
            decode_utf7_units(&encoded),
            Ok(ref decoded) if decoded == &units
        ));
    }

    #[test]
    fn utf7_rejects_ill_formed_shift_sequence() {
        assert!(decode_utf7_units(b"a+@b").is_err());
        assert!(decode_utf7_units(b"a+IK").is_err());
    }
}
