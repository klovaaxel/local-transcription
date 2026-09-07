import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Device capability probes that need no model download and no process
/// spawning — they run identically on every platform and cost under a
/// second, so the app can benchmark on first launch and after an update.
abstract final class DeviceBench {
  /// SHA-256 throughput in MB/s over [duration], measured in a background
  /// isolate. Pure Dart, memory-light: the score tracks CPU throughput,
  /// which is what the CPU-only paths (phone ASR, non-GPU llama) ride on.
  ///
  /// A GPU would carry the 7B anyway, so a weak score only downgrades the
  /// auto model pick — a manual pick always wins (see [AppSettings]).
  static Future<double> cpuScoreMbs({
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    return Isolate.run(() => _hashThroughput(duration));
  }
}

double _hashThroughput(Duration duration) {
  final block = Uint8List(64 * 1024);
  for (var i = 0; i < block.length; i++) {
    block[i] = i & 0xff;
  }
  final started = DateTime.now();
  var bytes = 0;
  var sink = 0;
  final deadline = started.add(duration);
  while (DateTime.now().isBefore(deadline)) {
    sink += sha256.convert(block).bytes[0];
    bytes += block.length;
  }
  // Keep the loop's work observable.
  if (sink < 0) {
    throw StateError('unreachable');
  }
  final seconds = DateTime.now().difference(started).inMicroseconds / 1e6;
  if (seconds <= 0) {
    return 0;
  }
  return bytes / 1e6 / seconds;
}

/// The calibration scale is anchored in real measurements: a known-good
/// desktop (runs the 7B brief, kb-whisper-medium ASR) measures ~112 MB/s
/// pure-Dart sha256. Below [cpuWeakMbs] the CPU alone would make the 7B
/// brief (CPU-only fallback) and medium ASR painful, so the auto pick steps
/// down a tier.
const cpuWeakMbs = 40.0;

String describeCpuScore(double mbs) {
  return '${mbs.toStringAsFixed(0)} MB/s';
}
