import 'dart:math' as math;

import '../cloud/openai_compatible.dart';
import 'brief_sections.dart';
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
  BriefPipeline({
    this.onProgress,
    this.specs = BriefSectionCatalog.defaultSpecs,
    this.useFewShot = false,
    this.useKeyLines = false,
    this.useKeyLineHints = true,
    this.useRetryPass = true,
    this.useVerifyPass = false,
    this.seed,
    this.onMapRaw,
  });

  /// Sampling seed. Null = llama.cpp picks one; the quality probe pins it to
  /// measure run-to-run variance honestly.
  final int? seed;

  /// Every raw map/reduce completion, for probe dumps.
  final void Function(String stage, String raw)? onMapRaw;

  final BriefProgress? onProgress;

  /// The sections this brief asks for, in prompt order. Parsed, stored and
  /// rendered sections all follow this list.
  final List<BriefSectionSpec> specs;

  /// The few-shot pair teaches the exact output shape, but the quality probe
  /// (feedback/quality/, test/brief_probe_test.dart) showed it makes the 7B
  /// fall back to keyword soup and lets the 1.5B copy the example line into
  /// real output. Off by default; the heading list alone holds the shape.
  final bool useFewShot;

  /// Before a chunk is briefed, model passes one extract raw transcript to
  /// verbatim "key lines": content-bearing sentences, and always every
  /// mention of prov, läxa, datum, uppgift or material — the lines the
  /// brief used to miss because they sat at the start of noisy speech.
  /// Accurate but expensive (an extra decode per chunk, 2-3x slower).
  final bool useKeyLines;

  /// A free pre-pass: regex-picks transcript sentences mentioning prov,
  /// läxa, uppgift, dates or material and prepends them as verbatim hints
  /// to the map prompt, so the model checks those lines instead of reading
  /// past them. Grounded extraction — the lines already exist in the
  /// transcript, nothing can be invented here.
  final bool useKeyLineHints;

  /// One corrective retry per map chunk, fired ONLY when the data already
  /// says the draft is missing something (hint lines mention prov but the
  /// schedule section is empty; the overview is empty). A model decode that
  /// usually does not run — cheap in the common case.
  final bool useRetryPass;

  /// A self-edit pass per map chunk: the model re-reads transcript + draft
  /// and corrects it (drops verbatim echoes, checks prov/läxa coverage).
  /// Doubles prefill per chunk; the probe A/B decides if it earns its time.
  final bool useVerifyPass;

  /// Transcript characters that fit in one request.
  int get chunkCharBudget;

  /// Parts merged in one reduce step before recursing.
  static const reduceGroup = 6;

  /// Opened once per [summarize] before the first [complete].
  Future<void> prepare() async {}

  /// Always runs, even when [complete] throws.
  Future<void> release() async {}

  Future<String> complete(List<ChatTurn> turns, {bool longOutput = false});

  @override
  Future<NewsletterSummary> summarize(String transcript) async {
    final parts = splitTranscriptForLlm(transcript, maxChars: chunkCharBudget);
    if (parts.isEmpty) {
      return NewsletterSummary.parseModelOutput('', headings: _headings);
    }

    await prepare();
    try {
      final extractSteps = useKeyLines ? parts.length : 0;
      final mergeSteps = parts.length > 1 ? 1 : 0;
      final total = parts.length + extractSteps + mergeSteps;
      final briefs = <NewsletterSummary>[];
      var step = 0;
      for (var i = 0; i < parts.length; i++) {
        var text = parts[i];
        if (useKeyLines) {
          step++;
          onProgress?.call(step, total);
          text = await _extractKeyLines(text, part: i + 1, of: parts.length);
        }
        step++;
        onProgress?.call(step, total);
        briefs.add(await _mapPart(text, part: i + 1, of: parts.length));
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

  List<String> get _headings => [for (final spec in specs) spec.heading];

  /// Verbatim key-line extraction. The model only picks line NUMBERS from a
  /// numbered rendering of the chunk; Dart reassembles the kept lines, so
  /// the result is exact transcript text — never rewritten, never truncated,
  /// and cheap to decode. Fall back to the raw chunk when the model clearly
  /// failed the task (no numbers, or fewer than an eighth of the lines).
  Future<String> _extractKeyLines(
    String transcript, {
    required int part,
    required int of,
  }) async {
    final lines = transcriptLines(transcript);
    final raw = await complete([
      ChatTurn.system(extractSystemPrompt()),
      ChatTurn.user(numberedTranscript(transcript)),
    ], longOutput: true);
    final numbers = RegExp(r'\d+')
        .allMatches(raw)
        .map((m) => int.parse(m.group(0)!))
        .toSet();
    final withinRange = [
      for (final n in numbers)
        if (n >= 1 && n <= lines.length) n,
    ];
    if (withinRange.length < (lines.length / 8).ceil()) {
      return transcript;
    }
    final kept = [for (final n in withinRange) lines[n - 1]].join(' ');
    return kept.length >= transcript.length ~/ 10 ? kept : transcript;
  }

  Future<NewsletterSummary> _mapPart(
    String transcript, {
    required int part,
    required int of,
  }) async {
    var draft = NewsletterSummary.parseModelOutput('', headings: _headings);
    final turns = briefMapTurns(
      specs,
      transcript,
      useFewShot: useFewShot,
      keyLineHints: useKeyLineHints ? keyLineHints(transcript) : null,
      part: part,
      of: of,
    );
    final hints = useKeyLineHints ? keyLineHints(transcript) : null;

    var raw = await complete(turns);
    onMapRaw?.call('map $part/$of', raw);
    draft = NewsletterSummary.parseModelOutput(raw, headings: _headings);

    if (useRetryPass) {
      final retryInstruction = retryInstructionFor(draft, specs, hints);
      if (retryInstruction != null) {
        final retried = await complete([
          ...turns,
          ChatTurn.assistant(raw),
          ChatTurn.user(retryInstruction),
        ]);
        onMapRaw?.call('map retry $part/$of', retried);
        final fixed = NewsletterSummary.parseModelOutput(
          retried,
          headings: _headings,
        );
        if (_better(fixed, draft)) {
          draft = fixed;
          raw = retried;
        }
      }
    }

    if (useVerifyPass) {
      final verified = await complete([
        ChatTurn.system(verifySystemPrompt(specs)),
        ChatTurn.user(
          'Transkript:\n$transcript\n\nUnderlag:\n${draft.toMarkdown()}\n\n'
          'Svara med det korrigerade underlaget.',
        ),
      ]);
      onMapRaw?.call('verify $part/$of', verified);
      final fixed = NewsletterSummary.parseModelOutput(
        verified,
        headings: _headings,
      );
      if (_better(fixed, draft)) {
        draft = fixed;
      }
    }

    return draft;
  }

  /// True when [candidate] should replace the current draft: strictly fewer
  /// placeholder sections, or the same gaps but a fuller overview. Anything
  /// else keeps the existing draft — later passes may only improve, never
  /// silently lose sections.
  static bool _better(NewsletterSummary candidate, NewsletterSummary draft) {
    int gaps(NewsletterSummary s) => s.sections
        .where(
          (section) =>
              section.body.trim().isEmpty ||
              section.body.trim() == NewsletterSummary.emptyPlaceholder,
        )
        .length;
    final candidateGaps = gaps(candidate);
    final draftGaps = gaps(draft);
    if (candidateGaps != draftGaps) {
      return candidateGaps < draftGaps;
    }
    int words(NewsletterSummary s) =>
        s.discussed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return words(candidate) > words(draft);
  }

  /// What a corrective retry should say, or null when the draft looks fine.
  /// Data-driven: only fires when the hints themselves prove the draft
  /// missed content the transcript contains.
  static String? retryInstructionFor(
    NewsletterSummary summary,
    List<BriefSectionSpec> specs,
    String? hints,
  ) {
    if (hints == null || hints.trim().isEmpty) {
      return null;
    }
    final problems = <String>[];
    for (final spec in specs) {
      final body = summary
          .bodyOf(spec.heading)
          .trim()
          .replaceAll(NewsletterSummary.emptyPlaceholder, '');
      if (body.isNotEmpty) {
        continue;
      }
      if (spec.id == 'overview') {
        problems.add(
          'Rubriken "${spec.heading}" är tom, men transkriptet innehåller '
          'undervisning.',
        );
      } else if (spec.id == 'schedule' &&
          RegExp(
            r'\b(prov|uppgift|läxa|inlämning|ta med)',
            caseSensitive: false,
          ).hasMatch(hints)) {
        problems.add(
          'Tipsraderna nämner prov, uppgifter eller material men rubriken '
          '"${spec.heading}" är tom.',
        );
      }
    }
    if (problems.isEmpty) {
      return null;
    }
    return '${problems.join(' ')} '
        'Svara igen med HELA underlaget, samma rubriker i samma ordning. '
        'Fyll i det som saknas från transkriptet. Hitta inte på något nytt.';
  }

  Future<NewsletterSummary> _reduce(List<NewsletterSummary> parts) async {
    if (parts.length == 1) {
      return parts.single;
    }
    if (parts.length <= reduceGroup) {
      final turns = briefReduceTurns(specs, parts);
      final raw = await complete(turns);
      onMapRaw?.call('reduce', raw);
      var merged = NewsletterSummary.parseModelOutput(raw, headings: _headings);

      // A merge that LOSES content a part had is a retry offence. The map
      // parts are the ground truth here: every datum exists verbatim in a
      // part, so the instruction can only ask to restore, not invent.
      if (useRetryPass) {
        final lostContent = reduceRetryInstruction(merged, parts, specs);
        if (lostContent != null) {
          final retried = await complete([
            ...turns,
            ChatTurn.assistant(raw),
            ChatTurn.user(lostContent),
          ]);
          onMapRaw?.call('reduce retry', retried);
          final fixed = NewsletterSummary.parseModelOutput(
            retried,
            headings: _headings,
          );
          if (_better(fixed, merged)) {
            merged = fixed;
          }
        }
      }
      return merged;
    }

    final grouped = <NewsletterSummary>[];
    for (var i = 0; i < parts.length; i += reduceGroup) {
      final end = math.min(i + reduceGroup, parts.length);
      grouped.add(await _reduce(parts.sublist(i, end)));
    }
    return _reduce(grouped);
  }

  /// What a corrective reduce retry should say, or null when the merge kept
  /// everything the parts carried.
  static String? reduceRetryInstruction(
    NewsletterSummary merged,
    List<NewsletterSummary> parts,
    List<BriefSectionSpec> specs,
  ) {
    String bodyOf(NewsletterSummary s, String heading) => s
        .bodyOf(heading)
        .trim()
        .replaceAll(NewsletterSummary.emptyPlaceholder, '');
    final problems = <String>[];
    for (final spec in specs) {
      if (spec.id == 'overview') {
        continue;
      }
      final partsHad = parts.any((p) => bodyOf(p, spec.heading).isNotEmpty);
      final mergedHas = bodyOf(merged, spec.heading).isNotEmpty;
      if (partsHad && !mergedHas) {
        problems.add(
          'Ett delunderlag hade innehåll under rubriken "${spec.heading}" '
          'som försvann när delarna slogs ihop.',
        );
      }
    }
    if (problems.isEmpty) {
      return null;
    }
    return '${problems.join(' ')} '
        'Behåll datum, prov, uppgifter och material från ALLA delar. '
        'Svara igen med HELA underlaget, samma rubriker i samma ordning. '
        'Hitta inte på något som inte står i delarna.';
  }
}
