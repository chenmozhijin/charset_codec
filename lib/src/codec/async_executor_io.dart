// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:isolate';

const int _isolatePayloadThresholdBytes = 64 * 1024;

Future<T> runCodecAsync<T>(
  FutureOr<T> Function() computation, {
  int estimatedPayloadBytes = _isolatePayloadThresholdBytes,
}) {
  // Queue small inputs on the current isolate to avoid repeatedly creating
  // isolates for short tasks.
  if (estimatedPayloadBytes < _isolatePayloadThresholdBytes) {
    return Future<T>.sync(computation);
  }
  return Isolate.run<T>(computation);
}
