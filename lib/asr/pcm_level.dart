import 'dart:math' as math;
import 'dart:typed_data';

/// 0–1 loudness from 16-bit mono PCM. Scaled so classroom speech reads clearly.
double pcm16Level(Uint8List bytes) {
  if (bytes.length < 2) {
    return 0;
  }
  final data = ByteData.sublistView(bytes);
  final samples = bytes.length ~/ 2;
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += sample * sample;
  }
  final rms = math.sqrt(sum / samples);
  return (rms * 5).clamp(0.0, 1.0);
}

/// True when the last [trailingSeconds] of 16 kHz float audio is below speech.
bool trailingFloatsAreSilent(
  Float32List samples, {
  int sampleRate = 16000,
  double trailingSeconds = 2,
  double rmsThreshold = 0.01,
}) {
  if (samples.isEmpty) {
    return true;
  }
  final n = math.min(samples.length, (sampleRate * trailingSeconds).round());
  final start = samples.length - n;
  var sum = 0.0;
  for (var i = start; i < samples.length; i++) {
    final s = samples[i];
    sum += s * s;
  }
  return math.sqrt(sum / n) < rmsThreshold;
}
