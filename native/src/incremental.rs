// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use std::slice;

use crate::backend::{NativeResult, bytes_from_raw, catch_native_result, err, result_to_ptr};
use crate::codecs::{self, gb18030, mbcs, sbcs, stateful};
use crate::generated::codec_index;

const STRICT_ERROR_MODE: u32 = 0;
const STATE_VERSION: u8 = 1;
const KIND_DECODER: u8 = 0;
const KIND_ENCODER: u8 = 1;
const HEADER_LEN: usize = 20;

const DECODER_MODE_SINGLE_BYTE: u8 = 0;
const DECODER_MODE_SPLIT_BUFFER: u8 = 1;
const DECODER_MODE_STATEFUL: u8 = 2;

const ENCODER_MODE_CHUNKED: u8 = 0;
const ENCODER_MODE_STATEFUL: u8 = 1;

const HZ_CODEC_NAME: &str = "hz-gb-2312";
const ISO2022_KR_CODEC_NAME: &str = "iso-2022-kr";
const ASCII_RESET_ESCAPE: &[u8] = &[0x1B, 0x28, 0x42];
const KR_DESIGNATION_ESCAPE: &[u8] = &[0x1B, 0x24, 0x29, 0x43];

enum IncrementalSession {
    Decoder(DecoderSession),
    Encoder(EncoderSession),
}

struct DecoderSession {
    codec_id: u32,
    error_mode: u32,
    mode: u8,
    pending: Vec<u8>,
    max_sequence_length: usize,
    stateful: Option<StatefulDecoderControl>,
}

struct EncoderSession {
    codec_id: u32,
    error_mode: u32,
    mode: u8,
    buffered_units: Vec<u16>,
    stateful: Option<StatefulEncoderControl>,
}

#[derive(Default)]
struct StatefulDecoderControl {
    hz_in_gb: bool,
    kr_designated: bool,
    kr_shifted: bool,
    iso_esc_throughout: bool,
    iso_g0: Vec<u8>,
    iso_g2: Vec<u8>,
}

#[derive(Default)]
struct StatefulEncoderControl {
    hz_in_gb: bool,
    kr_designated: bool,
    kr_shifted: bool,
    iso_g0: Vec<u8>,
    iso_g2: Vec<u8>,
}

struct BoundedControl {
    flags: u8,
    g0: Vec<u8>,
    g2: Vec<u8>,
    tail: Vec<u8>,
}

#[unsafe(no_mangle)]
pub extern "C" fn charset_codec_incremental_decoder_create(codec_id: u32, error_mode: u32) -> u64 {
    if error_mode != STRICT_ERROR_MODE {
        return 0;
    }
    let Some(session) = DecoderSession::new(codec_id, error_mode) else {
        return 0;
    };
    box_into_handle(IncrementalSession::Decoder(session))
}

