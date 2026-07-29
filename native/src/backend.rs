// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::slice;

use crate::codecs;
use crate::generated::codec_index;

pub(crate) const STATUS_OK: i32 = 0;
pub(crate) const STATUS_ERROR: i32 = 1;

#[repr(C)]
pub struct CodecResult {
    status: i32,
    data_ptr: *mut u8,
    data_len: usize,
    error_position: u32,
    error_message_ptr: *mut u8,
    error_message_len: usize,
}

#[derive(Clone, Debug)]
pub(crate) struct NativeError {
    pub(crate) position: u32,
    pub(crate) message: String,
}

pub(crate) type NativeResult<T> = Result<T, NativeError>;

#[unsafe(no_mangle)]
pub extern "C" fn charset_codec_backend_abi_version() -> u32 {
    codec_index::NATIVE_ABI_VERSION
}

#[unsafe(no_mangle)]
/// # Safety
/// When `length > 0`, `bytes` must point to at least `length` readable bytes
/// and remain valid for the duration of the call.
pub unsafe extern "C" fn charset_codec_decode_to_utf16le(
    codec_id: u32,
    error_mode: u32,
    bytes: *const u8,
    length: usize,
) -> *mut CodecResult {
    let input = unsafe { bytes_from_raw(bytes, length) };
    result_to_ptr(catch_native_result(|| {
        codecs::decode_to_utf16le(codec_id, error_mode, input)
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// When `length > 0`, `utf16_units` must be correctly aligned and point to at
/// least `length` readable `u16` values.
pub unsafe extern "C" fn charset_codec_encode_from_utf16(
    codec_id: u32,
    error_mode: u32,
    utf16_units: *const u16,
    length: usize,
) -> *mut CodecResult {
    let input = unsafe { u16_from_raw(utf16_units, length) };
    result_to_ptr(catch_native_result(|| {
        codecs::encode_from_utf16(codec_id, error_mode, input)
    }))
}

#[unsafe(no_mangle)]
/// # Safety
/// When `length > 0`, `bytes` must point to at least `length` readable bytes
/// and remain valid for the duration of the call.
pub unsafe extern "C" fn charset_codec_validate(
    codec_id: u32,
    bytes: *const u8,
    length: usize,
) -> u8 {
    let input = unsafe { bytes_from_raw(bytes, length) };
    u8::from(catch_native_bool(|| codecs::validate(codec_id, input)))
}

#[unsafe(no_mangle)]
/// # Safety
/// `result` must be null or an unreleased `CodecResult` returned by this
/// library. Each pointer may be released only once.
pub unsafe extern "C" fn charset_codec_free_result(result: *mut CodecResult) {
    if result.is_null() {
        return;
    }
    unsafe {
        let result = Box::from_raw(result);
        free_owned_bytes(result.data_ptr, result.data_len);
        free_owned_bytes(result.error_message_ptr, result.error_message_len);
    }
}

pub(crate) fn catch_native_result<T>(f: impl FnOnce() -> NativeResult<T>) -> NativeResult<T> {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| {
        // Generated data or native index corruption must return a diagnostic to
        // Dart instead of panicking across the FFI boundary.
        Err(err(
            0,
            "native charset backend failed while reading generated data",
        ))
    })
}

pub(crate) fn catch_native_bool(f: impl FnOnce() -> bool) -> bool {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(false)
}

pub(crate) fn err(position: u32, message: impl Into<String>) -> NativeError {
    NativeError {
        position,
        message: message.into(),
    }
}

pub(crate) unsafe fn bytes_from_raw<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if len == 0 || ptr.is_null() {
        return &[];
    }
    unsafe { slice::from_raw_parts(ptr, len) }
}

pub(crate) unsafe fn u16_from_raw<'a>(ptr: *const u16, len: usize) -> &'a [u16] {
    if len == 0 || ptr.is_null() {
        return &[];
    }
    unsafe { slice::from_raw_parts(ptr, len) }
}

pub(crate) fn result_to_ptr(result: NativeResult<Vec<u8>>) -> *mut CodecResult {
    let boxed = match result {
        Ok(data) => {
            let len = data.len();
            Box::new(CodecResult {
                status: STATUS_OK,
                data_ptr: into_owned_bytes(data),
                data_len: len,
                error_position: 0,
                error_message_ptr: std::ptr::null_mut(),
                error_message_len: 0,
            })
        }
        Err(error) => {
            let error_bytes = error.message.into_bytes();
            let error_len = error_bytes.len();
            Box::new(CodecResult {
                status: STATUS_ERROR,
                data_ptr: std::ptr::null_mut(),
                data_len: 0,
                error_position: error.position,
                error_message_ptr: into_owned_bytes(error_bytes),
                error_message_len: error_len,
            })
        }
    };
    Box::into_raw(boxed)
}

pub(crate) fn into_owned_bytes(data: Vec<u8>) -> *mut u8 {
    if data.is_empty() {
        return std::ptr::null_mut();
    }
    let mut boxed = data.into_boxed_slice();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    ptr
}

pub(crate) unsafe fn free_owned_bytes(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    let raw = std::ptr::slice_from_raw_parts_mut(ptr, len);
    unsafe {
        drop(Box::<[u8]>::from_raw(raw));
    }
}
