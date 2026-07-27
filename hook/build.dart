// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'build_support.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    await runCharsetCodecNativeBuild(input, output);
  });
}
