# charset_codec

[English](README.md) | [简体中文](README_zh.md)

面向 Dart 和 Flutter 的跨平台字符编码编解码库，行为对齐 CPython 的编解码
栈。

## 功能

- 支持 CPython 暴露的大量字符编码。
- 支持 canonical name 和常见别名，例如 `utf8`、`gbk`、`shift_jis`。
- 在对应编码支持的范围内提供 strict、replace、ignore、backslash、XML 字符
  引用、name 和 surrogate 错误模式。
- 为大输入提供异步 API，为分块输入提供有界增量解码器和编码器。
- Dart VM、Flutter 桌面/移动端与 Web 使用一致的公共 API。

## 安装

```bash
dart pub add charset_codec
```

## 快速开始

```dart
import 'package:charset_codec/charset_codec.dart';

void main() {
  final text = decodeBytes(
    [0xE4, 0xB8, 0xAD],
    encoding: 'utf-8',
  );
  print(text); // 中

  final bytes = encodeString('A中B', encoding: 'gb18030');
  print(bytes); // [65, 214, 208, 66]

  final maybeText = tryDecodeBytes([0xFF], encoding: 'utf-8');
  print(maybeText); // null
}
```

## 增量处理

当输入以分块形式到达时，可以使用增量解码器或编码器。流结束时调用
`close()`，以便按照所选错误模式处理不完整输入。

```dart
import 'package:charset_codec/charset_codec.dart';

void main() {
  final decoder = codec('gb18030').newDecoder();
  final first = decoder.feed([0xD6], finalChunk: false);
  final second = decoder.feed([0xD0], finalChunk: true);
  print(first + second);
}
```

增量状态有固定上限，可以使用 `getState` 和 `setState` 重置或转移状态。
UTF-7 的 one-shot 错误处理与 CPython 对齐。对于增量 UTF-7 的
`backslashreplace`，发生延迟 padding 错误时不会重放已经输出的文本，只转义
当前致错字节，从而保持内存有界。

## 公共 API

- `codec(String encoding)`：通过 canonical name 或别名获取编解码器。
- `decodeBytes(...)` 和 `encodeString(...)`：默认使用 strict 模式的一次性操作。
- `tryDecodeBytes(...)` 和 `tryEncodeString(...)`：失败时返回 `null`。
- `decodeBytesAsync(...)`、`encodeStringAsync(...)` 和
  `isValidDataForEncodingAsync(...)`：适合较大输入的异步辅助 API。
- `isValidDataForEncoding(...)`：校验字节数据而不返回解码文本。
- `CodecErrorMode`、`CodecException`、`CharsetCodec`、`IncrementalDecoder` 和
  `IncrementalEncoder`：用于自定义流程的公共类型。
- `lookupCodecInfo(...)` 和 `supportedPythonCodecNames`：查看支持的编码名称。

## 兼容性

本包对齐 CPython 可观察到的别名、非法输入、错误模式和代理项行为。未知编码
名称或 strict 转换失败时会抛出 `CodecException`，其中包含编码、操作和字节或
字符位置。

## 相关包

如果需要的是字符集检测，而不是直接编解码，请参阅
[`charset_normalizer_dart`](https://pub.dev/packages/charset_normalizer_dart)。

## 许可证

本包使用 `LICENSE` 中的许可证。源自 CPython 的元数据及其他第三方材料见
`THIRD_PARTY_NOTICES.md`。
