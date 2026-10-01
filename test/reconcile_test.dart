import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/app_state.dart';
import 'package:lecture_local/data/lecture_session.dart';
import 'package:lecture_local/data/session_store.dart';
import 'package:path/path.dart' as p;

/// The store pointed at a directory, so these tests are about what a launch
/// finds rather than about the store. `SessionStore.root` is the one place the
/// documents directory is reached, so overriding it is enough.
class StoreAt extends SessionStore {
  StoreAt(this.dir);

  final Directory dir;

  @override
  Future<Directory> root() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (call) async => null,
  );
  tearDownAll(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
  });

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lecture_reconcile');
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  Future<LectureAppState> launch() async {
    final state = LectureAppState(store: StoreAt(dir));
    // init() also loads settings and package info, which want platform
    // channels; the reconciliation under test is the third statement in it, so
    // run the launch path directly instead and keep the test about the disk.
    await state.reconcileForTest();
    return state;
  }

  /// Writes a session the way the recording path does, so what the tests find
  /// on disk is shaped like a real interrupted lecture.
  Future<void> leave(LectureSession session, {String? captions}) async {
    final store = StoreAt(dir);
    await store.save(session);
    if (captions != null) {
      await store.appendCaptions(session.id, captions);
    }
  }

  LectureSession recording(String id) => LectureSession(
        id: id,
        startedAt: DateTime(2026, 9, 1, 10),
        status: SessionStatus.recording,
        audioPath: p.join(dir.path, id, 'audio.wav'),
      );

  test('a killed recording stops claiming to be recording', () async {
    await leave(recording('s1'));

    final state = await launch();

    final entry = state.sessions.single;
    expect(entry.status, SessionStatus.interrupted);
    expect(
      entry.status,
      isNot(SessionStatus.recording),
      reason: 'this is the lie the card was telling: "Spelar in", forever',
    );
  });

  test('the caption log is folded into a lecture that never got written', () async {
    final store = StoreAt(dir);
    await leave(recording('s1'));
    // What the caption stream had reached before the kill. The session file was
    // written at recording start and never again, so it holds no text.
    await store.appendCaptions('s1', 'Idag gick vi igenom unionsupplösningen.');
    await store.appendCaptions(
      's1',
      'Idag gick vi igenom unionsupplösningen. Sedan tittade vi på Karlstad.',
    );

    await launch();

    final recovered = await StoreAt(dir).load('s1');
    expect(recovered.liveCaptions, contains('Karlstad'));
    expect(recovered.status, SessionStatus.interrupted);
  });

  test('a caption log is not folded in over text that already survived', () async {
    final store = StoreAt(dir);
    final session = recording('s1')
      ..liveCaptions = 'Det som faktiskt stod kvar.'
      ..transcript = 'En riktig transkription.';
    await store.save(session);
    await store.appendCaptions('s1', 'något äldre');

    await launch();

    final recovered = await StoreAt(dir).load('s1');
    expect(recovered.transcript, 'En riktig transkription.');
    expect(
      recovered.liveCaptions,
      'Det som faktiskt stod kvar.',
      reason: 'the session file wins over the log when it has text',
    );
  });

  test('a missing audio file stops being offered as transcribable', () async {
    // The path is set but nothing was ever written there -- a kill during the
    // first seconds can do this.
    await leave(recording('s1'));

    await launch();

    final recovered = await StoreAt(dir).load('s1');
    expect(
      recovered.audioPath,
      isNull,
      reason: 'offering to re-transcribe a file that is not there is worse '
          'than offering nothing',
    );
  });

  test('an audio file that is there is kept', () async {
    final store = StoreAt(dir);
    final session = recording('s1');
    final dir1 = await store.sessionDir('s1');
    File(p.join(dir1.path, 'audio.wav')).writeAsBytesSync(List.filled(64, 0));
    await store.save(session);

    await launch();

    final recovered = await StoreAt(dir).load('s1');
    expect(recovered.audioPath, isNotNull);
    expect(recovered.status, SessionStatus.interrupted);
  });

  test('a ready lecture is left alone', () async {
    final store = StoreAt(dir);
    final session = recording('s1')
      ..status = SessionStatus.ready
      ..transcript = 'En färdig föreläsning.';
    await store.save(session);

    final state = await launch();

    expect(state.sessions.single.status, SessionStatus.ready);
    final recovered = await StoreAt(dir).load('s1');
    expect(recovered.transcript, 'En färdig föreläsning.');
  });

  test('a lecture interrupted mid-transcription is reconciled too', () async {
    await leave(recording('s1')..status = SessionStatus.transcribing);

    final state = await launch();

    expect(state.sessions.single.status, SessionStatus.interrupted);
  });

  test('reconciling twice changes nothing the second time', () async {
    await leave(recording('s1'));

    await launch();
    final first = await StoreAt(dir).load('s1');
    final second = launch();

    final after = await StoreAt(dir).load('s1');
    expect(after.status, first.status);
    expect(after.liveCaptions, first.liveCaptions);
    expect((await second).sessions, hasLength(1));
  });

  test('a row whose session file is gone is still reconciled', () async {
    // Should not be reachable -- the store writes the file before the row --
    // but a store from an older build, or a file deleted under it, can leave
    // this, and it must not keep claiming to be recording.
    final store = StoreAt(dir);
    await store.save(recording('s1'));
    File(p.join((await store.sessionDir('s1')).path, 'session.json'))
        .deleteSync();

    final state = await launch();

    expect(state.sessions.single.status, SessionStatus.interrupted);
  });
}