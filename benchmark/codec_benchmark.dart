// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_codec/src/codec/backend.dart';
import 'package:charset_codec/src/codec/data_loader.dart';
import 'package:charset_codec/src/generated/codec_mbcs_data.g.dart';

typedef BenchBody = void Function();

void main(List<String> args) {
  if (args.contains('--rss-probe-child')) {
    _runColdRssProbeChild();
    return;
  }
  final int statefulProbeIndex = args.indexOf('--stateful-rss-probe-child');
  if (statefulProbeIndex >= 0) {
    _runStatefulRssProbeChild(args[statefulProbeIndex + 1]);
    return;
  }
  final int warmupIters = _readIntArg(args, '--warmup', fallback: 200);
  final int measureIters = _readIntArg(args, '--iters', fallback: 2000);
  final int rssSamples = _readIntArg(args, '--rss-samples', fallback: 5);
  final String? baselinePath = _readStringArg(args, '--compare-baseline');
  final String? outputPath = _readStringArg(args, '--output');
  final double regressionThreshold = _readDoubleArg(
    args,
    '--regression-threshold',
    fallback: 0.25,
  );
  // Windows locks loaded DLLs, so the cold-start child process must begin before
  // the parent first touches native FFI.
  final Map<String, Object> memoryProbe = <String, Object>{
    'cold_decode': _coldDecodeRssProbe(rssSamples),
    'stateful_incremental': _statefulIncrementalRssProbe(),
  };

  final String asciiText = 'Hello, codec benchmark! ' * 32;
  final List<int> asciiBytes = asciiText.codeUnits;
  final String utf8Text = 'Dart编解码🙂' * 64;
  final List<int> utf8Bytes = encodeString(utf8Text, encoding: 'utf-8');
  final String utf16Text = 'UTF16-示例🙂' * 64;
  final List<int> utf16Bytes = encodeString(utf16Text, encoding: 'utf-16');
  final List<int> gbkSample = generatedMbcsSampleMultibyteBytesByCodec['gbk']!;
  final int gbkScalar = generatedMbcsSampleMultibyteScalarByCodec['gbk']!;
  final String gbkText = String.fromCharCode(gbkScalar) * 256;
  final List<int> gbkBytes = _repeatBytes(gbkSample, 256);
  final List<int> cp950Sample =
      generatedMbcsSampleMultibyteBytesByCodec['cp950']!;
  final int cp950Scalar = generatedMbcsSampleMultibyteScalarByCodec['cp950']!;
  final String cp950Text = String.fromCharCode(cp950Scalar) * 256;
  final List<int> cp950Bytes = _repeatBytes(cp950Sample, 256);
  final List<int> eucJpSample =
      generatedMbcsSampleMultibyteBytesByCodec['euc-jp']!;
  final int eucJpScalar = generatedMbcsSampleMultibyteScalarByCodec['euc-jp']!;
  final String eucJpText = String.fromCharCode(eucJpScalar) * 256;
  final List<int> eucJpBytes = _repeatBytes(eucJpSample, 256);
  final String gb18030Text = '😀编解码' * 128;
  final List<int> gb18030Bytes = encodeString(gb18030Text, encoding: 'gb18030');
  final String hzText = String.fromCharCode(0x554A) * 256;
  final List<int> hzBytes = encodeString(hzText, encoding: 'hz-gb-2312');
  final String iso2022JpText = String.fromCharCode(0x3042) * 256;
  final List<int> iso2022JpBytes = encodeString(
    iso2022JpText,
    encoding: 'iso-2022-jp',
  );
  final String iso2022KrText = String.fromCharCode(0xAC00) * 256;
  final List<int> iso2022KrBytes = encodeString(
    iso2022KrText,
    encoding: 'iso-2022-kr',
  );
  final String utf7Text = 'A≢Α.' * 128;
  final List<int> utf7Bytes = encodeString(utf7Text, encoding: 'utf-7');

  final List<int> cp932Sample =
      generatedMbcsSampleMultibyteBytesByCodec['cp932']!;
  final int cp932Scalar = generatedMbcsSampleMultibyteScalarByCodec['cp932']!;
  final String cp932Text = String.fromCharCode(cp932Scalar) * 256;
  final List<int> cp932Bytes = _repeatBytes(cp932Sample, 256);
  final String macText = String.fromCharCode(0x00C4) * 256;
  final List<int> macBytes = _repeatBytes(const <int>[0x80], 256);

  final Map<String, Object> report = <String, Object>{
    'benchmark_schema_version': 2,
    'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
    'active_backend': activeCodecBackendName(),
    'dart_version': Platform.version,
    'rustc_version': _commandVersion('rustc', const <String>['--version']),
    'operating_system': Platform.operatingSystem,
    'cpu_model': _cpuModel(),
    'processor_count': Platform.numberOfProcessors,
    'asset_manifest_sha256': _sha256File('tool/generated/codec_manifest.json'),
    'native_manifest_sha256': _sha256File(
      'native/assets/generated/native_manifest.json',
    ),
    'warmup_iterations': warmupIters,
    'measure_iterations': measureIters,
    // A low iteration count only proves that the script and dependencies run; it
    // is not a representative performance baseline.
    'benchmark_profile': measureIters < 30 ? 'smoke' : 'measured',
    'benchmarks': <String, Object>{
      'cold_cp932_decode': _bench(warmupIters, measureIters, () {
        CodecDataLoader.resetCachesForTesting();
        decodeBytes(cp932Bytes, encoding: 'cp932');
      }),
      'alias_resolve_cp932': _bench(
        warmupIters,
        measureIters,
        () => codec('CP932'),
      ),
      'hot_ascii_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(asciiBytes, encoding: 'ascii'),
      ),
      'hot_ascii_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(asciiText, encoding: 'ascii'),
      ),
      'hot_utf8_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(utf8Bytes, encoding: 'utf-8'),
      ),
      'hot_utf8_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(utf8Text, encoding: 'utf-8'),
      ),
      'hot_utf16_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(utf16Bytes, encoding: 'utf-16'),
      ),
      'hot_utf16_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(utf16Text, encoding: 'utf-16'),
      ),
      'hot_gbk_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(gbkBytes, encoding: 'gbk'),
      ),
      'hot_gbk_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(gbkText, encoding: 'gbk'),
      ),
      'cold_cp950_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(cp950Bytes, encoding: 'cp950'),
      ),
      'cold_cp950_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(cp950Text, encoding: 'cp950'),
      ),
      'hot_euc_jp_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(eucJpBytes, encoding: 'euc-jp'),
      ),
      'hot_euc_jp_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(eucJpText, encoding: 'euc-jp'),
      ),
      'hot_gb18030_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(gb18030Bytes, encoding: 'gb18030'),
      ),
      'hot_gb18030_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(gb18030Text, encoding: 'gb18030'),
      ),
      'hot_hz_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(hzBytes, encoding: 'hz-gb-2312'),
      ),
      'hot_hz_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(hzText, encoding: 'hz-gb-2312'),
      ),
      'hot_iso2022jp_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(iso2022JpBytes, encoding: 'iso-2022-jp'),
      ),
      'hot_iso2022jp_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(iso2022JpText, encoding: 'iso-2022-jp'),
      ),
      'hot_iso2022kr_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(iso2022KrBytes, encoding: 'iso-2022-kr'),
      ),
      'hot_iso2022kr_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(iso2022KrText, encoding: 'iso-2022-kr'),
      ),
      'hot_cp932_decode': _bench(
        warmupIters,
        measureIters,
        () {
          decodeBytes(cp932Bytes, encoding: 'cp932');
        },
        setup: () {
          CodecDataLoader.resetCachesForTesting();
          decodeBytes(cp932Bytes, encoding: 'cp932');
        },
      ),
      'hot_cp932_encode': _bench(
        warmupIters,
        measureIters,
        () {
          encodeString(cp932Text, encoding: 'cp932');
        },
        setup: () {
          CodecDataLoader.resetCachesForTesting();
          encodeString(cp932Text, encoding: 'cp932');
        },
      ),
      'hot_mac_arabic_decode': _bench(
        warmupIters,
        measureIters,
        () => decodeBytes(macBytes, encoding: 'mac-arabic'),
      ),
      'hot_mac_romanian_encode': _bench(
        warmupIters,
        measureIters,
        () => encodeString(macText, encoding: 'mac-romanian'),
      ),
      'validate_utf8': _bench(
        warmupIters,
        measureIters,
        () => isValidDataForEncoding(utf8Bytes, 'utf-8'),
      ),
      'validate_cp932': _bench(
        warmupIters,
        measureIters,
        () => isValidDataForEncoding(cp932Bytes, 'cp932'),
        setup: () {
          CodecDataLoader.resetCachesForTesting();
          decodeBytes(cp932Bytes, encoding: 'cp932');
        },
      ),
      'incremental_cp932_decode': _bench(
        warmupIters,
        measureIters,
        () {
          final IncrementalDecoder decoder = codec('cp932').newDecoder();
          final int mid = cp932Bytes.length ~/ 2;
          decoder.feed(cp932Bytes.sublist(0, mid));
          decoder.feed(cp932Bytes.sublist(mid), finalChunk: true);
          decoder.close();
        },
        setup: () {
          CodecDataLoader.resetCachesForTesting();
          decodeBytes(cp932Bytes, encoding: 'cp932');
        },
      ),
      'incremental_cp932_encode': _bench(
        warmupIters,
        measureIters,
        () {
          final IncrementalEncoder encoder = codec('cp932').newEncoder();
          final int mid = max(1, cp932Text.length ~/ 2);
          encoder.feed(cp932Text.substring(0, mid));
          encoder.feed(cp932Text.substring(mid), finalChunk: true);
          encoder.close();
        },
        setup: () {
          CodecDataLoader.resetCachesForTesting();
          encodeString(cp932Text, encoding: 'cp932');
        },
      ),
      'incremental_gb18030_decode': _bench(
        warmupIters,
        measureIters,
        () {
          final IncrementalDecoder decoder = codec('gb18030').newDecoder();
          final int cut = gb18030Bytes.length ~/ 2;
          decoder.feed(gb18030Bytes.sublist(0, cut));
          decoder.feed(gb18030Bytes.sublist(cut), finalChunk: true);
          decoder.close();
        },
        setup: () {
          CodecDataLoader.resetCachesForTesting();
          decodeBytes(gb18030Bytes, encoding: 'gb18030');
        },
      ),
      'incremental_gb18030_encode': _bench(
        warmupIters,
        measureIters,
        () {
          final IncrementalEncoder encoder = codec('gb18030').newEncoder();
          final int cut = max(1, gb18030Text.length ~/ 2);
          encoder.feed(gb18030Text.substring(0, cut));
          encoder.feed(gb18030Text.substring(cut), finalChunk: true);
          encoder.close();
        },
        setup: () {
          CodecDataLoader.resetCachesForTesting();
          encodeString(gb18030Text, encoding: 'gb18030');
        },
      ),
      'incremental_hz_decode': _incrementalDecodeBench(
        'hz-gb-2312',
        hzBytes,
        warmupIters,
        measureIters,
      ),
      'incremental_hz_encode': _incrementalEncodeBench(
        'hz-gb-2312',
        hzText,
        warmupIters,
        measureIters,
      ),
      'incremental_iso2022jp_decode': _incrementalDecodeBench(
        'iso-2022-jp',
        iso2022JpBytes,
        warmupIters,
        measureIters,
      ),
      'incremental_iso2022jp_encode': _incrementalEncodeBench(
        'iso-2022-jp',
        iso2022JpText,
        warmupIters,
        measureIters,
      ),
      'incremental_iso2022kr_decode': _incrementalDecodeBench(
        'iso-2022-kr',
        iso2022KrBytes,
        warmupIters,
        measureIters,
      ),
      'incremental_iso2022kr_encode': _incrementalEncodeBench(
        'iso-2022-kr',
        iso2022KrText,
        warmupIters,
        measureIters,
      ),
      'incremental_utf7_decode': _incrementalDecodeBench(
        'utf-7',
        utf7Bytes,
        warmupIters,
        measureIters,
      ),
      'incremental_utf7_encode': _incrementalEncodeBench(
        'utf-7',
        utf7Text,
        warmupIters,
        measureIters,
      ),
    },
    'memory_probe': memoryProbe,
  };

  const JsonEncoder pretty = JsonEncoder.withIndent('  ');
  final String encodedReport = pretty.convert(report);
  // ignore: avoid_print
  print(encodedReport);
  if (outputPath != null) {
    final File output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$encodedReport\n');
  }

  if (baselinePath != null) {
    final List<String> regressions = _compareWithBaseline(
      report,
      File(baselinePath),
      regressionThreshold,
    );
    if (regressions.isNotEmpty) {
      stderr.writeln('Benchmark regression threshold exceeded:');
      for (final String item in regressions) {
        stderr.writeln('  - $item');
      }
      exitCode = 1;
    }
  }
}

