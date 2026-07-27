// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:async';

Future<T> runCodecAsync<T>(
  FutureOr<T> Function() computation, {
  int estimatedPayloadBytes = 0,
}) {
  return Future<T>.sync(computation);
}
