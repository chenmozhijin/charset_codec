# Third-Party Notices

`charset_codec` is an independent Dart codec library aligned with CPython codec
behavior.

## Project code

- The Dart runtime and package code in this repository are original project
  code.
- License: MIT
- License file: `LICENSE`

## CPython-sourced material

- Upstream: <https://github.com/python/cpython>
- Role: upstream source for alias metadata and codec behavior reference
- Upstream license: Python Software Foundation License Version 2 (PSF-2.0)
- Local license copy: `licenses/PSF-2.0.txt`
- Upstream license file: <https://github.com/python/cpython/blob/main/LICENSE>
- Upstream source used in vendored form: `Lib/encodings/aliases.py`
- Additional use during development:
  - selected CPython codec source files, including material under
    `Modules/cjkcodecs`, were consulted as implementation reference while
    developing the original Dart runtime behavior
- Material used in this repository:
  - `tool/vendor/cpython_aliases.json` is a vendored snapshot derived from
    `Lib/encodings/aliases.py`.
- Summary of project-side changes and use:
  - alias metadata is redistributed as a normalized JSON snapshot instead of
    the original Python source module
  - generated codec assets are produced from project metadata, CPython-derived
    alias data, and observed Python `codecs` behavior
  - the Dart runtime is maintained as an original implementation, with selected
    CPython codec source files consulted as reference in some areas

## Generated compatibility data

- `tool/export_codec_data.py` combines:
  - the project-maintained codec catalog `tool/vendor/codec_catalog.json`
  - vendored CPython alias metadata from `tool/vendor/cpython_aliases.json` or
    an external CPython checkout
  - observable behavior from Python's standard `codecs` module
- Generated outputs include:
  - `lib/src/generated/*.g.dart`
  - `tool/generated/codec_manifest.json`
- These outputs are generated compatibility assets derived from upstream
  behavior and reference metadata. They are not a verbatim copy of CPython
  runtime source files.

## Project-maintained catalog

- `tool/vendor/codec_catalog.json` is maintained in this project as the
  canonical codec catalog used by the exporter.
- It is not represented here as a copied CPython source file.

## Test fixture sources (test-only, optional download)

These sources are used only when preparing local fixtures for full regression
tests and are not shipped as runtime package assets.

- pythontestdotnet archive:
  - Source URL is pinned in `tool/fixtures.lock.json` under `sources.pythontestdotnet`.
  - Usage: unicode code map raw files used to generate
    `test/.fixtures/codecmaps/parsed/map_cases.jsonl`.

## Scope of third-party terms

- Third-party license terms remain applicable to the corresponding upstream
  material and generated compatibility data.
- Reference use of CPython source files during implementation review does not
  change the fact that this repository's runtime code is maintained as original
  Dart code.
- Those third-party terms do not replace the MIT license for this project's
  original Dart code.