String? _readStringArg(List<String> args, String key) {
  final int idx = args.indexOf(key);
  if (idx < 0 || idx + 1 >= args.length) {
    return null;
  }
  final String value = args[idx + 1].trim();
  return value.isEmpty ? null : value;
}

double _readDoubleArg(
  List<String> args,
  String key, {
  required double fallback,
}) {
  final int idx = args.indexOf(key);
  if (idx < 0 || idx + 1 >= args.length) {
    return fallback;
  }
  final double? parsed = double.tryParse(args[idx + 1]);
  if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
    return fallback;
  }
  return parsed;
}

List<String> _compareWithBaseline(
  Map<String, Object> report,
  File baselineFile,
  double threshold,
) {
  if (!baselineFile.existsSync()) {
    return <String>['baseline file does not exist: ${baselineFile.path}'];
  }
  final Object? decoded = jsonDecode(baselineFile.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    return <String>['baseline file is not a JSON object: ${baselineFile.path}'];
  }
  final Object? currentBenchmarks = report['benchmarks'];
  final Object? baselineBenchmarks = decoded['benchmarks'];
  if (currentBenchmarks is! Map<String, Object?> ||
      baselineBenchmarks is! Map<String, Object?>) {
    return <String>['baseline/current benchmarks section is missing'];
  }

  final List<String> failures = <String>[];
  for (final MapEntry<String, Object?> entry in baselineBenchmarks.entries) {
    final Object? currentRaw = currentBenchmarks[entry.key];
    final Object? baselineRaw = entry.value;
    if (currentRaw is! Map<String, Object?> ||
        baselineRaw is! Map<String, Object?>) {
      continue;
    }
    final num? baselineAvg = baselineRaw['avg_us_per_op'] as num?;
    final num? currentAvg = currentRaw['avg_us_per_op'] as num?;
    if (baselineAvg == null || currentAvg == null || baselineAvg <= 0) {
      continue;
    }
    final double allowed = baselineAvg.toDouble() * (1 + threshold);
    if (currentAvg > allowed) {
      failures.add(
        '${entry.key}: current=${currentAvg.toStringAsFixed(3)}us '
        'baseline=${baselineAvg.toStringAsFixed(3)}us '
        'threshold=${(threshold * 100).toStringAsFixed(1)}%',
      );
    }
  }
  return failures;
}