#[unsafe(no_mangle)]
pub extern "C" fn charset_codec_incremental_encoder_create(codec_id: u32, error_mode: u32) -> u64 {
    if error_mode != STRICT_ERROR_MODE {
        return 0;
    }
    let Some(session) = EncoderSession::new(codec_id, error_mode) else {
        return 0;
    };
    box_into_handle(IncrementalSession::Encoder(session))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live decoder session. `bytes` must describe a readable
/// region containing `length` bytes.
pub unsafe extern "C" fn charset_codec_incremental_decoder_feed(
    handle: u64,
    bytes: *const u8,
    length: usize,
    final_chunk: u8,
) -> *mut crate::backend::CodecResult {
    let input = unsafe { bytes_from_raw(bytes, length) };
    let final_chunk = final_chunk != 0;
    result_to_ptr(catch_native_result(|| {
        with_decoder_session(handle, |session| session.feed(input, final_chunk))
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live encoder session. `units` must be correctly aligned
/// and cover `length` `u16` values.
pub unsafe extern "C" fn charset_codec_incremental_encoder_feed_utf16(
    handle: u64,
    units: *const u16,
    length: usize,
    final_chunk: u8,
) -> *mut crate::backend::CodecResult {
    let input = unsafe { u16_units_from_raw(units, length) };
    let final_chunk = final_chunk != 0;
    result_to_ptr(catch_native_result(|| {
        with_encoder_session(handle, |session| session.feed(input, final_chunk))
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live decoder session and must not be accessed concurrently
/// by another thread.
pub unsafe extern "C" fn charset_codec_incremental_decoder_close(
    handle: u64,
) -> *mut crate::backend::CodecResult {
    result_to_ptr(catch_native_result(|| {
        with_decoder_session(handle, DecoderSession::close)
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live encoder session and must not be accessed concurrently
/// by another thread.
pub unsafe extern "C" fn charset_codec_incremental_encoder_close(
    handle: u64,
) -> *mut crate::backend::CodecResult {
    result_to_ptr(catch_native_result(|| {
        with_encoder_session(handle, EncoderSession::close)
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live session and must not be accessed concurrently by
/// another thread.
pub unsafe extern "C" fn charset_codec_incremental_session_reset(
    handle: u64,
) -> *mut crate::backend::CodecResult {
    result_to_ptr(catch_native_result(|| {
        with_session(handle, |session| {
            session.reset();
            Ok(Vec::new())
        })
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live session and must not be accessed concurrently by
/// another thread.
pub unsafe extern "C" fn charset_codec_incremental_session_get_state(
    handle: u64,
) -> *mut crate::backend::CodecResult {
    result_to_ptr(catch_native_result(|| {
        with_session(handle, |session| session.serialize_state())
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live session. `state_bytes` must describe a readable
/// region containing `state_length` bytes.
pub unsafe extern "C" fn charset_codec_incremental_session_set_state(
    handle: u64,
    state_bytes: *const u8,
    state_length: usize,
) -> *mut crate::backend::CodecResult {
    let state = unsafe { bytes_from_raw(state_bytes, state_length) };
    result_to_ptr(catch_native_result(|| {
        with_session(handle, |session| {
            session.restore_state(state)?;
            Ok(Vec::new())
        })
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// `handle` must be a live session created by this library. Each handle may be
/// destroyed only once.
pub unsafe extern "C" fn charset_codec_incremental_session_destroy(handle: u64) {
    if handle == 0 {
        return;
    }
    unsafe {
        drop(Box::from_raw(handle_to_ptr(handle)));
    }
}

fn with_session<T>(
    handle: u64,
    f: impl FnOnce(&mut IncrementalSession) -> NativeResult<T>,
) -> NativeResult<T> {
    let session = unsafe { session_from_handle(handle)? };
    f(session)
}

fn box_into_handle(session: IncrementalSession) -> u64 {
    Box::into_raw(Box::new(session)) as usize as u64
}

unsafe fn session_from_handle<'a>(handle: u64) -> NativeResult<&'a mut IncrementalSession> {
    if handle == 0 {
        return Err(err(0, "invalid incremental session handle"));
    }
    Ok(unsafe { &mut *handle_to_ptr(handle) })
}

fn handle_to_ptr(handle: u64) -> *mut IncrementalSession {
    handle as usize as *mut IncrementalSession
}

fn with_decoder_session<T>(
    handle: u64,
    f: impl FnOnce(&mut DecoderSession) -> NativeResult<T>,
) -> NativeResult<T> {
    with_session(handle, |session| match session {
        IncrementalSession::Decoder(decoder) => f(decoder),
        IncrementalSession::Encoder(_) => Err(err(0, "incremental session kind mismatch")),
    })
}

fn with_encoder_session<T>(
    handle: u64,
    f: impl FnOnce(&mut EncoderSession) -> NativeResult<T>,
) -> NativeResult<T> {
    with_session(handle, |session| match session {
        IncrementalSession::Encoder(encoder) => f(encoder),
        IncrementalSession::Decoder(_) => Err(err(0, "incremental session kind mismatch")),
    })
}

impl IncrementalSession {
    fn reset(&mut self) {
        match self {
            IncrementalSession::Decoder(session) => session.reset(),
            IncrementalSession::Encoder(session) => session.reset(),
        }
    }

    fn serialize_state(&self) -> NativeResult<Vec<u8>> {
        match self {
            IncrementalSession::Decoder(session) => session.serialize_state(),
            IncrementalSession::Encoder(session) => session.serialize_state(),
        }
    }

    fn restore_state(&mut self, bytes: &[u8]) -> NativeResult<()> {
        match self {
            IncrementalSession::Decoder(session) => session.restore_state(bytes),
            IncrementalSession::Encoder(session) => session.restore_state(bytes),
        }
    }
}

impl DecoderSession {
    fn new(codec_id: u32, error_mode: u32) -> Option<Self> {
        if !supports_native_incremental_decoder(codec_id) {
            return None;
        }
        let mode = if sbcs::supports(codec_id) {
            DECODER_MODE_SINGLE_BYTE
        } else if mbcs::supports(codec_id) {
            DECODER_MODE_SPLIT_BUFFER
        } else {
            DECODER_MODE_STATEFUL
        };
        Some(Self {
            codec_id,
            error_mode,
            mode,
            pending: Vec::new(),
            max_sequence_length: max_multibyte_sequence_length(codec_id),
            stateful: (mode == DECODER_MODE_STATEFUL).then(StatefulDecoderControl::default),
        })
    }

    fn feed(&mut self, chunk: &[u8], final_chunk: bool) -> NativeResult<Vec<u8>> {
        match self.mode {
            DECODER_MODE_SINGLE_BYTE => {
                if chunk.is_empty() {
                    return Ok(Vec::new());
                }
                codecs::decode(self.codec_id, self.error_mode, chunk)
            }
            DECODER_MODE_SPLIT_BUFFER => {
                if !chunk.is_empty() {
                    self.pending.extend_from_slice(chunk);
                }
                if self.pending.is_empty() {
                    return Ok(Vec::new());
                }
                if final_chunk {
                    let out = codecs::decode(self.codec_id, self.error_mode, &self.pending)?;
                    self.pending.clear();
                    return Ok(out);
                }
                match codecs::decode(self.codec_id, self.error_mode, &self.pending) {
                    Ok(out) => {
                        self.pending.clear();
                        Ok(out)
                    }
                    Err(error) => {
                        let max_tail = self.max_sequence_length.saturating_sub(1);
                        for tail in 1..=max_tail {
                            if self.pending.len() <= tail {
                                break;
                            }
                            let split = self.pending.len() - tail;
                            if let Ok(out) = codecs::decode(
                                self.codec_id,
                                self.error_mode,
                                &self.pending[..split],
                            ) {
                                let trailing = self.pending[split..].to_vec();
                                self.pending = trailing;
                                return Ok(out);
                            }
                        }
                        if self.pending.len() <= max_tail {
                            Ok(Vec::new())
                        } else {
                            Err(error)
                        }
                    }
                }
            }
            DECODER_MODE_STATEFUL => {
                if gb18030::supports(self.codec_id) {
                    return self.feed_gb18030_streaming(chunk, final_chunk);
                }
                self.feed_stateful_streaming(chunk, final_chunk)
            }
            _ => Err(err(0, "unsupported incremental decoder mode")),
        }
    }

    fn close(&mut self) -> NativeResult<Vec<u8>> {
        match self.mode {
            DECODER_MODE_STATEFUL => {
                if gb18030::supports(self.codec_id) {
                    return self.feed_gb18030_streaming(&[], true);
                }
                self.feed_stateful_streaming(&[], true)
            }
            _ => {
                if self.pending.is_empty() {
                    return Ok(Vec::new());
                }
                let out = codecs::decode(self.codec_id, self.error_mode, &self.pending)?;
                self.pending.clear();
                Ok(out)
            }
        }
    }

    fn reset(&mut self) {
        self.pending.clear();
        if let Some(stateful) = &mut self.stateful {
            *stateful = StatefulDecoderControl::default();
        }
    }

    fn feed_gb18030_streaming(&mut self, chunk: &[u8], final_chunk: bool) -> NativeResult<Vec<u8>> {
        if !chunk.is_empty() {
            self.pending.extend_from_slice(chunk);
        }
        if self.pending.is_empty() {
            return Ok(Vec::new());
        }
        let (decoded, consumed) =
            gb18030::decode_prefix(self.codec_id, &self.pending, final_chunk)?;
        if consumed > 0 {
            self.pending.drain(..consumed);
        }
        if final_chunk && !self.pending.is_empty() {
            return Err(err(0, "incomplete multibyte sequence"));
        }
        Ok(decoded)
    }

    fn feed_stateful_streaming(
        &mut self,
        chunk: &[u8],
        final_chunk: bool,
    ) -> NativeResult<Vec<u8>> {
        self.pending.extend_from_slice(chunk);
        if self.pending.is_empty() {
            return Ok(Vec::new());
        }
        let control = self
            .stateful
            .as_ref()
            .ok_or_else(|| err(0, "missing native stateful decoder control"))?;
        let (prefix, strip_prefix_output) = stateful_decoder_prefix(self.codec_id, control);
        let mut upper = self.pending.len();
        if !final_chunk
            && codec_index::canonical_name(self.codec_id) == HZ_CODEC_NAME
            && self.pending.ends_with(&[0x7E, 0x0D])
        {
            upper -= 2;
        }
        let canonical_name = codec_index::canonical_name(self.codec_id);
        if !final_chunk
            && (canonical_name == "iso-2022-jp" || canonical_name.starts_with("iso2022-jp"))
            && let Some(incomplete_start) = iso2022_incomplete_escape_start(&self.pending)
        {
            upper = upper.min(incomplete_start);
        }

        let mut split = upper;
        let mut payload = Vec::with_capacity(prefix.len() + upper);
        payload.extend_from_slice(&prefix);
        payload.extend_from_slice(&self.pending[..upper]);
        if !final_chunk {
            match stateful::decode(self.codec_id, &payload) {
                Ok(_) => {}
                Err(error) if is_possibly_incomplete_reason(&error.message) => {
                    split = (error.position as usize)
                        .saturating_sub(prefix.len())
                        .min(upper);
                }
                Err(mut error) => {
                    error.position = error.position.saturating_sub(prefix.len() as u32);
                    return Err(error);
                }
            }
        }
        if split == 0 {
            return Ok(Vec::new());
        }

        payload.truncate(prefix.len());
        payload.extend_from_slice(&self.pending[..split]);
        let mut decoded = stateful::decode(self.codec_id, &payload).map_err(|mut error| {
            error.position = error.position.saturating_sub(prefix.len() as u32);
            error
        })?;
        if strip_prefix_output > 0 {
            if decoded.len() < strip_prefix_output {
                return Err(err(0, "stateful decoder prefix output was truncated"));
            }
            decoded.drain(..strip_prefix_output);
        }
        let control = self
            .stateful
            .as_mut()
            .ok_or_else(|| err(0, "missing native stateful decoder control"))?;
        scan_stateful_decoder_control(self.codec_id, &self.pending[..split], control);
        self.pending.drain(..split);
        Ok(decoded)
    }

    fn serialize_state(&self) -> NativeResult<Vec<u8>> {
        let payload = if self.mode == DECODER_MODE_STATEFUL && !gb18030::supports(self.codec_id) {
            serialize_stateful_decoder_control(
                self.stateful
                    .as_ref()
                    .ok_or_else(|| err(0, "missing native stateful decoder control"))?,
                &self.pending,
            )
        } else {
            self.pending.clone()
        };
        Ok(serialize_state_header(
            KIND_DECODER,
            self.mode,
            self.codec_id,
            self.error_mode,
            0,
            &payload,
        ))
    }

    fn restore_state(&mut self, bytes: &[u8]) -> NativeResult<()> {
        let state = parse_state_header(bytes, KIND_DECODER)?;
        if state.codec_id != self.codec_id || state.error_mode != self.error_mode {
            return Err(err(
                0,
                "incremental decoder state does not match codec or error mode",
            ));
        }
        if state.mode != self.mode {
            return Err(err(0, "incremental decoder state mode mismatch"));
        }
        if self.mode == DECODER_MODE_STATEFUL && !gb18030::supports(self.codec_id) {
            let (control, pending) = parse_stateful_decoder_control(state.payload)?;
            self.stateful = Some(control);
            self.pending = pending;
        } else {
            self.pending.clear();
            self.pending.extend_from_slice(state.payload);
        }
        Ok(())
    }
}

impl EncoderSession {
    fn new(codec_id: u32, error_mode: u32) -> Option<Self> {
        if !supports_native_incremental_encoder(codec_id) {
            return None;
        }
        let mode = if gb18030::supports(codec_id) || stateful::supports(codec_id) {
            ENCODER_MODE_STATEFUL
        } else {
            ENCODER_MODE_CHUNKED
        };
        Some(Self {
            codec_id,
            error_mode,
            mode,
            buffered_units: Vec::new(),
            stateful: (mode == ENCODER_MODE_STATEFUL).then(StatefulEncoderControl::default),
        })
    }

    fn feed(&mut self, chunk: &[u16], final_chunk: bool) -> NativeResult<Vec<u8>> {
        match self.mode {
            ENCODER_MODE_STATEFUL => {
                if gb18030::supports(self.codec_id) {
                    return self.feed_gb18030_streaming(chunk, final_chunk);
                }
                self.feed_stateful_streaming(chunk, final_chunk)
            }
            ENCODER_MODE_CHUNKED => {
                let mut units = Vec::with_capacity(self.buffered_units.len() + chunk.len());
                units.extend_from_slice(&self.buffered_units);
                units.extend_from_slice(chunk);
                self.buffered_units.clear();
                if !final_chunk
                    && let Some(&last) = units.last()
                    && is_high_surrogate(last)
                {
                    self.buffered_units.push(last);
                    units.pop();
                }
                if units.is_empty() {
                    return Ok(Vec::new());
                }
                encode_units_for_codec(self.codec_id, self.error_mode, &units)
            }
            _ => Err(err(0, "unsupported incremental encoder mode")),
        }
    }

    fn close(&mut self) -> NativeResult<Vec<u8>> {
        if self.mode == ENCODER_MODE_STATEFUL {
            if gb18030::supports(self.codec_id) {
                return self.feed_gb18030_streaming(&[], true);
            }
            return self.feed_stateful_streaming(&[], true);
        }
        if self.buffered_units.is_empty() {
            return Ok(Vec::new());
        }
        let out = encode_units_for_codec(self.codec_id, self.error_mode, &self.buffered_units)?;
        self.buffered_units.clear();
        Ok(out)
    }

    fn reset(&mut self) {
        self.buffered_units.clear();
        if let Some(stateful) = &mut self.stateful {
            *stateful = StatefulEncoderControl::default();
        }
    }

    fn feed_gb18030_streaming(
        &mut self,
        chunk: &[u16],
        final_chunk: bool,
    ) -> NativeResult<Vec<u8>> {
        let mut units = Vec::with_capacity(self.buffered_units.len() + chunk.len());
        units.extend_from_slice(&self.buffered_units);
        units.extend_from_slice(chunk);
        self.buffered_units.clear();
        if !final_chunk
            && let Some(&last) = units.last()
            && is_high_surrogate(last)
        {
            self.buffered_units.push(last);
            units.pop();
        }
        if units.is_empty() {
            return Ok(Vec::new());
        }
        encode_units_for_codec(self.codec_id, self.error_mode, &units)
    }

    fn feed_stateful_streaming(
        &mut self,
        chunk: &[u16],
        final_chunk: bool,
    ) -> NativeResult<Vec<u8>> {
        let mut units = Vec::with_capacity(self.buffered_units.len() + chunk.len());
        units.extend_from_slice(&self.buffered_units);
        units.extend_from_slice(chunk);
        self.buffered_units.clear();
        if !final_chunk
            && let Some(&last) = units.last()
            && is_high_surrogate(last)
        {
            self.buffered_units.push(last);
            units.pop();
        }
        let encoded = if units.is_empty() {
            Vec::new()
        } else {
            encode_units_for_codec(self.codec_id, self.error_mode, &units)?
        };
        let control = self
            .stateful
            .as_mut()
            .ok_or_else(|| err(0, "missing native stateful encoder control"))?;
        transform_stateful_encoded(self.codec_id, encoded, control, final_chunk)
    }

    fn serialize_state(&self) -> NativeResult<Vec<u8>> {
        let payload = if self.mode == ENCODER_MODE_STATEFUL && !gb18030::supports(self.codec_id) {
            serialize_stateful_encoder_control(
                self.stateful
                    .as_ref()
                    .ok_or_else(|| err(0, "missing native stateful encoder control"))?,
                &self.buffered_units,
            )
        } else {
            utf16_units_to_bytes(&self.buffered_units)
        };
        Ok(serialize_state_header(
            KIND_ENCODER,
            self.mode,
            self.codec_id,
            self.error_mode,
            0,
            &payload,
        ))
    }

    fn restore_state(&mut self, bytes: &[u8]) -> NativeResult<()> {
        let state = parse_state_header(bytes, KIND_ENCODER)?;
        if state.codec_id != self.codec_id || state.error_mode != self.error_mode {
            return Err(err(
                0,
                "incremental encoder state does not match codec or error mode",
            ));
        }
        if state.mode != self.mode {
            return Err(err(0, "incremental encoder state mode mismatch"));
        }
        if self.mode == ENCODER_MODE_STATEFUL && !gb18030::supports(self.codec_id) {
            let (control, units) = parse_stateful_encoder_control(state.payload)?;
            self.stateful = Some(control);
            self.buffered_units = units;
        } else {
            self.buffered_units = bytes_to_utf16_units(state.payload)?;
        }
        Ok(())
    }
}

fn stateful_decoder_prefix(codec_id: u32, control: &StatefulDecoderControl) -> (Vec<u8>, usize) {
    match codec_index::canonical_name(codec_id) {
        HZ_CODEC_NAME => (
            if control.hz_in_gb {
                vec![0x7E, 0x7B]
            } else {
                Vec::new()
            },
            0,
        ),
        ISO2022_KR_CODEC_NAME => {
            let mut prefix = Vec::new();
            if control.kr_designated {
                prefix.extend_from_slice(KR_DESIGNATION_ESCAPE);
            }
            if control.kr_shifted {
                prefix.push(0x0E);
            }
            (prefix, 0)
        }
        _ => {
            let mut prefix = Vec::new();
            prefix.extend_from_slice(&control.iso_g2);
            prefix.extend_from_slice(&control.iso_g0);
            if control.iso_esc_throughout {
                prefix.push(0x1B);
            }
            (prefix, usize::from(control.iso_esc_throughout))
        }
    }
}

fn scan_stateful_decoder_control(
    codec_id: u32,
    bytes: &[u8],
    control: &mut StatefulDecoderControl,
) {
    match codec_index::canonical_name(codec_id) {
        HZ_CODEC_NAME => scan_hz_decoder_control(bytes, control),
        ISO2022_KR_CODEC_NAME => scan_kr_decoder_control(bytes, control),
        _ => scan_iso2022_decoder_control(codec_id, bytes, control),
    }
}

fn scan_hz_decoder_control(bytes: &[u8], control: &mut StatefulDecoderControl) {
    let mut index = 0usize;
    while index < bytes.len() {
        if bytes[index] == 0x7E && index + 1 < bytes.len() {
            let next = bytes[index + 1];
            if next == 0x7B {
                control.hz_in_gb = true;
            } else if next == 0x7D {
                control.hz_in_gb = false;
            }
            index += if next == 0x0D && index + 2 < bytes.len() && bytes[index + 2] == 0x0A {
                3
            } else {
                2
            };
        } else {
            index += if control.hz_in_gb { 2 } else { 1 };
        }
    }
}

fn scan_kr_decoder_control(bytes: &[u8], control: &mut StatefulDecoderControl) {
    let mut index = 0usize;
    while index < bytes.len() {
        if bytes[index..].starts_with(KR_DESIGNATION_ESCAPE) {
            control.kr_designated = true;
            index += KR_DESIGNATION_ESCAPE.len();
        } else if bytes[index] == 0x0E {
            control.kr_shifted = true;
            index += 1;
        } else if bytes[index] == 0x0F {
            control.kr_shifted = false;
            index += 1;
        } else {
            index += if control.kr_shifted { 2 } else { 1 };
        }
    }
}

fn scan_iso2022_decoder_control(codec_id: u32, bytes: &[u8], control: &mut StatefulDecoderControl) {
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        if control.iso_esc_throughout {
            if is_iso2022_escape_end(byte) {
                control.iso_esc_throughout = false;
            }
            index += 1;
            continue;
        }
        if byte != 0x1B {
            index += 1;
            continue;
        }
        if codec_index::canonical_name(codec_id) == "iso2022-jp-2"
            && index + 2 < bytes.len()
            && bytes[index + 1] == 0x4E
        {
            index += 3;
            continue;
        }
        if let Some((length, target_g2, ascii)) = iso2022_designation_at(bytes, index) {
            let designation = if ascii {
                Vec::new()
            } else {
                bytes[index..index + length].to_vec()
            };
            if target_g2 {
                control.iso_g2 = designation;
            } else {
                control.iso_g0 = designation;
            }
            index += length;
            continue;
        }
        control.iso_esc_throughout = true;
        index += 1;
    }
}

fn iso2022_designation_at(bytes: &[u8], offset: usize) -> Option<(usize, bool, bool)> {
    let remaining = bytes.get(offset..)?;
    if remaining.starts_with(ASCII_RESET_ESCAPE) {
        return Some((3, false, true));
    }
    const G0_THREE: &[[u8; 3]] = &[
        [0x1B, 0x28, 0x49],
        [0x1B, 0x28, 0x4A],
        [0x1B, 0x24, 0x42],
        [0x1B, 0x24, 0x40],
    ];
    const G0_FOUR: &[[u8; 4]] = &[
        [0x1B, 0x24, 0x28, 0x41],
        [0x1B, 0x24, 0x28, 0x43],
        [0x1B, 0x24, 0x28, 0x44],
        [0x1B, 0x24, 0x28, 0x50],
        [0x1B, 0x24, 0x28, 0x51],
        [0x1B, 0x24, 0x28, 0x40],
    ];
    const G2_THREE: &[[u8; 3]] = &[[0x1B, 0x2E, 0x41], [0x1B, 0x2E, 0x46], [0x1B, 0x2E, 0x42]];
    if G0_THREE
        .iter()
        .any(|sequence| remaining.starts_with(sequence))
    {
        return Some((3, false, false));
    }
    if G0_FOUR
        .iter()
        .any(|sequence| remaining.starts_with(sequence))
    {
        return Some((4, false, false));
    }
    if G2_THREE
        .iter()
        .any(|sequence| remaining.starts_with(sequence))
    {
        return Some((3, true, remaining.starts_with(&[0x1B, 0x2E, 0x42])));
    }
    if remaining.starts_with(&[0x1B, 0x26, 0x40, 0x1B, 0x24, 0x42]) {
        return Some((6, false, false));
    }
    None
}

fn iso2022_incomplete_escape_start(bytes: &[u8]) -> Option<usize> {
    const PATTERNS: &[&[u8]] = &[
        &[0x1B, 0x28, 0x42],
        &[0x1B, 0x28, 0x49],
        &[0x1B, 0x28, 0x4A],
        &[0x1B, 0x24, 0x42],
        &[0x1B, 0x24, 0x40],
        &[0x1B, 0x24, 0x28, 0x41],
        &[0x1B, 0x24, 0x28, 0x43],
        &[0x1B, 0x24, 0x28, 0x44],
        &[0x1B, 0x24, 0x28, 0x50],
        &[0x1B, 0x24, 0x28, 0x51],
        &[0x1B, 0x24, 0x28, 0x40],
        &[0x1B, 0x2E, 0x41],
        &[0x1B, 0x2E, 0x46],
        &[0x1B, 0x2E, 0x42],
        &[0x1B, 0x26, 0x40, 0x1B, 0x24, 0x42],
    ];
    let search_start = bytes.len().saturating_sub(6);
    for index in search_start..bytes.len() {
        if bytes[index] != 0x1B {
            continue;
        }
        let suffix = &bytes[index..];
        if suffix.len() == 1
            || (suffix.len() < 3 && suffix.starts_with(&[0x1B, 0x4E]))
            || PATTERNS
                .iter()
                .any(|pattern| suffix.len() < pattern.len() && pattern.starts_with(suffix))
        {
            return Some(index);
        }
    }
    None
}

fn is_iso2022_escape_end(byte: u8) -> bool {
    byte.is_ascii_uppercase() || byte == 0x40
}

fn transform_stateful_encoded(
    codec_id: u32,
    encoded: Vec<u8>,
    control: &mut StatefulEncoderControl,
    final_chunk: bool,
) -> NativeResult<Vec<u8>> {
    match codec_index::canonical_name(codec_id) {
        HZ_CODEC_NAME => Ok(transform_hz_encoded(encoded, control, final_chunk)),
        ISO2022_KR_CODEC_NAME => Ok(transform_kr_encoded(encoded, control, final_chunk)),
        _ => transform_iso2022_encoded(encoded, control, final_chunk),
    }
}

fn transform_hz_encoded(
    mut encoded: Vec<u8>,
    control: &mut StatefulEncoderControl,
    final_chunk: bool,
) -> Vec<u8> {
    let was_in_gb = control.hz_in_gb;
    let chunk_ends_in_gb = encoded.ends_with(&[0x7E, 0x7D]);
    if was_in_gb && !encoded.is_empty() {
        if encoded.starts_with(&[0x7E, 0x7B]) {
            encoded.drain(..2);
        } else {
            encoded.splice(..0, [0x7E, 0x7D]);
        }
    }
    if !final_chunk && chunk_ends_in_gb {
        encoded.truncate(encoded.len() - 2);
        control.hz_in_gb = true;
    } else if encoded.is_empty() && !final_chunk {
        control.hz_in_gb = was_in_gb;
    } else {
        control.hz_in_gb = false;
    }
    if final_chunk && encoded.is_empty() && was_in_gb {
        encoded.extend_from_slice(&[0x7E, 0x7D]);
        control.hz_in_gb = false;
    }
    encoded
}

fn transform_kr_encoded(
    mut encoded: Vec<u8>,
    control: &mut StatefulEncoderControl,
    final_chunk: bool,
) -> Vec<u8> {
    let was_designated = control.kr_designated;
    let was_shifted = control.kr_shifted;
    let designation_offset = find_subslice(&encoded, KR_DESIGNATION_ESCAPE);
    let chunk_designates = designation_offset.is_some();
    if was_designated && let Some(offset) = designation_offset {
        encoded.drain(offset..offset + KR_DESIGNATION_ESCAPE.len());
    }
    if was_shifted && !encoded.is_empty() {
        if encoded[0] == 0x0E {
            encoded.remove(0);
        } else {
            encoded.insert(0, 0x0F);
        }
    }
    let chunk_ends_shifted = encoded.last() == Some(&0x0F);
    if !final_chunk && chunk_ends_shifted {
        encoded.pop();
        control.kr_shifted = true;
    } else if encoded.is_empty() && !final_chunk {
        control.kr_shifted = was_shifted;
    } else {
        control.kr_shifted = false;
    }
    control.kr_designated = was_designated || chunk_designates;
    if final_chunk {
        if encoded.is_empty() && was_shifted {
            encoded.push(0x0F);
        }
        control.kr_designated = false;
        control.kr_shifted = false;
    }
    encoded
}

fn transform_iso2022_encoded(
    mut encoded: Vec<u8>,
    control: &mut StatefulEncoderControl,
    final_chunk: bool,
) -> NativeResult<Vec<u8>> {
    if !final_chunk && encoded.ends_with(ASCII_RESET_ESCAPE) {
        encoded.truncate(encoded.len() - ASCII_RESET_ESCAPE.len());
    }
    let mut out = Vec::with_capacity(encoded.len() + 3);
    let mut index = 0usize;
    if !control.iso_g0.is_empty() && !encoded.is_empty() {
        let begins_designation = iso2022_designation_at(&encoded, 0).is_some();
        let begins_single_shift = encoded.starts_with(&[0x1B, 0x4E]);
        if !begins_designation && !begins_single_shift {
            out.extend_from_slice(ASCII_RESET_ESCAPE);
            control.iso_g0.clear();
        }
    }
    while index < encoded.len() {
        if let Some((length, target_g2, ascii)) = iso2022_designation_at(&encoded, index) {
            let next = if ascii {
                Vec::new()
            } else {
                encoded[index..index + length].to_vec()
            };
            let current = if target_g2 {
                &mut control.iso_g2
            } else {
                &mut control.iso_g0
            };
            if *current != next {
                out.extend_from_slice(&encoded[index..index + length]);
                *current = next;
            }
            index += length;
            continue;
        }
        if encoded[index..].starts_with(&[0x1B, 0x4E]) {
            let end = (index + 3).min(encoded.len());
            out.extend_from_slice(&encoded[index..end]);
            index = end;
            continue;
        }
        out.push(encoded[index]);
        index += 1;
    }
    if final_chunk {
        if out.is_empty() && !control.iso_g0.is_empty() {
            out.extend_from_slice(ASCII_RESET_ESCAPE);
        }
        control.iso_g0.clear();
        control.iso_g2.clear();
    }
    Ok(out)
}

fn find_subslice(bytes: &[u8], pattern: &[u8]) -> Option<usize> {
    bytes
        .windows(pattern.len())
        .position(|window| window == pattern)
}

fn serialize_stateful_decoder_control(control: &StatefulDecoderControl, pending: &[u8]) -> Vec<u8> {
    let flags = u8::from(control.hz_in_gb)
        | (u8::from(control.kr_designated) << 1)
        | (u8::from(control.kr_shifted) << 2)
        | (u8::from(control.iso_esc_throughout) << 3);
    serialize_bounded_control(flags, &control.iso_g0, &control.iso_g2, pending)
}

fn parse_stateful_decoder_control(
    payload: &[u8],
) -> NativeResult<(StatefulDecoderControl, Vec<u8>)> {
    let parsed = parse_bounded_control(payload, 8)?;
    Ok((
        StatefulDecoderControl {
            hz_in_gb: parsed.flags & 1 != 0,
            kr_designated: parsed.flags & 2 != 0,
            kr_shifted: parsed.flags & 4 != 0,
            iso_esc_throughout: parsed.flags & 8 != 0,
            iso_g0: parsed.g0,
            iso_g2: parsed.g2,
        },
        parsed.tail,
    ))
}

fn serialize_stateful_encoder_control(
    control: &StatefulEncoderControl,
    pending_units: &[u16],
) -> Vec<u8> {
    let flags = u8::from(control.hz_in_gb)
        | (u8::from(control.kr_designated) << 1)
        | (u8::from(control.kr_shifted) << 2);
    serialize_bounded_control(
        flags,
        &control.iso_g0,
        &control.iso_g2,
        &utf16_units_to_bytes(pending_units),
    )
}

fn parse_stateful_encoder_control(
    payload: &[u8],
) -> NativeResult<(StatefulEncoderControl, Vec<u16>)> {
    let parsed = parse_bounded_control(payload, 2)?;
    let units = bytes_to_utf16_units(&parsed.tail)?;
    if units.len() > 1 {
        return Err(err(
            0,
            "stateful encoder pending state exceeded one UTF-16 unit",
        ));
    }
    Ok((
        StatefulEncoderControl {
            hz_in_gb: parsed.flags & 1 != 0,
            kr_designated: parsed.flags & 2 != 0,
            kr_shifted: parsed.flags & 4 != 0,
            iso_g0: parsed.g0,
            iso_g2: parsed.g2,
        },
        units,
    ))
}

fn serialize_bounded_control(flags: u8, g0: &[u8], g2: &[u8], tail: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + g0.len() + g2.len() + tail.len());
    out.push(flags);
    out.push(g0.len() as u8);
    out.push(g2.len() as u8);
    out.push(tail.len() as u8);
    out.extend_from_slice(g0);
    out.extend_from_slice(g2);
    out.extend_from_slice(tail);
    out
}

fn parse_bounded_control(payload: &[u8], max_tail: usize) -> NativeResult<BoundedControl> {
    if payload.len() < 4 {
        return Err(err(0, "stateful incremental control is truncated"));
    }
    let g0_len = payload[1] as usize;
    let g2_len = payload[2] as usize;
    let tail_len = payload[3] as usize;
    let expected = 4 + g0_len + g2_len + tail_len;
    if expected != payload.len() || g0_len > 6 || g2_len > 3 || tail_len > max_tail {
        return Err(err(0, "stateful incremental control length is invalid"));
    }
    let g0_start = 4;
    let g2_start = g0_start + g0_len;
    let tail_start = g2_start + g2_len;
    Ok(BoundedControl {
        flags: payload[0],
        g0: payload[g0_start..g2_start].to_vec(),
        g2: payload[g2_start..tail_start].to_vec(),
        tail: payload[tail_start..].to_vec(),
    })
}

struct ParsedState<'a> {
    mode: u8,
    codec_id: u32,
    error_mode: u32,
    payload: &'a [u8],
}

fn serialize_state_header(
    kind: u8,
    mode: u8,
    codec_id: u32,
    error_mode: u32,
    reserved: u32,
    payload: &[u8],
) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER_LEN + payload.len());
    out.push(STATE_VERSION);
    out.push(kind);
    out.push(mode);
    out.push(0);
    out.extend_from_slice(&codec_id.to_le_bytes());
    out.extend_from_slice(&error_mode.to_le_bytes());
    out.extend_from_slice(&reserved.to_le_bytes());
    out.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    out.extend_from_slice(payload);
    out
}

fn parse_state_header<'a>(bytes: &'a [u8], expected_kind: u8) -> NativeResult<ParsedState<'a>> {
    if bytes.len() < HEADER_LEN {
        return Err(err(0, "incremental state blob is truncated"));
    }
    if bytes[0] != STATE_VERSION {
        return Err(err(0, "incremental state blob version mismatch"));
    }
    if bytes[1] != expected_kind {
        return Err(err(0, "incremental state blob kind mismatch"));
    }
    let mode = bytes[2];
    let codec_id = read_u32(bytes, 4);
    let error_mode = read_u32(bytes, 8);
    if read_u32(bytes, 12) != 0 {
        return Err(err(0, "incremental state reserved field must be zero"));
    }
    let payload_len = read_u32(bytes, 16) as usize;
    if HEADER_LEN + payload_len != bytes.len() {
        return Err(err(0, "incremental state blob payload length mismatch"));
    }
    Ok(ParsedState {
        mode,
        codec_id,
        error_mode,
        payload: &bytes[HEADER_LEN..],
    })
}

fn supports_native_incremental_decoder(codec_id: u32) -> bool {
    sbcs::supports(codec_id)
        || mbcs::supports(codec_id)
        || gb18030::supports(codec_id)
        || stateful::supports(codec_id)
}

fn supports_native_incremental_encoder(codec_id: u32) -> bool {
    sbcs::supports(codec_id)
        || mbcs::supports(codec_id)
        || gb18030::supports(codec_id)
        || stateful::supports(codec_id)
}

fn max_multibyte_sequence_length(codec_id: u32) -> usize {
    if let Some(index) = codec_index::mbcs_hot_family_index(codec_id) {
        return codec_index::MBCS_HOT_MAX_SEQUENCE_LENGTHS[index] as usize;
    }
    if let Some(index) = codec_index::mbcs_cold_family_index(codec_id) {
        return codec_index::MBCS_COLD_MAX_SEQUENCE_LENGTHS[index] as usize;
    }
    2
}

fn is_possibly_incomplete_reason(reason: &str) -> bool {
    let reason = reason.to_ascii_lowercase();
    reason.contains("incomplete")
        || reason.contains("odd byte length")
        || reason.contains("not divisible by 4")
        || reason.contains("unterminated")
        || reason.contains("partial character")
        || reason.contains("unexpected end")
}

fn encode_units_for_codec(codec_id: u32, error_mode: u32, units: &[u16]) -> NativeResult<Vec<u8>> {
    codecs::encode_from_utf16(codec_id, error_mode, units)
}

unsafe fn u16_units_from_raw<'a>(ptr: *const u16, len: usize) -> &'a [u16] {
    if len == 0 || ptr.is_null() {
        return &[];
    }
    unsafe { slice::from_raw_parts(ptr, len) }
}

fn utf16_units_to_bytes(units: &[u16]) -> Vec<u8> {
    let mut out = Vec::with_capacity(units.len() * 2);
    for unit in units {
        out.extend_from_slice(&unit.to_le_bytes());
    }
    out
}

fn bytes_to_utf16_units(bytes: &[u8]) -> NativeResult<Vec<u16>> {
    if !bytes.len().is_multiple_of(2) {
        return Err(err(
            0,
            "incremental encoder state payload was not aligned to UTF-16 units",
        ));
    }
    let mut units = Vec::with_capacity(bytes.len() / 2);
    for chunk in bytes.chunks_exact(2) {
        units.push(u16::from_le_bytes([chunk[0], chunk[1]]));
    }
    Ok(units)
}

fn is_high_surrogate(unit: u16) -> bool {
    (0xD800..=0xDBFF).contains(&unit)
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
    ])
}
