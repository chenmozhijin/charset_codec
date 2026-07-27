## 0.1.0

- Initial release.
- Added Dart/Web fallback codecs and a Rust native-hybrid backend aligned with CPython behavior.
- Support decoding, encoding with various error modes (`strict`, `replace`, `ignore`).
- Provided a rich set of top-level API functions: `codec`, `decodeBytes`, `tryDecodeBytes`, `encodeString`, `tryEncodeString`, `isValidDataForEncoding`.
- Kept codec tables demand-loaded instead of exposing backend-dependent preload controls.
- Added strict one-shot Rust routes for all 103 canonical codecs, including UTF-7.
- Upgraded the native bridge to ABI 3 with UTF-16 input and UTF-16LE output so UTF-7 preserves lone surrogate code units.
- Replaced stateful incremental whole-buffer replay with bounded HZ, ISO-2022, GB18030, and UTF-7 streaming state; native session snapshots remain at most 41 bytes for decoders and 35 bytes for encoders.
- Documented the bounded UTF-7 incremental `backslashreplace` behavior instead of inheriting CPython's unbounded full-shift replay.
- Added bounded native blob parsing, generated route validation, reproducible rustfmt-before-hash generation, and independent CI/pub.dev workflows.