Map<String, Object> _bench(
  int warmup,
  int iters,
  BenchBody body, {
  void Function()? setup,
}) {
  setup?.call();
  for (int i = 0; i < warmup; i++) {
    body();
  }

  final List<int> samplesUs = <int>[];
  final Stopwatch total = Stopwatch()..start();
  for (int i = 0; i < iters; i++) {
    final Stopwatch one = Stopwatch()..start();
    body();
    one.stop();
    samplesUs.add(one.elapsedMicroseconds);
  }
  total.stop();

  samplesUs.sort();
  final double avgUs = samplesUs.reduce((int a, int b) => a + b) / iters;
  final double variance =
      samplesUs
          .map((int value) => pow(value - avgUs, 2).toDouble())
          .reduce((double a, double b) => a + b) /
      iters;
  final double opsPerSec = avgUs == 0 ? double.infinity : 1000000.0 / avgUs;
  return <String, Object>{
    'elapsed_us_total': total.elapsedMicroseconds,
    'avg_us_per_op': avgUs,
    'min_us_per_op': samplesUs.first,
    'median_us_per_op': _percentile(samplesUs, 0.5),
    'p95_us_per_op': _percentile(samplesUs, 0.95),
    'max_us_per_op': samplesUs.last,
    'stddev_us_per_op': sqrt(variance),
    'ops_per_sec': opsPerSec,
    'sample_count': samplesUs.length,
  };
}

