import 'dart:math' as math;

import '../cloud/openai_compatible.dart';
import 'newsletter.dart';
import 'summarizer.dart';

typedef BriefProgress = void Function(int completed, int total);

/// Map/reduce over a lecture transcript, shared by the local model and the
/// cloud provider. A lecture longer than the model window is split into
/// overlapping parts, each part becomes a partial brief, and the parts are
/// merged — the middle is never dropped.
///
/// Subclasses only have to answer one chat turn list at a time.
abstract class BriefPipeline implements Summarizer {
  BriefPipeline({this.onProgress});

  final BriefProgress? onProgress;

  /// Transcript characters that fit in one request.
  int get chunkCharBudget;

  /// Parts merged in one reduce step before recursing.
  static const reduceGroup = 6;

  /// Opened once per [summarize] before the first [complete].
  Future<void> prepare() async {}

  /// Always runs, even when [complete] throws.
  Future<void> release() async {}

  Future<String> complete(List<ChatTurn> turns);

  @override
  Future<NewsletterSummary> summarize(String transcript) async {
    final parts = splitTranscriptForLlm(transcript, maxChars: chunkCharBudget);
    if (parts.isEmpty) {
      return NewsletterSummary.parseModelOutput('');
    }

    await prepare();
    try {
      final mergeSteps = parts.length > 1 ? 1 : 0;
      final total = parts.length + mergeSteps;
      final briefs = <NewsletterSummary>[];
      for (var i = 0; i < parts.length; i++) {
        onProgress?.call(i + 1, total);
        briefs.add(await _mapPart(parts[i], part: i + 1, of: parts.length));
      }
      onProgress?.call(total, total);
      if (briefs.length == 1) {
        return briefs.single;
      }
      return await _reduce(briefs);
    } finally {
      await release();
    }
  }

  Future<NewsletterSummary> _mapPart(
    String transcript, {
    required int part,
    required int of,
  }) async {
    final raw = await complete([
      ChatTurn.system(newsletterSystemPrompt()),
      ChatTurn.user(newsletterUserPrompt(newsletterFewShotTranscript)),
      ChatTurn.assistant(newsletterFewShotAssistant()),
      ChatTurn.user(newsletterUserPrompt(transcript, part: part, of: of)),
    ]);
    return NewsletterSummary.parseModelOutput(raw);
  }

  Future<NewsletterSummary> _reduce(List<NewsletterSummary> parts) async {
    if (parts.length == 1) {
      return parts.single;
    }
    if (parts.length <= reduceGroup) {
      final raw = await complete([
        ChatTurn.system(newsletterReduceSystemPrompt()),
        ChatTurn.user(newsletterReduceUserPrompt(parts)),
      ]);
      return NewsletterSummary.parseModelOutput(raw);
    }

    final grouped = <NewsletterSummary>[];
    for (var i = 0; i < parts.length; i += reduceGroup) {
      final end = math.min(i + reduceGroup, parts.length);
      grouped.add(await _reduce(parts.sublist(i, end)));
    }
    return _reduce(grouped);
  }
}
