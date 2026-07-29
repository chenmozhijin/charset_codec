// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

use crate::backend::{NativeResult, err};

// Generated tables are package assets but must still be parsed as untrusted
// input: truncation or version mismatches must not terminate the host process
// through an out-of-bounds index.
pub(super) struct BlobReader<'a> {
    bytes: &'a [u8],
    cursor: usize,
    context: &'static str,
}

impl<'a> BlobReader<'a> {
    pub(super) fn new(bytes: &'a [u8], context: &'static str) -> Self {
        Self {
            bytes,
            cursor: 0,
            context,
        }
    }

    pub(super) fn read_u16(&mut self) -> NativeResult<u16> {
        let bytes = self.read_bytes(2)?;
        Ok(u16::from_le_bytes([bytes[0], bytes[1]]))
    }

    pub(super) fn read_u32(&mut self) -> NativeResult<u32> {
        let bytes = self.read_bytes(4)?;
        Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    pub(super) fn read_u32_vec(&mut self, count: usize) -> NativeResult<Vec<u32>> {
        self.ensure_item_bytes(count, 4)?;
        let mut values = Vec::with_capacity(count);
        for _ in 0..count {
            values.push(self.read_u32()?);
        }
        Ok(values)
    }

    pub(super) fn read_bytes(&mut self, length: usize) -> NativeResult<&'a [u8]> {
        let end = self
            .cursor
            .checked_add(length)
            .ok_or_else(|| self.corrupt("byte range overflow"))?;
        let bytes = self
            .bytes
            .get(self.cursor..end)
            .ok_or_else(|| self.corrupt("truncated data"))?;
        self.cursor = end;
        Ok(bytes)
    }

    pub(super) fn read_utf8_string(&mut self, length: usize) -> NativeResult<String> {
        let bytes = self.read_bytes(length)?;
        std::str::from_utf8(bytes)
            .map(str::to_owned)
            .map_err(|_| self.corrupt("invalid UTF-8 side mapping"))
    }

    pub(super) fn finish(self) -> NativeResult<()> {
        if self.cursor == self.bytes.len() {
            return Ok(());
        }
        Err(self.corrupt("unexpected trailing data"))
    }

    fn ensure_item_bytes(&self, count: usize, width: usize) -> NativeResult<()> {
        let length = count
            .checked_mul(width)
            .ok_or_else(|| self.corrupt("item count overflow"))?;
        let end = self
            .cursor
            .checked_add(length)
            .ok_or_else(|| self.corrupt("byte range overflow"))?;
        if end <= self.bytes.len() {
            return Ok(());
        }
        Err(self.corrupt("truncated item array"))
    }

    fn corrupt(&self, reason: &str) -> crate::backend::NativeError {
        err(
            0,
            format!(
                "corrupt {} at byte {}: {}",
                self.context, self.cursor, reason
            ),
        )
    }
}

pub(super) fn checked_slice<'a>(
    blob: &'a [u8],
    offset: usize,
    length: usize,
    context: &'static str,
) -> NativeResult<&'a [u8]> {
    let end = offset
        .checked_add(length)
        .ok_or_else(|| err(0, format!("corrupt {context}: byte range overflow")))?;
    blob.get(offset..end)
        .ok_or_else(|| err(0, format!("corrupt {context}: table range is truncated")))
}

#[cfg(test)]
mod tests {
    use super::{BlobReader, checked_slice};

    #[test]
    fn truncated_integer_returns_native_error() {
        let mut reader = BlobReader::new(&[0x01, 0x02, 0x03], "test table");
        let result = reader.read_u32();
        assert!(matches!(
            result,
            Err(ref error) if error.message.contains("truncated")
        ));
    }

    #[test]
    fn invalid_utf8_returns_native_error() {
        let mut reader = BlobReader::new(&[0xFF], "test table");
        let result = reader.read_utf8_string(1);
        assert!(matches!(
            result,
            Err(ref error) if error.message.contains("invalid UTF-8")
        ));
    }

    #[test]
    fn overflowing_slice_range_returns_native_error() {
        let result = checked_slice(&[0x01], usize::MAX, 2, "test table");
        assert!(matches!(
            result,
            Err(ref error) if error.message.contains("overflow")
        ));
    }

    #[test]
    fn trailing_bytes_are_rejected() {
        let reader = BlobReader::new(&[0x01], "test table");
        let result = reader.finish();
        assert!(matches!(
            result,
            Err(ref error) if error.message.contains("trailing")
        ));
    }
}
