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

/// True while a mic has produced nothing louder than [silenceBelow] for
/// [warnAfter], or once it has.
///
/// The window is long on purpose. Silence of a second or two is normal between
/// sentences and while a teacher thinks, so a shorter one would flash during
/// ordinary pauses and train the eye to ignore it — worse than not warning at
/// all. The threshold sits under classroom speech and over a quiet room's hum,
/// so it fires on a muted or unplugged mic rather than on a room that is simply
/// still.
///
/// Pure and clock-free, so the behaviour is testable: pass the time in rather
/// than reading it, and every caller's own clock stays out of the decision.
bool micHasBeenSilent({
  required DateTime? silentSince,
  required DateTime now,
  Duration warnAfter = const Duration(seconds: 5),
  double level = 0,
  double silenceBelow = 0.02,
}) {
  if (level >= silenceBelow) {
    return false;
  }
  if (silentSince == null) {
    return false;
  }
  return now.difference(silentSince) >= warnAfter;
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
