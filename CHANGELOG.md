## 0.1.1

- Corrected validation API documentation to match the `false` result for
  unknown or invalid input.
- Restored dependency resolution with Flutter 3.44 stable by using a compatible
  native build-hook dependency.

## 0.1.0

- Initial release.
- Added cross-platform encoding and decoding for 103 canonical codecs, including
  canonical-name and alias lookup.
- Added one-shot, asynchronous, validation, and bounded incremental APIs.
- Added strict, ignore, replace, backslash, XML character reference, Unicode
  name, and surrogate error modes where supported by the selected codec.
- Aligned malformed-input, UTF-7, byte-order-mark, and surrogate behavior with
  CPython, with the documented bounded incremental UTF-7 exception.
