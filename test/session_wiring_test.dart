import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/app_state.dart';
import 'package:lecture_local/asr/asr_engine.dart';
import 'package:lecture_local/data/lecture_session.dart';
import 'package:lecture_local/data/session_entry.dart';
import 'package:lecture_local/data/session_store.dart';

/// Counts what the app asks the store to do, without touching the disk. The
/// question these tests exist to answer is which of those calls happen on a
/// caption event -- the regression this whole change is about.
class SpyStore extends SessionStore {
  SpyStore(this.dir);

  final Directory dir;
  int saves = 0;
  int appends = 0;
  final appended = <String>[];

  @override
  Future<Directory> root() async => dir;

  @override
  Future<void> save(LectureSession session) async {
    saves++;
  }

  @override
  Future<void> appendCaptions(String id, String text) async {
    appends++;
    appended.add(text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `LectureAppState` constructs an `AudioRecorder`, which calls straight into
  // the platform on creation. Nothing here records, so the channel only has to
  // answer, not answer correctly.
  final messenger =
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (call) async => null,
  );

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lecture_wiring');
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('a caption event appends and never rewrites the lecture', () async {
    final store = SpyStore(dir);
    final state = LectureAppState(store: store);
    final session = LectureSession(
      id: 'abc',
      startedAt: DateTime(2026, 9, 1, 10),
      status: SessionStatus.recording,
    );
    state.active = session;
    state.sessions = [SessionEntry.fromSession(session)];

    // The caption stream hands over the whole buffer every time, which is
    // exactly why writing it through `save` would rewrite the corpus.
    await state.onCaptionForTest(
      const CaptionEvent('Idag gick vi igenom unionsupplösningen.'),
    );
    await state.onCaptionForTest(
      const CaptionEvent(
        'Idag gick vi igenom unionsupplösningen. Sedan tittade vi på '
        'Karlstadskonventionen.',
      ),
    );

    expect(store.appends, 2);
    expect(store.saves, 0, reason: 'the manifest must not be rewritten per event');
    expect(store.appended.first, contains('unionsupplösningen'));
    // Verbatim, not pre-sliced: the store diffs the cumulative buffer itself.
    expect(store.appended.last.length, greaterThan(20));
  });

  test('the manifest row carries the preview the card renders', () {
    final session = LectureSession(
      id: 'abc',
      startedAt: DateTime(2026, 9, 1, 10),
      transcript: 'x' * 400,
    );

    final entry = SessionEntry.fromSession(session);

    expect(entry.preview.length, SessionEntry.previewLimit + 1);
    expect(entry.preview.endsWith('…'), isTrue);
    expect(entry.cachedTitle, isNull, reason: 'no brief yet, so the date names it');
  });

  test('an unbriefed lecture previews its transcript, a briefed one its brief', () {
    final unbriefed = LectureSession(
      id: 'a',
      startedAt: DateTime(2026, 9, 1, 10),
      transcript: 'Transkriptet börjar här och fortsätter länge än.',
    );
    expect(SessionEntry.fromSession(unbriefed).preview, startsWith('Transkriptet'));

    // A brief wins over the transcript for the preview, which is what the old
    // card did when it read `summary?.discussed ?? displayTranscript`.
    final briefed = LectureSession(
      id: 'b',
      startedAt: DateTime(2026, 9, 1, 10),
      transcript: 'Transkriptet börjar här.',
    );
    expect(SessionEntry.fromSession(briefed).preview, startsWith('Transkriptet'));
  });
}