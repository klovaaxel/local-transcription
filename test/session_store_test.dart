import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/data/lecture_session.dart';
import 'package:lecture_local/data/session_entry.dart';
import 'package:lecture_local/data/session_store.dart';
import 'package:lecture_local/summarize/newsletter.dart';

/// The store resolves where it keeps lectures through [SessionStore.root], so
/// handing it a temp directory puts the real thing -- real files, real writes,
/// a real rename -- on disk, with no test seam in production code.
class TempStore extends SessionStore {
  TempStore(this.dir) {
    dir.createSync(recursive: true);
  }

  final Directory dir;

  @override
  Future<Directory> root() async => dir;
}

/// A 45-minute lecture: the review measured ~50,000 characters, and a
/// finished lecture carries the same words twice -- once as the transcript,
/// once as the live captions that were on screen while it was recorded.
String _spoken(int chars) {
  const words = [
    'Bråk',
    'procent',
    'genomgången',
    'ekvationen',
    'provet',
    'kapitel',
  ];
  final buffer = StringBuffer();
  var i = 0;
  while (buffer.length < chars) {
    buffer.write('${words[i++ % words.length]} ');
  }
  return buffer.toString().substring(0, chars);
}

LectureSession _lecture(
  String id, {
  DateTime? startedAt,
  bool briefed = false,
}) {
  final text = _spoken(50000);
  return LectureSession(
    id: id,
    startedAt: startedAt ?? DateTime(2026, 9, 1, 10, 30, 15, 250),
    endedAt: DateTime(2026, 9, 1, 11, 15),
    audioPath: 'C:/Users/lektör/AppData/sessions/$id/audio.wav',
    transcript: text,
    liveCaptions: text,
    summary: briefed
        ? NewsletterSummary.legacy(
            discussed: 'Unionsupplösningen 1905 och Karlstadskonventionen.',
            decided: 'Prov på fredag den 12 september.',
            absentees: 'Läs kapitel 4.',
          )
        : null,
  );
}

File _index(Directory dir) =>
    File('${dir.path}${Platform.pathSeparator}index.json');

File _sessionFile(Directory dir, String id, String name) => File(
  '${dir.path}${Platform.pathSeparator}$id${Platform.pathSeparator}$name',
);

