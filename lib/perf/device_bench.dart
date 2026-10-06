import 'dart:io';
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
  /// A GPU would carry the large brief anyway, so a weak score only
  /// downgrades the auto model pick — a manual pick always wins (see
  /// [AppSettings]).
  static Future<double> cpuScoreMbs({
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    return Isolate.run(() => _hashThroughput(duration));
  }

  /// Installed RAM in megabytes, or the tighter cgroup limit when the
  /// process is capped below that (a Waydroid container often is). Null on
  /// Windows and iOS, and when the files cannot be read — the auto pick
  /// then keeps the platform default.
  static int? ramTotalMb() {
    if (!Platform.isLinux && !Platform.isAndroid) {
      return null;
    }
    int? best;
    void take(int? value) {
      if (value == null || value <= 0) {
        return;
      }
      best = best == null || value < best! ? value : best;
    }

    try {
      take(meminfoTotalMb(File('/proc/meminfo').readAsStringSync()));
    } catch (_) {}
    for (final path in const [
      '/sys/fs/cgroup/memory.max',
      '/sys/fs/cgroup/memory/memory.limit_in_bytes',
    ]) {
      try {
        take(cgroupMemoryLimitMb(File(path).readAsStringSync()));
      } catch (_) {}
    }
    return best;
  }
}

/// `MemTotal` from `/proc/meminfo`, in megabytes.
int? meminfoTotalMb(String text) {
  final match = RegExp(
    r'^MemTotal:\s+(\d+)\s+kB',
    multiLine: true,
  ).firstMatch(text);
  if (match == null) {
    return null;
  }
  return int.parse(match.group(1)!) ~/ 1024;
}

/// A cgroup memory limit in megabytes. `"max"` and the v1 unlimited sentinel
/// mean there is no cap.
int? cgroupMemoryLimitMb(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed == 'max') {
    return null;
  }
  final bytes = int.tryParse(trimmed);
  if (bytes == null || bytes <= 0 || bytes > 1 << 40) {
    return null;
  }
  return bytes ~/ (1024 * 1024);
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
/// desktop (runs the large brief, kb-whisper ASR) measures ~112 MB/s
/// pure-Dart sha256. Below [cpuWeakMbs] the CPU alone would make the large
/// brief (CPU-only fallback) and any ASR tier above small painful, so the
/// auto picks step down.
const cpuWeakMbs = 40.0;

String describeCpuScore(double mbs) {
  return '${mbs.toStringAsFixed(0)} MB/s';
}
