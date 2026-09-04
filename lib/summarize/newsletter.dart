class NewsletterSummary {
  const NewsletterSummary({
    required this.discussed,
    required this.decided,
    required this.absentees,
  });

  final String discussed;
  final String decided;
  final String absentees;

  static const discussedHeading = 'Vad som togs upp';
  static const decidedHeading = 'Datum, prov och uppgifter';
  static const absenteesHeading = 'För frånvarande och vårdnadshavare';

  static const legacyDiscussedHeading = 'Vad som diskuterades';
  static const legacyDecidedHeading = 'Vad som beslutades';
  static const legacyAbsenteesHeading = 'Vad de som inte var där behöver veta';

  static const emptyPlaceholder = 'Inget tydligt i transkriptet.';

  String toMarkdown() {
    return '''
## $discussedHeading

$discussed

## $decidedHeading

$decided

## $absenteesHeading

$absentees
'''
        .trim();
  }

  Map<String, dynamic> toJson() => {
    'discussed': discussed,
    'decided': decided,
    'absentees': absentees,
  };

  factory NewsletterSummary.fromJson(Map<String, dynamic> json) {
    return NewsletterSummary(
      discussed: json['discussed'] as String? ?? '',
      decided: json['decided'] as String? ?? '',
      absentees: json['absentees'] as String? ?? '',
    );
  }

  /// Parses the three Swedish headings. Unknown layout goes into [discussed].
  factory NewsletterSummary.parseModelOutput(String raw) {
    final text = normalizeModelOutput(raw);
    if (text.isEmpty) {
      return const NewsletterSummary(
        discussed: emptyPlaceholder,
        decided: emptyPlaceholder,
        absentees: emptyPlaceholder,
      );
    }

    final discussed =
        _section(text, discussedHeading, decidedHeading) ??
        _section(text, legacyDiscussedHeading, legacyDecidedHeading);
    final decided =
        _section(text, decidedHeading, absenteesHeading) ??
        _section(text, legacyDecidedHeading, legacyAbsenteesHeading);
    final absentees =
        _section(text, absenteesHeading, null) ??
        _section(text, legacyAbsenteesHeading, null);

    if (discussed == null && decided == null && absentees == null) {
      return NewsletterSummary(
        discussed: text,
        decided: emptyPlaceholder,
        absentees: emptyPlaceholder,
      );
    }

    return NewsletterSummary(
      discussed: _orEmpty(discussed),
      decided: _orEmpty(decided),
      absentees: _orEmpty(absentees),
    );
  }

  /// Longest a derived lecture name may get before it is cut.
  static const _titleLimit = 46;

  /// A short name for the lecture, cut from the first thing the brief says
  /// was covered. Nothing is invented: if the brief found no subject, the
  /// lecture keeps its date as its name.
  ///
  /// A colon or dash inside the first line is treated as a topic label and
  /// wins over length ("Unionsupplösningen 1905: bakgrunden…" -> the part
  /// before the colon). Sentences are deliberately not split on '.', which in
  /// Swedish also ends abbreviations like "kap." and ordinals.
  String? get autoTitle {
    var line = discussed
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty || line == emptyPlaceholder) {
      return null;
    }

    line = line
        .replaceFirst(RegExp(r'^([-*•]|\d+[.)])\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final label = RegExp(r'[:–—]|\s-\s').firstMatch(line);
    if (label != null && label.start > 0 && label.start <= _titleLimit) {
      return _tidy(line.substring(0, label.start));
    }
    if (line.length <= _titleLimit) {
      return _tidy(line);
    }

    final head = line.substring(0, _titleLimit + 1);
    final cut = head.lastIndexOf(' ');
    final stem = _tidy(cut > 0 ? head.substring(0, cut) : head);
    return stem.isEmpty ? null : '$stem…';
  }

  static String _tidy(String value) {
    return value.trim().replaceFirst(RegExp(r'[\s,;:.\-–—]+$'), '');
  }

  static String _orEmpty(String? value) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? emptyPlaceholder : v;
  }

  static String? _section(String text, String heading, String? nextHeading) {
    final start = _headingIndex(text, heading);
    if (start < 0) {
      return null;
    }
    final bodyStart = start + heading.length;
    final end = nextHeading == null
        ? text.length
        : _headingIndex(text, nextHeading, from: bodyStart);
    final slice = text.substring(bodyStart, end < 0 ? text.length : end);
    return slice
        .replaceFirst(RegExp(r'^[\s#:]+'), '')
        .replaceFirst(RegExp(r'\n*#+\s*$'), '')
        .trim();
  }

  static int _headingIndex(String text, String heading, {int from = 0}) {
    final lower = text.toLowerCase();
    final needle = heading.toLowerCase();
    return lower.indexOf(needle, from);
  }
}

String newsletterSystemPrompt() {
  return '''
Du skriver ett underlag från en svensk föreläsning som läraren klistrar in i skolplattformen.
Svara ENDAST med dessa tre rubriker, i denna ordning, med korta meningar eller punktlistor:

## ${NewsletterSummary.discussedHeading}
Ämnen och innehåll som togs upp. Inte datum, prov eller läxor.

## ${NewsletterSummary.decidedHeading}
Endast datum, prov, inlämningar och läxor som faktiskt sägs. Inget annat.

## ${NewsletterSummary.absenteesHeading}
Vad den som missade lektionen behöver göra, läsa eller ta med.

Regler:
- Svenska, kort, sakligt.
- Hitta inte på datum, namn, prov eller fakta som inte finns i transkriptet.
- Kopiera inte transkriptet. Sammanfatta.
- Om en del saknar underlag, skriv exakt: ${NewsletterSummary.emptyPlaceholder}
- Ingen inledning, ingen avslutning, inga kodstängsel.
''';
}

