import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lecture_session.dart';

class SessionStore {
  Directory? _root;

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

  Future<List<LectureSession>> list() async {
    final file = await _indexFile();
    if (!await file.exists()) {
      return [];
    }
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    final sessions = raw
        .whereType<Map<String, dynamic>>()
        .map(LectureSession.fromJson)
        .toList();
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  Future<void> upsert(LectureSession session) async {
    final sessions = await list();
    final i = sessions.indexWhere((s) => s.id == session.id);
    if (i >= 0) {
      sessions[i] = session;
    } else {
      sessions.add(session);
    }
    await _writeIndex(sessions);
    final dir = await sessionDir(session.id);
    await File(
      p.join(dir.path, 'session.json'),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(session.toJson()));
  }

  Future<void> delete(String id) async {
    final sessions = await list();
    sessions.removeWhere((s) => s.id == id);
    await _writeIndex(sessions);
    final dir = Directory(p.join((await root()).path, id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<File> _indexFile() async {
    return File(p.join((await root()).path, 'index.json'));
  }

  Future<void> _writeIndex(List<LectureSession> sessions) async {
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    await (await _indexFile()).writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(sessions.map((s) => s.toJson()).toList()),
    );
  }
}