Map<String, Object> _incrementalDecodeBench(
  String encoding,
  List<int> bytes,
  int warmup,
  int iterations,
) {
  return _bench(warmup, iterations, () {
    final IncrementalDecoder decoder = codec(encoding).newDecoder();
    final int chunkSize = max(1, bytes.length ~/ 4);
    for (int offset = 0; offset < bytes.length; offset += chunkSize) {
      final int end = min(bytes.length, offset + chunkSize);
      decoder.feed(bytes.sublist(offset, end), finalChunk: end == bytes.length);
    }
    decoder.close();
  });
}

Map<String, Object> _incrementalEncodeBench(
  String encoding,
  String text,
  int warmup,
  int iterations,
) {
  return _bench(warmup, iterations, () {
    final IncrementalEncoder encoder = codec(encoding).newEncoder();
    final int chunkSize = max(1, text.length ~/ 4);
    for (int offset = 0; offset < text.length; offset += chunkSize) {
      final int end = min(text.length, offset + chunkSize);
      encoder.feed(text.substring(offset, end), finalChunk: end == text.length);
    }
    encoder.close();
  });
}

int _readIntArg(List<String> args, String key, {required int fallback}) {
  final int idx = args.indexOf(key);
  if (idx < 0 || idx + 1 >= args.length) {
    return fallback;
  }
  return int.tryParse(args[idx + 1]) ?? fallback;
}