const newsletterFewShotTranscript =
    'Vi räknade procent och moms. Ta med linjal nästa gång.';

String newsletterFewShotAssistant() {
  return '''
## ${NewsletterSummary.discussedHeading}
Procent och moms.

## ${NewsletterSummary.decidedHeading}
${NewsletterSummary.emptyPlaceholder}

## ${NewsletterSummary.absenteesHeading}
Ta med linjal nästa gång.
'''
      .trim();
}

String newsletterUserPrompt(
  String transcript, {
  int? part,
  int? of,
}) {
  if (part != null && of != null && of > 1) {
    return 'Detta är del $part av $of av transkriptet. '
        'Sammanfatta bara denna del.\n\nTranskript:\n$transcript';
  }
  return 'Transkript:\n$transcript';
}

String newsletterReduceSystemPrompt() {
  return '''
Du slår ihop delunderlag från en lång föreläsning till ETT underlag läraren klistrar in i skolplattformen.
Svara ENDAST med dessa tre rubriker, i denna ordning:

## ${NewsletterSummary.discussedHeading}
## ${NewsletterSummary.decidedHeading}
## ${NewsletterSummary.absenteesHeading}

Regler:
- Svenska, kort, sakligt.
- Behåll datum, prov, uppgifter och "ta med" från ALLA delar. Om en del saknar något men en annan har det, behåll det som finns.
- Slå ihop "${NewsletterSummary.discussedHeading}" till en kort översikt i ungefär den ordning det togs upp. Ta bort dubbletter.
- Hitta inte på något som inte står i delarna.
- Om inget finns i någon del, skriv exakt: ${NewsletterSummary.emptyPlaceholder}
- Ingen inledning, ingen avslutning, inga kodstängsel.
''';
}

String newsletterReduceUserPrompt(List<NewsletterSummary> parts) {
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    buffer.writeln('--- Del ${i + 1} ---');
    buffer.writeln(parts[i].toMarkdown());
    buffer.writeln();
  }
  buffer.write('Slå ihop till ett underlag.');
  return buffer.toString();
}

/// Characters of transcript that fit beside prompt + few-shot + output.
///
/// The *3 chars/token estimate is deliberately conservative: fragmented
/// whisper Swedish tokenizes worse than normal prose (~2.2 chars/token at
/// worst), and an over-full chunk now fails decode instead of crashing.
int llmChunkCharBudget({
  required int contextSize,
  required int compactMaxChars,
}) {
  return ((contextSize - 1100) * 22 ~/ 10).clamp(2500, compactMaxChars);
}

/// Split a long transcript into overlapping windows that each fit [maxChars].
///
/// Prefer paragraph, then sentence, then word breaks so dates are not cut in
/// half. Overlap keeps a homework line that sits on a window boundary.
List<String> splitTranscriptForLlm(
  String transcript, {
  required int maxChars,
  int? overlapChars,
}) {
  final t = transcript.trim();
  if (t.isEmpty) {
    return const [];
  }
  if (t.length <= maxChars) {
    return [t];
  }

  final overlap = (overlapChars ?? (maxChars * 0.08).round()).clamp(
    120,
    maxChars ~/ 4,
  );
  final chunks = <String>[];
  var start = 0;
  while (start < t.length) {
    if (t.length - start <= maxChars) {
      final tail = t.substring(start).trim();
      if (tail.isNotEmpty) {
        chunks.add(tail);
      }
      break;
    }

    var end = start + maxChars;
    final minEnd = start + (maxChars * 0.6).ceil();
    end = _preferredBreak(t, from: minEnd, to: end) ?? end;
    if (end <= start) {
      end = start + maxChars;
    }

    final piece = t.substring(start, end).trim();
    if (piece.isNotEmpty) {
      chunks.add(piece);
    }

    final next = end - overlap;
    start = next <= start ? end : next;
  }
  return chunks;
}

int? _preferredBreak(String t, {required int from, required int to}) {
  final end = to.clamp(0, t.length);
  final begin = from.clamp(0, end);
  if (begin >= end) {
    return null;
  }
  final window = t.substring(begin, end);
  for (final needle in ['\n\n', '\n', '. ', '! ', '? ', ' ']) {
    final i = window.lastIndexOf(needle);
    if (i >= 0) {
      return begin + i + needle.length;
    }
  }
  return null;
}

/// Drops fences and chatter before the first known heading.
String normalizeModelOutput(String raw) {
  var text = raw.trim();
  text = text.replaceAll(RegExp(r'```[^\n]*'), '');
  text = text.trim();

  const headings = [
    NewsletterSummary.discussedHeading,
    NewsletterSummary.decidedHeading,
    NewsletterSummary.absenteesHeading,
    NewsletterSummary.legacyDiscussedHeading,
    NewsletterSummary.legacyDecidedHeading,
    NewsletterSummary.legacyAbsenteesHeading,
  ];
  var earliest = -1;
  final lower = text.toLowerCase();
  for (final heading in headings) {
    final index = lower.indexOf(heading.toLowerCase());
    if (index >= 0 && (earliest < 0 || index < earliest)) {
      earliest = index;
    }
  }
  if (earliest > 0) {
    text = text.substring(earliest).trim();
  }
  return text;
}

/// Last-resort head+tail cap. Long lectures use [splitTranscriptForLlm] instead.
String compactTranscriptForLlm(String transcript, {int maxChars = 8000}) {
  final t = transcript.trim();
  if (t.length <= maxChars) {
    return t;
  }
  final head = (maxChars * 0.18).round().clamp(400, 4000);
  final tail = maxChars - head - 20;
  if (tail <= 0) {
    return t.substring(0, maxChars);
  }
  return '${t.substring(0, head)}\n\n[...]\n\n${t.substring(t.length - tail)}';
}
