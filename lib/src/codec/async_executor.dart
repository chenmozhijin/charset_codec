// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'async_executor_stub.dart'
    if (dart.library.io) 'async_executor_io.dart'
    as impl;

Future<T> runCodecAsync<T>(
  FutureOr<T> Function() computation, {
  int estimatedPayloadBytes = 64 * 1024,
}) {
  return impl.runCodecAsync(
    computation,
    estimatedPayloadBytes: estimatedPayloadBytes,
  );
}
