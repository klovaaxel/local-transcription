import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/pcm_level.dart';

void main() {
  test('silence is near zero', () {
    expect(pcm16Level(Uint8List(64)), 0);
  });

  test('a loud sample reads as hearing', () {
    final bytes = Uint8List(4);
    final data = ByteData.sublistView(bytes);
    data.setInt16(0, 20000, Endian.little);
    data.setInt16(2, -20000, Endian.little);
    expect(pcm16Level(bytes), greaterThan(0.2));
  });

  test('trailing silence is detected after speech', () {
    final samples = Float32List(16000 * 3);
    for (var i = 0; i < 16000; i++) {
      samples[i] = 0.2;
    }
    expect(trailingFloatsAreSilent(samples), isTrue);
  });

  test('trailing speech is not silent', () {
    final samples = Float32List(16000 * 3);
    for (var i = samples.length - 16000; i < samples.length; i++) {
      samples[i] = 0.2;
    }
    expect(trailingFloatsAreSilent(samples), isFalse);
  });
}
