// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:isolate';

const int _isolatePayloadThresholdBytes = 64 * 1024;

Future<T> runCodecAsync<T>(
  FutureOr<T> Function() computation, {
  int estimatedPayloadBytes = _isolatePayloadThresholdBytes,
}) {
  // 小歌词片段直接在当前 isolate 排队，避免大量短任务反复创建 isolate。
  if (estimatedPayloadBytes < _isolatePayloadThresholdBytes) {
    return Future<T>.sync(computation);
  }
  return Isolate.run<T>(computation);
}
