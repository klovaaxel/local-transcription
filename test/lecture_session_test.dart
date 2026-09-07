import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/data/lecture_session.dart';
import 'package:lecture_local/summarize/newsletter.dart';

void main() {
  test('the lecture name comes from the brief', () {
    final session = LectureSession(
      id: 'a',
      startedAt: DateTime.utc(2026, 9, 1, 12),
      summary: NewsletterSummary.legacy(
        discussed: 'Bråk och procent: vi räknade uppgift 3 till 7.',
        decided: 'Prov på fredag.',
        absentees: 'Läs kapitel 4.',
      ),
    );
    expect(session.autoTitle, 'Bråk och procent');
  });

  test('a lecture without a brief has no name yet', () {
    final session = LectureSession(
      id: 'b',
      startedAt: DateTime.utc(2026, 9, 1, 12),
      transcript: 'hej',
    );
    expect(session.autoTitle, isNull);
  });

  test('a title stored by an older build is ignored, not restored', () {
    final restored = LectureSession.fromJson({
      'id': 'c',
      'startedAt': '2026-09-01T12:00:00.000Z',
      'title': 'Åk 8 — Bråk',
      'transcript': 'hej',
    });
    expect(restored.autoTitle, isNull);
    expect(restored.transcript, 'hej');
  });

  test('round-trips the brief the name is derived from', () {
    final session = LectureSession(
      id: 'd',
      startedAt: DateTime.utc(2026, 9, 1, 12),
      summary: NewsletterSummary.legacy(discussed: 'Unionsupplösningen 1905'),
    );
    final restored = LectureSession.fromJson(session.toJson());
    expect(restored.autoTitle, 'Unionsupplösningen 1905');
  });
}
