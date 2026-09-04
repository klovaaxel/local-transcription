import '../summarize/newsletter.dart';

enum SessionStatus { recording, ready, transcribing, summarizing }

class LectureSession {
  LectureSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.audioPath,
    this.transcript = '',
    this.liveCaptions = '',
    this.summary,
    this.status = SessionStatus.ready,
    this.error,
  });

  final String id;
  final DateTime startedAt;
  DateTime? endedAt;
  String? audioPath;
  String transcript;
  String liveCaptions;
  NewsletterSummary? summary;
  SessionStatus status;
  String? error;

  /// The lecture's name, derived from the brief. Null until a brief exists,
  /// or when the brief found no subject — the date names it then. Nobody
  /// types this; see [NewsletterSummary.autoTitle].
  String? get autoTitle => summary?.autoTitle;

  String get displayTranscript {
    if (transcript.trim().isNotEmpty) {
      return transcript;
    }
    return liveCaptions;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'audioPath': audioPath,
    'transcript': transcript,
    'liveCaptions': liveCaptions,
    'summary': summary?.toJson(),
    'status': status.name,
    'error': error,
  };

  factory LectureSession.fromJson(Map<String, dynamic> json) {
    return LectureSession(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String),
      audioPath: json['audioPath'] as String?,
      transcript: json['transcript'] as String? ?? '',
      liveCaptions: json['liveCaptions'] as String? ?? '',
      summary: json['summary'] is Map<String, dynamic>
          ? NewsletterSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : null,
      status: SessionStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SessionStatus.ready,
      ),
      error: json['error'] as String?,
    );
  }
}