void main() {
  late Directory dir;
  late TempStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('session_store');
    store = TempStore(dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('the manifest holds no lecture text', () async {
    final lectures = [
      for (var i = 0; i < 12; i++)
        _lecture('l$i', startedAt: DateTime(2026, 9, 1 + i ~/ 4, 9, i)),
    ];
    for (final lecture in lectures) {
      await store.save(lecture);
    }

    final manifest = _index(dir).lengthSync();
    // Exactly what the old index wrote: every whole session, indented.
    final corpus = const JsonEncoder.withIndent('  ')
        .convert([for (final lecture in lectures) lecture.toJson()])
        .length;

    expect(
      manifest,
      lessThan(corpus ~/ 20),
      reason: 'the manifest is $manifest bytes for a $corpus byte corpus',
    );

    final raw = _index(dir).readAsStringSync();
    for (final lecture in lectures) {
      expect(raw, isNot(contains(lecture.transcript)));
      expect(raw, isNot(contains(lecture.liveCaptions)));
      expect(raw, isNot(contains(lecture.transcript.substring(200))));
    }

    // And the list itself is what the home screen will read: twelve rows, each
    // a snippet and a name.
    final entries = await store.list();
    expect(entries, hasLength(12));
    for (final entry in entries) {
      expect(entry.preview.length, lessThanOrEqualTo(111));
      expect(entry.audioPath, isNotNull);
      expect(entry.cachedTitle, isNull);
    }
  });

  test('a saved lecture reads back whole', () async {
    final lecture = LectureSession(
      id: 'l1',
      startedAt: DateTime(2026, 9, 1, 10, 30, 15, 250),
      endedAt: DateTime(2026, 9, 1, 11, 15, 30, 500),
      audioPath: r'C:\Users\lektör\AppData\sessions\l1\audio.wav',
      transcript:
          'Vi gick igenom unionsupplösningen 1905.\nOch Karlstadskonventionen.',
      liveCaptions: 'Vi gick igenom unionsupplösningen.',
      summary: NewsletterSummary.legacy(
        discussed: 'Unionsupplösningen 1905: bakgrunden.',
        decided: 'Prov på fredag.',
        absentees: 'Läs kapitel 4.',
      ),
      status: SessionStatus.ready,
      error: 'Ljudfilen kunde inte läsas.',
    );

    await store.save(lecture);
    // A different store object, the way the next launch sees it.
    final restored = await TempStore(dir).load('l1');

    expect(restored.toJson(), lecture.toJson());
    expect(restored.transcript, lecture.transcript);
    expect(restored.liveCaptions, lecture.liveCaptions);
    expect(restored.summary?.discussed, 'Unionsupplösningen 1905: bakgrunden.');
    expect(restored.error, 'Ljudfilen kunde inte läsas.');
    expect(restored.audioPath, lecture.audioPath);
    expect(restored.endedAt, lecture.endedAt);
  });

  test('the preview is what the lecture card already rendered', () async {
    // The rule the home card used, verbatim. Applied to the cached preview it
    // has to change nothing, which is what keeps the screen identical.
    String card(String text) => text.trim().isEmpty
        ? ''
        : (text.length > 110 ? '${text.substring(0, 110)}…' : text);

    final briefed = _lecture('l1', briefed: true);
    final entry = SessionEntry.fromSession(briefed);
    expect(entry.preview, card(briefed.summary!.discussed));
    expect(entry.preview, 'Unionsupplösningen 1905 och Karlstadskonventionen.');
    expect(entry.preview, card(entry.preview));

    // No brief yet: the transcript stands in for it, and the captions are
    // only used when there is no transcript.
    final unbriefed = LectureSession(
      id: 'l2',
      startedAt: DateTime(2026, 9, 1),
      transcript: '  Bråk och procent idag.  ',
      liveCaptions: 'något annat',
    );
    expect(
      SessionEntry.fromSession(unbriefed).preview,
      'Bråk och procent idag.',
    );

    final live = LectureSession(
      id: 'l3',
      startedAt: DateTime(2026, 9, 1),
      liveCaptions: 'Just nu säger jag detta.',
    );
    expect(SessionEntry.fromSession(live).preview, 'Just nu säger jag detta.');

    // Cut at 110 characters, ellipsis appended -- the card's own arithmetic.
    final long = LectureSession(
      id: 'l4',
      startedAt: DateTime(2026, 9, 1),
      transcript: 'x' * 400,
    );
    final cut = SessionEntry.fromSession(long).preview;
    expect(cut, '${'x' * 110}…');
    expect(cut.length, 111);

    // Nothing to show means the card falls back to the lecture's status, so
    // an empty preview has to stay empty rather than become a stray ellipsis.
    expect(
      SessionEntry.fromSession(
        LectureSession(id: 'l5', startedAt: DateTime(2026, 9, 1)),
      ).preview,
      '',
    );
    expect(
      SessionEntry.fromSession(
        LectureSession(
          id: 'l6',
          startedAt: DateTime(2026, 9, 1),
          transcript: '   ',
        ),
      ).preview,
      '',
    );
  });

  test('a brief with nothing to say names nothing', () async {
    final blank = NewsletterSummary.legacy(
      discussed: NewsletterSummary.emptyPlaceholder,
    );
    final session = LectureSession(
      id: 'l1',
      startedAt: DateTime(2026, 9, 1),
      transcript: 'Dagens föreläsning handlade om saker.',
      summary: blank,
    );

    expect(session.autoTitle, isNull);
    expect(SessionEntry.fromSession(session).cachedTitle, isNull);
    // The date names that lecture, so the card still has text to show.
    expect(SessionEntry.fromSession(session).preview, isNotEmpty);
  });

  test('the lecture name is cached once the brief exists', () async {
    final session = LectureSession(
      id: 'l1',
      startedAt: DateTime(2026, 9, 1),
      transcript: 'Vi gick igenom unionsupplösningen.',
    );
    expect(SessionEntry.fromSession(session).cachedTitle, isNull);

    await store.save(session);
    expect((await store.list()).single.cachedTitle, isNull);

    session.summary = NewsletterSummary.legacy(
      discussed:
          'Unionsupplösningen 1905: bakgrunden och Karlstadskonventionen.',
    );
    await store.save(session);

    final entry = (await store.list()).single;
    expect(entry.cachedTitle, 'Unionsupplösningen 1905');
    expect(entry.cachedTitle, session.autoTitle);
  });

  test('a caption event never touches the manifest', () async {
    await store.save(_lecture('l1'));
    final manifest = _index(dir);
    final sessionFile = _sessionFile(dir, 'l1', 'session.json');
    final before = manifest.readAsBytesSync();
    final beforeModified = manifest.statSync().modified;
    final sessionBefore = sessionFile.readAsBytesSync();

    // The caption stream hands over the whole buffer as it stands.
    var spoken = '';
    var restated = 0;
    for (var i = 0; i < 5; i++) {
      spoken = '$spoken${_spoken(2000)}';
      restated += spoken.length;
      await store.appendCaptions('l1', spoken);
    }

    expect(manifest.readAsBytesSync(), before);
    expect(manifest.statSync().modified, beforeModified);
    expect(sessionFile.readAsBytesSync(), sessionBefore);
    expect(await store.readCaptions('l1'), spoken);

    // Each line holds what grew, so the log costs the lecture. Restoring the
    // buffer as it stood on every event -- what the field's `upsert` did --
    // would have cost five times the lecture.
    final log = _sessionFile(dir, 'l1', 'captions.jsonl').lengthSync();
    expect(log, lessThan(restated ~/ 2));
  });

  test(
    'a caption log left by an earlier run is superseded, not added to',
    () async {
      await store.appendCaptions('l1', 'Första halvan av föreläsningen.');
      await store.appendCaptions(
        'l1',
        'Första halvan av föreläsningen. Och mer.',
      );

      // The next launch: a store that has never seen this lecture, against a
      // log somebody else wrote.
      final later = TempStore(dir);
      await later.appendCaptions(
        'l1',
        'Första halvan av föreläsningen. Och mer.',
      );

      expect(
        await later.readCaptions('l1'),
        'Första halvan av föreläsningen. Och mer.',
      );
    },
  );

  test('a lecture killed mid-write keeps the words already spoken', () async {
    await store.appendCaptions('l1', 'Vi började med bråk.');
    final log = _sessionFile(dir, 'l1', 'captions.jsonl');
    // A kill can cut the last line in half; the rest is still the lecture.
    log.writeAsStringSync('{"text": "halv', mode: FileMode.append);

    expect(await store.readCaptions('l1'), 'Vi började med bråk.');
  });

  test('an index that kept whole lectures is migrated once', () async {
    final legacy = [
      _lecture('l1', briefed: true),
      _lecture('l2', startedAt: DateTime(2026, 8, 30)),
      _lecture('l3', startedAt: DateTime(2026, 9, 2)),
    ];
    final old = _index(dir);
    old.writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert([for (final lecture in legacy) lecture.toJson()]),
    );
    final oldBytes = old.readAsBytesSync();

    final entries = await store.list();

    expect(entries.map((e) => e.id), ['l3', 'l1', 'l2']);
    expect(entries.first.preview, isNotEmpty);
    expect(
      entries.first.preview.length,
      lessThanOrEqualTo(111),
      reason: 'a migrated row previews the lecture, it does not copy it',
    );

    final manifestBytes = old.lengthSync();
    expect(
      manifestBytes,
      lessThan(oldBytes.length ~/ 20),
      reason:
          '$manifestBytes bytes of manifest for ${oldBytes.length} of index',
    );
    for (final lecture in legacy) {
      final restored = await store.load(lecture.id);
      expect(restored.toJson(), lecture.toJson());
    }

    final backup = File(
      '${dir.path}${Platform.pathSeparator}index.legacy.json',
    );
    expect(backup.readAsBytesSync(), oldBytes);

    // Twice is a no-op: the manifest is its own end state.
    final manifest = old.readAsBytesSync();
    await TempStore(dir).list();
    expect(old.readAsBytesSync(), manifest);
    expect(backup.readAsBytesSync(), oldBytes);
  });

  test('a new install never leaves a backup behind', () async {
    await store.save(_lecture('l1'));
    await store.list();
    expect(
      File('${dir.path}${Platform.pathSeparator}index.legacy.json')
          .existsSync(),
      isFalse,
    );
  });

  test('an interrupted save leaves the previous index readable', () async {
    await store.save(_lecture('l1'));
    final manifest = _index(dir);
    final before = manifest.readAsStringSync();

    // Something is in the way of the temp file, so the write that is about to
    // replace the index cannot finish. Nothing about the old index should
    // have moved.
    final temp = Directory('${manifest.path}.tmp')..createSync();
    await expectLater(
      store.save(_lecture('l2', startedAt: DateTime(2026, 9, 2))),
      throwsA(isA<FileSystemException>()),
    );

    expect(manifest.readAsStringSync(), before);
    expect(await store.list(), hasLength(1));
    expect(temp.existsSync(), isTrue);

    temp.deleteSync();
    await store.save(_lecture('l2', startedAt: DateTime(2026, 9, 2)));
    expect((await store.list()).map((e) => e.id), ['l2', 'l1']);
    expect(await store.load('l1'), isNotNull);
  });

  test('the session file is written before the index names it', () async {
    await store.save(_lecture('l1'));

    // Every row the manifest carries can be loaded: an index entry is never
    // published before the lecture it names is on disk.
    for (final entry in await store.list()) {
      expect(await store.load(entry.id), isNotNull);
    }
  });

  test('deleting a lecture takes its row and its files', () async {
    await store.save(_lecture('l1'));
    await store.save(_lecture('l2', startedAt: DateTime(2026, 9, 2)));
    await store.appendCaptions(
      'l1',
      'text som ska försvinna med föreläsningen.',
    );

    await store.delete('l1');

    final entries = await store.list();
    expect(entries.map((e) => e.id), ['l2']);
    expect(_sessionFile(dir, 'l1', 'session.json').existsSync(), isFalse);
    expect(_sessionFile(dir, 'l1', 'captions.jsonl').existsSync(), isFalse);
    expect(await store.load('l2'), isNotNull);
    await expectLater(store.load('l1'), throwsA(isA<StateError>()));
  });
}
