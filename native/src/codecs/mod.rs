// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

mod blob_reader;

pub mod gb18030;
pub mod mbcs;
pub mod sbcs;
pub mod stateful;
pub mod utf;

use crate::backend::{NativeResult, err};
use crate::generated::codec_index;

const STRICT_ERROR_MODE: u32 = 0;

pub fn decode_to_utf16le(codec_id: u32, error_mode: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    if !codec_index::native_supports(codec_id) {
        return Err(err(
            0,
            "codec is disabled by the generated native route matrix",
        ));
    }
    if error_mode != STRICT_ERROR_MODE {
        return Err(err(
            0,
            "native backend currently supports only strict error mode",
        ));
    }
    let units = if utf::supports(codec_id) {
        utf::decode_utf16_units(codec_id, bytes)?
    } else {
        let decoded = decode(codec_id, error_mode, bytes)?;
        let text = std::str::from_utf8(&decoded).map_err(|error| {
            err(
                error.valid_up_to() as u32,
                "native codec output was not valid UTF-8",
            )
        })?;
        text.encode_utf16().collect()
    };
    let mut out = Vec::with_capacity(units.len() * 2);
    for unit in units {
        out.extend_from_slice(&unit.to_le_bytes());
    }
    Ok(out)
}

pub fn encode_from_utf16(codec_id: u32, error_mode: u32, units: &[u16]) -> NativeResult<Vec<u8>> {
    if !codec_index::native_supports(codec_id) {
        return Err(err(
            0,
            "codec is disabled by the generated native route matrix",
        ));
    }
    if error_mode != STRICT_ERROR_MODE {
        return Err(err(
            0,
            "native backend currently supports only strict error mode",
        ));
    }
    if utf::supports(codec_id) {
        return utf::encode_utf16_units(codec_id, units);
    }
    let mut text = String::with_capacity(units.len());
    for (index, decoded) in std::char::decode_utf16(units.iter().copied()).enumerate() {
        match decoded {
            Ok(ch) => text.push(ch),
            Err(_) => {
                return Err(err(
                    index as u32,
                    "input contains invalid surrogate sequence",
                ));
            }
        }
    }
    encode(codec_id, error_mode, text.as_bytes())
}

pub fn decode(codec_id: u32, error_mode: u32, bytes: &[u8]) -> NativeResult<Vec<u8>> {
    if error_mode != STRICT_ERROR_MODE {
        return Err(err(
            0,
            "native backend currently supports only strict error mode",
        ));
    }
    if utf::supports(codec_id) {
        return utf::decode(codec_id, bytes);
    }
    if gb18030::supports(codec_id) {
        return gb18030::decode(codec_id, bytes);
    }
    if stateful::supports(codec_id) {
        return stateful::decode(codec_id, bytes);
    }
    if mbcs::supports(codec_id) {
        return mbcs::decode(codec_id, bytes);
    }
    if sbcs::supports(codec_id) {
        return sbcs::decode(codec_id, bytes);
    }
    Err(err(
        0,
        format!(
            "native backend does not implement codec {} yet",
            codec_index::canonical_name(codec_id)
        ),
    ))
}

pub fn encode(codec_id: u32, error_mode: u32, utf8_bytes: &[u8]) -> NativeResult<Vec<u8>> {
    if error_mode != STRICT_ERROR_MODE {
        return Err(err(
            0,
            "native backend currently supports only strict error mode",
        ));
    }
    if utf::supports(codec_id) {
        return utf::encode(codec_id, utf8_bytes);
    }
    if gb18030::supports(codec_id) {
        return gb18030::encode(codec_id, utf8_bytes);
    }
    if stateful::supports(codec_id) {
        return stateful::encode(codec_id, utf8_bytes);
    }
    if mbcs::supports(codec_id) {
        return mbcs::encode(codec_id, utf8_bytes);
    }
    if sbcs::supports(codec_id) {
        return sbcs::encode(codec_id, utf8_bytes);
    }
    Err(err(
        0,
        format!(
            "native backend does not implement codec {} yet",
            codec_index::canonical_name(codec_id)
        ),
    ))
}

pub fn validate(codec_id: u32, bytes: &[u8]) -> bool {
    if utf::supports(codec_id) {
        return utf::validate(codec_id, bytes);
    }
    if gb18030::supports(codec_id) {
        return gb18030::validate(codec_id, bytes);
    }
    if stateful::supports(codec_id) {
        return stateful::validate(codec_id, bytes);
    }
    if mbcs::supports(codec_id) {
        return mbcs::validate(codec_id, bytes);
    }
    if sbcs::supports(codec_id) {
        return sbcs::validate(codec_id, bytes);
    }
    false
}

#[cfg(test)]
mod tests {
    use super::{decode_to_utf16le, encode_from_utf16};
    use crate::generated::codec_index;

    #[test]
    fn every_generated_codec_can_initialize_its_native_tables() {
        for codec_id in 0..codec_index::CANONICAL_NAMES.len() as u32 {
            assert!(
                codec_index::native_supports(codec_id),
                "generated native route matrix disabled {}",
                codec_index::canonical_name(codec_id)
            );
            let decoded = decode_to_utf16le(codec_id, 0, &[]);
            let encoded = encode_from_utf16(codec_id, 0, &[]);
            assert!(
                decoded.is_ok(),
                "native decode table failed to initialize for {}",
                codec_index::canonical_name(codec_id)
            );
            assert!(
                encoded.is_ok(),
                "native encode table failed to initialize for {}",
                codec_index::canonical_name(codec_id)
            );
        }
    }
}
