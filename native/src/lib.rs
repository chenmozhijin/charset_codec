// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

#[path = "../generated/mod.rs"]
mod generated;

mod backend;
mod codecs;
mod incremental;

pub use backend::{
    charset_codec_backend_abi_version, charset_codec_decode_to_utf16le,
    charset_codec_encode_from_utf16, charset_codec_free_result, charset_codec_validate,
};
pub use incremental::{
    charset_codec_incremental_decoder_close, charset_codec_incremental_decoder_create,
    charset_codec_incremental_decoder_feed, charset_codec_incremental_encoder_close,
    charset_codec_incremental_encoder_create, charset_codec_incremental_encoder_feed_utf16,
    charset_codec_incremental_session_destroy, charset_codec_incremental_session_get_state,
    charset_codec_incremental_session_reset, charset_codec_incremental_session_set_state,
};
