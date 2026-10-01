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

  group('micHasBeenSilent', () {
    final start = DateTime(2026, 9, 30, 9);
    DateTime at(int seconds) => start.add(Duration(seconds: seconds));

    test('a pause between sentences is not silence', () {
      // Three seconds of nothing is ordinary in a lecture, not a fault.
      expect(
        micHasBeenSilent(
          silentSince: start,
          now: at(3),
          level: 0.001,
        ),
        isFalse,
      );
    });

    test('a muted mic is reported once the window passes', () {
      expect(
        micHasBeenSilent(
          silentSince: start,
          now: at(5),
          level: 0.001,
        ),
        isTrue,
      );
    });

    test('sound clears it however long the silence ran', () {
      // The mic comes back after a minute of nothing. The stale silence start
      // must not keep the warning up.
      expect(
        micHasBeenSilent(
          silentSince: start,
          now: at(60),
          level: 0.4,
        ),
        isFalse,
      );
    });

    test('an unstarted run is not silence', () {
      expect(micHasBeenSilent(silentSince: null, now: at(60)), isFalse);
    });

    test('room hum is not a broken microphone', () {
      // A still but live room reads above the threshold and stays quiet.
      expect(
        micHasBeenSilent(
          silentSince: start,
          now: at(30),
          level: 0.03,
        ),
        isFalse,
      );
    });
  });

  test('trailing speech is not silent', () {
    final samples = Float32List(16000 * 3);
    for (var i = samples.length - 16000; i < samples.length; i++) {
      samples[i] = 0.2;
    }
    expect(trailingFloatsAreSilent(samples), isFalse);
  });
}
