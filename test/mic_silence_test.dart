import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/app_state.dart';

void main() {
  // The detector is driven with an explicit clock rather than by pumping
  // timers: what matters is the elapsed silence, not wall time, and a test that
  // had to wait out real seconds would be slower and no more honest.
  final t0 = DateTime(2026, 9, 30, 9);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  // Constructed per test rather than in setUp, and inside a widget test: the
  // state reaches for the recorder's platform channel on construction, and
  // only the test binding answers it. Nothing is rendered — the binding is here
  // for the channel, not the tree.
  late LectureAppState state;

  // A run of quiet audio starts at the first chunk that is quiet, because that
  // is the earliest moment the app can know about it. Anything before that is
  // unobservable, so the window is counted from here and the warning can only
  // be this much late, never early.
  void quiet(int seconds) =>
      state.trackSilence(level: 0, now: at(seconds));
  void speech(int seconds) =>
      state.trackSilence(level: 0.3, now: at(seconds));

  group('a silent microphone is reported, and its recovery is confirmed', () {
    testWidgets('a pause shorter than the window is not silence', (
      tester,
    ) async {
      state = LectureAppState();
      // Four seconds of nothing, under the five-second window: a teacher
      // thinking, not a dead microphone.
      for (var i = 0; i < 4; i++) {
        quiet(i);
      }
      expect(state.statusIsHold, isFalse);
      expect(state.statusMessage, isNull);
    });

    testWidgets('sustained silence raises the warning once', (tester) async {
      state = LectureAppState();
      quiet(0);
      quiet(5);
      expect(state.statusIsHold, isTrue);
      expect(state.statusMessage, LectureAppState.micSilenceNotice);

      // Still silent: the warning must stay, not flicker or re-announce itself.
      quiet(20);
      expect(state.statusMessage, LectureAppState.micSilenceNotice);
      expect(state.statusIsHold, isTrue);
    });

    testWidgets('the window is measured from the first quiet chunk', (
      tester,
    ) async {
      // Guards the real-world timing: a lecture can go quiet at any moment, and
      // the warning must not be able to fire on the very first quiet chunk
      // using a stale start from before recording began.
      state = LectureAppState();
      quiet(30);
      expect(
        state.statusIsHold,
        isFalse,
        reason: 'a single quiet chunk is not five seconds of silence',
      );
    });

    testWidgets('a short gap in speech never triggers it', (tester) async {
      state = LectureAppState();
      // A lecture is not continuous: raise and clear the run over and over, the
      // way a teacher pausing between sentences does. Four seconds each way is
      // under the window, so this must never fire.
      for (var i = 0; i < 12; i++) {
        quiet(i * 5);
        speech(i * 5 + 4);
      }
      expect(state.statusIsHold, isFalse);
    });

    testWidgets('sound returning is confirmed, not silently dropped', (
      tester,
    ) async {
      state = LectureAppState();
      quiet(0);
      quiet(5);
      expect(state.statusMessage, LectureAppState.micSilenceNotice);

      speech(6);
      // A teacher who looked away needs to learn the mic came back, so the
      // warning is replaced by a confirmation rather than vanishing.
      expect(state.statusIsHold, isFalse);
      expect(state.statusMessage, LectureAppState.micHeardAgainNotice);
    });

    testWidgets('a room with hum is not a dead mic', (tester) async {
      state = LectureAppState();
      // Sustained, but above the threshold: the separation depends on room
      // noise sitting there. A room at 0.03 is a quiet lecture hall; a muted
      // or unplugged mic stays at 0. If the threshold ever moves above the
      // hum of a real classroom, every silent lecture warns and the teacher
      // learns to dismiss it.
      const roomHum = 0.03;
      expect(roomHum, greaterThan(LectureAppState.silenceBelow));
      for (var i = 0; i < 20; i++) {
        state.trackSilence(level: roomHum, now: at(i));
      }
      expect(state.statusIsHold, isFalse);
    });

    testWidgets('a truly dead mic is reported however long it goes on', (
      tester,
    ) async {
      state = LectureAppState();
      // Longer than any lecture, to be sure nothing about the window is
      // bounded by how long the recording runs.
      for (var i = 0; i < 400; i++) {
        state.trackSilence(level: 0, now: at(i));
      }
      expect(state.statusMessage, LectureAppState.micSilenceNotice);
    });
  });

  testWidgets('the meter reading and the warning cannot disagree', (
    tester,
  ) async {
    state = LectureAppState();
    // A chunk loud enough to read on the meter can never also be silence, or
    // the meter and the warning would contradict each other on screen. The
    // meter lights a bar above level/18.
    const speechLevel = 0.3;
    expect(speechLevel, greaterThan(1 / 18));
    expect(speechLevel, greaterThan(LectureAppState.silenceBelow));

    for (var i = 0; i < 10; i++) {
      state.trackSilence(level: speechLevel, now: at(i));
    }
    expect(state.statusIsHold, isFalse);
  });
}