void _runColdRssProbeChild() {
  final List<int> sample = generatedMbcsSampleMultibyteBytesByCodec['cp932']!;
  final List<int> sampleBytes = _repeatBytes(sample, 256);
  final int before = ProcessInfo.currentRss;
  decodeBytes(sampleBytes, encoding: 'cp932');
  final int after = ProcessInfo.currentRss;
  // The child process emits one JSON line, so the parent can ignore other build
  // hook logs and parse the final line deterministically.
  // ignore: avoid_print
  print(jsonEncode(<String, int>{'before': before, 'after': after}));
}

void _runStatefulRssProbeChild(String encoding) {
  final String sample = switch (encoding) {
    'hz-gb-2312' => '中文A',
    'iso-2022-kr' => '한글A',
    'iso-2022-jp' => '日本語A',
    'utf-7' => 'A≢Α.',
    _ => throw ArgumentError.value(encoding, 'encoding'),
  };
  final IncrementalEncoder encoder = codec(encoding).newEncoder();
  final IncrementalDecoder decoder = codec(encoding).newDecoder();
  for (int i = 0; i < 1000; i++) {
    decoder.feed(encoder.feed(sample));
  }
  final int before = ProcessInfo.currentRss;
  final Stopwatch stopwatch = Stopwatch()..start();
  for (int i = 0; i < 20000; i++) {
    decoder.feed(encoder.feed(sample));
  }
  stopwatch.stop();
  final int after = ProcessInfo.currentRss;
  // ignore: avoid_print
  print(
    jsonEncode(<String, Object>{
      'encoding': encoding,
      'iterations': 20000,
      'elapsed_us': stopwatch.elapsedMicroseconds,
      'rss_before_bytes': before,
      'rss_after_bytes': after,
      'rss_delta_bytes': after - before,
    }),
  );
}

