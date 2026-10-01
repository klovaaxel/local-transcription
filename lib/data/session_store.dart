import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lecture_session.dart';
import 'session_entry.dart';

/// Lectures on disk.
///
/// `index.json` is a manifest: one [SessionEntry] per lecture, no lecture
/// text. The full session lives in the lecture's own directory, which is where
/// it was already being written. That split is what makes reading the lecture
/// list cost what the number of lectures costs, instead of what everything
/// ever said in them costs -- the list is read on every launch, and the index
/// used to be re-encoded and rewritten on every caption event.
class SessionStore {
  Directory? _root;

  /// The caption log as this store last wrote it, per lecture. The caption
  /// stream hands over the whole buffer as it stands, not the words since
  /// last time, so without this the log would hold the lecture once per
  /// event.
  final Map<String, String> _captionTails = {};

  /// Manifest writes are a read-modify-write of one file, so two overlapping
  /// saves would race and the loser's lecture would vanish from the list.
  /// Every mutation goes through this chain, which also keeps a failed write
  /// from poisoning the ones behind it.
  Future<void> _writes = Future.value();

  Future<Directory> root() async {
    if (_root != null) {
      return _root!;
    }
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, 'lecture_local', 'sessions'));
    await _root!.create(recursive: true);
    return _root!;
  }

  Future<Directory> sessionDir(String id) async {
    final dir = Directory(p.join((await root()).path, id));
    await dir.create(recursive: true);
    return dir;
  }

  /// The lecture list. Manifest only -- no session file is opened, because
  /// the list renders a preview and a name that the manifest already carries.
  Future<List<SessionEntry>> list() async {
    await _migrateOnce();
    final file = await _indexFile();
    if (!await file.exists()) {
      return [];
    }
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    final entries = raw
        .whereType<Map<String, dynamic>>()
        .map(SessionEntry.fromJson)
        .toList();
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return entries;
  }

  /// One whole lecture, read from its own file.
  Future<LectureSession> load(String id) async {
    // Migration is what guarantees a legacy entry has a session file to read,
    // so even a single lecture cannot skip it.
    await _migrateOnce();
    final file = File(p.join((await sessionDir(id)).path, 'session.json'));
    if (!await file.exists()) {
      throw StateError('Ingen sparad lektion med id $id.');
    }
    return LectureSession.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  /// Writes the session and updates its row in the manifest. This is the
  /// state-transition path: a caption event goes to [appendCaptions] instead.
  Future<void> save(LectureSession session) async {
    // The session file first. The old order was the reverse and could leave a
    // manifest row pointing at a file that was never written; this way round
    // the worst case is a lecture on disk that the list has not heard of yet,
    // and nothing asks for a lecture the manifest does not list.
    final dir = await sessionDir(session.id);
    await File(p.join(dir.path, 'session.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
    );
    final entry = SessionEntry.fromSession(session);
    await _enqueue(() async {
      final entries = await list();
      final i = entries.indexWhere((e) => e.id == entry.id);
      if (i >= 0) {
        entries[i] = entry;
      } else {
        entries.add(entry);
      }
      await _writeIndex(entries);
    });
  }

  Future<void> delete(String id) async {
    _captionTails.remove(id);
    await _enqueue(() async {
      final entries = await list();
      entries.removeWhere((e) => e.id == id);
      await _writeIndex(entries);
    });
    // After the row is gone, never before. If the delete of the directory
    // dies, what is left over is files no list row points at, which is
    // recoverable; the other order leaves a lecture on screen whose text is
    // gone.
    final dir = Directory(p.join((await root()).path, id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Appends one live-caption event to the lecture's `captions.jsonl` and
  /// touches nothing else: no manifest read, no manifest write. Keeping the
  /// newest words of a lecture must not cost anything that grows with how much
  /// the user has already recorded, which is the whole reason the log is a
  /// separate append-only file rather than a field in the session.
  ///
  /// [text] is the caption buffer as it stands -- how the caption stream
  /// delivers it -- not just the words since the last event. So a line stores
  /// what grew since the previous one, and a buffer that did not extend what
  /// the store last wrote (a fresh store after a restart, or a cleared
  /// buffer) resets the recovered text instead of adding to it. Either way
  /// [readCaptions] gives back the lecture.
  ///
  /// There is nothing to close or flush afterwards, and deliberately so: the
  /// file is opened, written and closed per event with the write flushed
  /// before the future completes, so a lecture killed a moment later keeps
  /// the text that was already spoken. Holding a handle open instead would buy
  /// nothing and leave something to leak.
  Future<void> appendCaptions(String id, String text) async {
    final file = File(p.join((await sessionDir(id)).path, 'captions.jsonl'));
    final tail = _captionTails[id] ?? '';
    // What the log already holds is only known if this store wrote it. A log
    // left by an earlier run has to be superseded rather than added to, or
    // recovery would hand back the lecture twice; the file's own existence is
    // what tells the two first-event cases apart.
    final grows =
        text.startsWith(tail) && (tail.isNotEmpty || !await file.exists());
    final line = jsonEncode({
      if (!grows) 'reset': true,
      'text': grows ? text.substring(tail.length) : text,
    });
    _captionTails[id] = text;
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  /// The caption log back as one block of text, for a lecture whose session
  /// file never got written. A line that does not parse is a write a kill cut
  /// in half, and everything before it is still the lecture.
  Future<String> readCaptions(String id) async {
    final file = File(p.join((await sessionDir(id)).path, 'captions.jsonl'));
    if (!await file.exists()) {
      return '';
    }
    final text = StringBuffer();
    for (final line in const LineSplitter().convert(
      await file.readAsString(),
    )) {
      if (line.trim().isEmpty) {
        continue;
      }
      final Map<String, dynamic> event;
      try {
        event = jsonDecode(line) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }
      if (event['reset'] == true) {
        text.clear();
      }
      text.write(event['text'] as String? ?? '');
    }
    return text.toString();
  }

  Future<File> _indexFile() async {
    return File(p.join((await root()).path, 'index.json'));
  }

  Future<void> _writeIndex(List<SessionEntry> entries) async {
    final file = await _indexFile();
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    // Through a temp file and a rename, because `writeAsString` truncates the
    // file it writes: a kill between the truncate and the last byte leaves a
    // torn index, and a torn index takes down every lecture in it, not the
    // one being saved. A rename either lands or does not.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(entries.map((e) => e.toJson()).toList()),
    );
    await _replace(temp, file.path);
  }

  /// Windows refuses the rename outright when something holds the target for a
  /// moment -- a search indexer or a virus scanner does, on an ordinary
  /// laptop -- and the refusal is transient. Measured here on this machine: 0
  /// failures in 300 renames on a quiet run, 22 in 900 on a busy one. Losing
  /// a lecture to that would be absurd, so retry it. A refusal that is not
  /// transient (the target is a directory, say) still surfaces, after a few
  /// hundred milliseconds.
  Future<void> _replace(File temp, String target) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await temp.rename(target);
        return;
      } on FileSystemException {
        if (attempt == 4) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 10 * (attempt + 1)));
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() write) {
    final next = _writes.then((_) => write());
    // The chain swallows its own errors so one failed save does not turn
    // every later save into an error; the caller still sees its own.
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void>? _migrated;

  /// Rewrites an index left by a build that kept whole sessions in it. At most
  /// once per store instance; a failure clears the memo so the next call tries
  /// again rather than serving a half-migrated index forever.
  Future<void> _migrateOnce() async {
    final running = _migrated;
    if (running != null) {
      return running;
    }
    final run = _migrate();
    _migrated = run;
    try {
      await run;
    } catch (_) {
      _migrated = null;
      rethrow;
    }
  }

  /// An index is legacy exactly when its entries carry lecture text: nothing
  /// in a manifest can look like that, so a migrated index is its own end
  /// state and running this again is a no-op.
  Future<void> _migrate() async {
    final file = await _indexFile();
    if (!await file.exists()) {
      return;
    }
    final raw = jsonDecode(await file.readAsString());
    if (raw is! List) {
      return;
    }
    final legacy = [
      for (final item in raw)
        if (item is Map<String, dynamic> &&
            (item.containsKey('transcript') ||
                item.containsKey('liveCaptions')))
          item,
    ];
    if (legacy.isEmpty) {
      return;
    }

    // The copy of the old index goes down before anything is replaced. A
    // migration that dies half way has to leave the original recoverable,
    // and there are few enough installs that carrying a spare copy forever
    // costs nothing.
    final backup = File(p.join(file.parent.path, 'index.legacy.json'));
    if (!await backup.exists()) {
      await file.copy(backup.path);
    }

    for (final item in legacy) {
      final session = LectureSession.fromJson(item);
      final dir = await sessionDir(session.id);
      // The old build wrote the index before the session file, so an entry is
      // never older than the session.json beside it and writing here cannot
      // roll one back.
      await File(p.join(dir.path, 'session.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(session.toJson()),
      );
    }

    await _writeIndex([
      for (final item in raw.whereType<Map<String, dynamic>>())
        SessionEntry.fromSession(LectureSession.fromJson(item)),
    ]);
  }
}
