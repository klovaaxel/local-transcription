import 'lecture_session.dart';

/// One row of the lecture list: what the home screen and the session list can
/// render, and nothing else. The lecture itself lives in the session's own
/// file, so the index holding these is a manifest rather than a second copy of
/// everything the user has ever recorded.
class SessionEntry {
  const SessionEntry({
    required this.id,
    required this.startedAt,
    required this.status,
    this.endedAt,
    this.audioPath,
    this.error,
    this.preview = '',
    this.cachedTitle,
  });

  /// How much of the lecture the card shows before it ellipsises. This number
  /// is the reason the manifest needs text at all: a lecture that has been
  /// recorded but not yet briefed has no summary to preview, so the card
  /// falls back to the transcript.
  static const previewLimit = 110;

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SessionStatus status;

  /// Kept so the session page can tell whether the recording is still on disk
  /// and "Transkribera om" is worth offering.
  final String? audioPath;
  final String? error;

  /// The card's text, decided when the session was written: the brief's
  /// overview if there is one, otherwise the transcript as it stands, trimmed
  /// and cut to [previewLimit]. Empty means the card falls back to the
  /// lecture's status.
  final String preview;

  /// [NewsletterSummary.autoTitle], cached for the same reason -- the name is
  /// derived from the brief, so there is no way to know it without the
  /// summary. Null until a brief exists, and null when the brief found no
  /// subject, because the date names that lecture.
  final String? cachedTitle;

  /// Everything here is derived from the session rather than stored on it, so
  /// the manifest is written on every state transition and whatever the
  /// lecture list needs has to be computed at that moment.
  factory SessionEntry.fromSession(LectureSession session) {
    final text = session.summary?.discussed ?? session.displayTranscript;
    final trimmed = text.trim();
    return SessionEntry(
      id: session.id,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      status: session.status,
      audioPath: session.audioPath,
      error: session.error,
      preview: trimmed.length > previewLimit
          ? '${trimmed.substring(0, previewLimit)}…'
          : trimmed,
      cachedTitle: session.summary?.autoTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'status': status.name,
    'audioPath': audioPath,
    'error': error,
    'preview': preview,
    'cachedTitle': cachedTitle,
  };

  factory SessionEntry.fromJson(Map<String, dynamic> json) {
    return SessionEntry(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String),
      status: SessionStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SessionStatus.ready,
      ),
      audioPath: json['audioPath'] as String?,
      error: json['error'] as String?,
      preview: json['preview'] as String? ?? '',
      cachedTitle: json['cachedTitle'] as String?,
    );
  }
}