Map<String, Object> _statefulIncrementalRssProbe() {
  final Map<String, Object> results = <String, Object>{};
  for (final String encoding in const <String>[
    'hz-gb-2312',
    'iso-2022-kr',
    'iso-2022-jp',
    'utf-7',
  ]) {
    final List<String> childArguments = <String>[
      'run',
      'benchmark/codec_benchmark.dart',
      '--stateful-rss-probe-child',
      encoding,
    ];
    final ProcessResult result = Process.runSync(
      Platform.resolvedExecutable,
      childArguments,
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'stateful RSS probe child failed for $encoding: ${result.stderr}',
      );
    }
    final String jsonLine = result.stdout
        .toString()
        .trim()
        .split('\n')
        .lastWhere((String line) => line.trimLeft().startsWith('{'));
    results[encoding] = jsonDecode(jsonLine) as Map<String, Object?>;
  }
  return results;
}

Map<String, Object> _coldDecodeRssProbe(int sampleCount) {
  final List<int> deltas = <int>[];
  final List<int> beforeValues = <int>[];
  final List<int> afterValues = <int>[];
  for (int index = 0; index < max(1, sampleCount); index++) {
    final ProcessResult result = Process.runSync(
      Platform.resolvedExecutable,
      const <String>[
        'run',
        'benchmark/codec_benchmark.dart',
        '--rss-probe-child',
      ],
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode != 0) {
      throw StateError('cold RSS probe child failed: ${result.stderr}');
    }
    final List<String> lines = result.stdout.toString().trim().split('\n');
    final String jsonLine = lines.lastWhere(
      (String line) => line.trimLeft().startsWith('{'),
    );
    final Map<String, Object?> decoded =
        jsonDecode(jsonLine) as Map<String, Object?>;
    final int before = decoded['before']! as int;
    final int after = decoded['after']! as int;
    beforeValues.add(before);
    afterValues.add(after);
    deltas.add(after - before);
  }
  deltas.sort();
  return <String, Object>{
    'probe': 'fresh_process_first_cp932_decode',
    'sample_count': deltas.length,
    'rss_before_bytes': beforeValues,
    'rss_after_bytes': afterValues,
    'rss_delta_bytes': deltas,
    'rss_delta_median_bytes': _percentile(deltas, 0.5),
    'rss_delta_p95_bytes': _percentile(deltas, 0.95),
  };
}

List<int> _repeatBytes(List<int> sample, int count) {
  final List<int> out = <int>[];
  for (int i = 0; i < count; i++) {
    out.addAll(sample);
  }
  return out;
}

double _percentile(List<int> sortedSamples, double percentile) {
  if (sortedSamples.isEmpty) {
    return 0;
  }
  final int index = ((sortedSamples.length - 1) * percentile).round();
  return sortedSamples[index].toDouble();
}

String _sha256File(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return 'missing';
  }
  return crypto.sha256.convert(file.readAsBytesSync()).toString();
}

String _commandVersion(String executable, List<String> arguments) {
  final ProcessResult result = Process.runSync(executable, arguments);
  if (result.exitCode != 0) {
    return 'unavailable';
  }
  return result.stdout.toString().trim();
}

String _cpuModel() {
  final String? windowsIdentifier =
      Platform.environment['PROCESSOR_IDENTIFIER'];
  if (windowsIdentifier != null && windowsIdentifier.trim().isNotEmpty) {
    return windowsIdentifier.trim();
  }
  if (Platform.isLinux) {
    final File cpuInfo = File('/proc/cpuinfo');
    if (cpuInfo.existsSync()) {
      for (final String line in cpuInfo.readAsLinesSync()) {
        if (line.toLowerCase().startsWith('model name')) {
          return line.split(':').last.trim();
        }
      }
    }
  }
  if (Platform.isMacOS) {
    return _commandVersion('sysctl', const <String>[
      '-n',
      'machdep.cpu.brand_string',
    ]);
  }
  return 'unknown';
}
