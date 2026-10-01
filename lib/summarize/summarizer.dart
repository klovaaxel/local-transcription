import 'brief_pipeline.dart' show BriefCancelled;
import 'newsletter.dart';

/// A local or cloud run of the brief pipeline. The interface stays this thin so
/// the two backends only have to answer one chat turn list at a time, per
/// AGENTS.md; [cancel] is here because the teacher's way out of a minutes-long
/// local decode belongs on the thing doing the work, not on the UI.
abstract class Summarizer {
  Future<NewsletterSummary> summarize(String transcript);

  /// Stop after the current chunk. May throw [BriefCancelled] out of an
  /// in-flight [summarize] rather than returning.
  void cancel();
}