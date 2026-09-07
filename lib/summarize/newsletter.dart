/// One rendered block of the brief: a section heading and what the model
/// wrote under it. The list of sections is the brief; see
/// [NewsletterSummary.parseModelOutput].
class BriefSection {
  const BriefSection({required this.heading, required this.body});

  final String heading;
  final String body;

  Map<String, dynamic> toJson() => {'heading': heading, 'body': body};

  factory BriefSection.fromJson(Map<String, dynamic> json) {
    return BriefSection(
      heading: json['heading'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }
}

class NewsletterSummary {
  const NewsletterSummary({required this.sections});

  factory NewsletterSummary.legacy({
    String? discussed,
    String? decided,
    String? absentees,
  }) {
    return NewsletterSummary(
      sections: [
        BriefSection(
          heading: discussedHeading,
          body: discussed ?? emptyPlaceholder,
        ),
        BriefSection(
          heading: decidedHeading,
          body: decided ?? emptyPlaceholder,
        ),
        BriefSection(
          heading: absenteesHeading,
          body: absentees ?? emptyPlaceholder,
        ),
      ],
    );
  }

  final List<BriefSection> sections;

  static const discussedHeading = 'Vad som togs upp';
  static const decidedHeading = 'Datum, prov och uppgifter';
  static const absenteesHeading = 'För frånvarande och vårdnadshavare';

  static const legacyDiscussedHeading = 'Vad som diskuterades';
  static const legacyDecidedHeading = 'Vad som beslutades';
  static const legacyAbsenteesHeading = 'Vad de som inte var där behöver veta';

  static const emptyPlaceholder = 'Inget tydligt i transkriptet.';

  /// The section headings the default brief is parsed against.
  static const defaultHeadings = [
    discussedHeading,
    decidedHeading,
    absenteesHeading,
  ];

  String bodyOf(String heading) {
    for (final section in sections) {
      if (section.heading.toLowerCase() == heading.toLowerCase()) {
        return section.body;
      }
    }
    return '';
  }

  /// The overview is what the home screen previews and where the lecture
  /// name comes from, so it falls back to the first section written.
  String get discussed {
    final body = bodyOf(discussedHeading);
    if (body.isNotEmpty) {
      return body;
    }
    return sections.isEmpty ? '' : sections.first.body;
  }

  String get decided => bodyOf(decidedHeading);

  String get absentees => bodyOf(absenteesHeading);

  String toMarkdown() {
    final buffer = StringBuffer();
    for (final section in sections) {
      buffer
        ..writeln('## ${section.heading}')
        ..writeln()
        ..writeln(section.body);
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic> toJson() => {
    'sections': [for (final s in sections) s.toJson()],
    // Legacy keys so an older app version can still read a newer session
    // file. Extra sections have no legacy slot; the old reader just shows
    // its three standard headings.
    'discussed': discussed,
    'decided': decided,
    'absentees': absentees,
  };

  factory NewsletterSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['sections'];
    if (raw is List) {
      final sections = [
        for (final entry in raw)
          if (entry is Map<String, dynamic>) BriefSection.fromJson(entry),
      ];
      if (sections.isNotEmpty) {
        return NewsletterSummary(sections: sections);
      }
    }
    return NewsletterSummary.legacy(
      discussed: json['discussed'] as String? ?? '',
      decided: json['decided'] as String? ?? '',
      absentees: json['absentees'] as String? ?? '',
    );
  }

  /// Parses the enabled section headings, in prompt order. Unknown layout
  /// goes into the first section. Model output that names a heading the
  /// brief does not ask for is dropped, not shown.
  factory NewsletterSummary.parseModelOutput(
    String raw, {
    List<String>? headings,
  }) {
    final keys = headings ?? defaultHeadings;
    final text = normalizeModelOutput(raw);
    if (text.isEmpty) {
      return NewsletterSummary(
        sections: [
          for (final key in keys)
            BriefSection(heading: key, body: emptyPlaceholder),
        ],
      );
    }

    final sections = <BriefSection>[];
    var foundAny = false;
    for (var i = 0; i < keys.length; i++) {
      final next = i + 1 < keys.length ? keys[i + 1] : null;
      // A stored/older prompt may name the legacy headings; both spellings
      // count as found.
      final body =
          _section(text, keys[i], next) ??
          _section(text, _legacyAlias(keys[i]) ?? keys[i], next);
      if (body != null) {
        foundAny = true;
      }
      sections.add(
        BriefSection(heading: keys[i], body: body ?? emptyPlaceholder),
      );
    }

    if (!foundAny) {
      // The model wrote prose or unknown headings: the first section takes
      // the whole text so nothing is silently dropped.
      return NewsletterSummary(
        sections: [
          for (var i = 0; i < sections.length; i++)
            i == 0
                ? BriefSection(heading: sections[i].heading, body: text)
                : sections[i],
        ],
      );
    }

    return NewsletterSummary(sections: sections);
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

  static String? _section(String text, String heading, String? nextHeading) {
    final start = _headingIndex(text, heading);
    if (start < 0) {
      return null;
    }
    final bodyStart = start + heading.length;
    final end = _sectionEnd(text, bodyStart, nextHeading);
    final slice = text.substring(bodyStart, end);

    // Models sometimes leave the empty placeholder line inside a section
    // that also has real content ("20 frågor...\nInget tydligt i
    // transkriptet."). The placeholder is only meaningful when it is ALL
    // the section says.
    final kept = slice
        .split('\n')
        .where(
          (line) =>
              _normalizeWhitespace(line) !=
              _normalizeWhitespace(emptyPlaceholder),
        )
        .join('\n')
        .trim();
    if (kept.isEmpty) {
      return null;
    }

    return kept
        .replaceFirst(RegExp(r'^[\s#:]+'), '')
        .replaceFirst(RegExp(r'\n*#+\s*$'), '')
        .trim();
  }

  static String _normalizeWhitespace(String s) {
    return s.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// A section body stops at the next requested heading — or at any other
  /// markdown heading line, so sections the brief did not ask for never
  /// bleed into the last requested one.
  static int _sectionEnd(String text, int bodyStart, String? nextHeading) {
    var end = text.length;
    if (nextHeading != null) {
      final at = _headingIndex(text, nextHeading, from: bodyStart);
      if (at > bodyStart) {
        end = at;
      }
    }
    final headingLine = RegExp(r'^\s*#{1,6}\s', multiLine: true);
    for (final match in headingLine.allMatches(text, bodyStart)) {
      if (match.start > bodyStart && match.start < end) {
        end = match.start;
        break;
      }
    }
    return end;
  }

  static String? _legacyAlias(String heading) {
    switch (heading) {
      case discussedHeading:
        return legacyDiscussedHeading;
      case decidedHeading:
        return legacyDecidedHeading;
      case absenteesHeading:
        return legacyAbsenteesHeading;
      default:
        return null;
    }
  }

  static int _headingIndex(String text, String heading, {int from = 0}) {
    final lower = text.toLowerCase();
    final needle = heading.toLowerCase();
    return lower.indexOf(needle, from);
  }
}

/// Swedish course-stuff keywords plus weekdays/dates in prose. Lines with
/// any of these are the ones the brief historically lost to noise.
final RegExp _keyLinePattern = RegExp(
  r'\b(prov|provet|test|diagnos|läxa|läxor|uppgift|uppgifter|'
  r'inlämning|inlämningar|kapitel|sida|fredag|måndag|tisdag|onsdag|torsdag|'
  r'lördag|söndag|vecka|fråga|frågor|nästa gång|ta med)\b',
  caseSensitive: false,
);

/// Splits raw transcript text into rough sentences (whisper output is
/// unpunctuated or badly punctuated; '.' needs following whitespace).
List<String> _roughSentences(String text) {
  final pieces = <String>[];
  final buffer = StringBuffer();
  for (final word in text.split(RegExp(r'\s+'))) {
    buffer.write(word);
    buffer.write(' ');
    if (RegExp(r'[.!?]$').hasMatch(word)) {
      pieces.add(buffer.toString().trim());
      buffer.clear();
    }
  }
  final rest = buffer.toString().trim();
  if (rest.isNotEmpty) {
    pieces.add(rest);
  }
  return pieces;
}

/// Whole transcript sentences that look like they carry prov / läxa /
/// uppgift / material information, verbatim. These "hints" go into the map
/// prompt so a line buried at the start of noisy speech is checked, not
/// skipped. Extraction, not rewriting — the text is already in the
/// transcript, so nothing here can be invented.
String keyLineHints(
  String transcript, {
  int maxLines = 16,
  int maxChars = 2400,
  int maxLineChars = 240,
}) {
  final lines = <String>[];
  var chars = 0;
  for (final sentence in _roughSentences(transcript)) {
    if (lines.length >= maxLines || chars >= maxChars) {
      break;
    }
    if (_keyLinePattern.hasMatch(sentence)) {
      var trimmed = sentence.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.length > maxLineChars) {
        trimmed = trimmed.substring(0, maxLineChars);
      }
      if (lines.contains(trimmed)) {
        continue;
      }
      if (chars + trimmed.length > maxChars) {
        break;
      }
      lines.add(trimmed);
      chars += trimmed.length;
    }
  }
  return lines.map((l) => '- $l').join('\n');
}

/// Splits raw transcript text into rough sentences (whisper output is
/// unpunctuated or badly punctuated; '.' needs following whitespace) and
/// hard-wraps overlong runs at word boundaries, so every line stays
/// verbatim and individually referenceable.
List<String> transcriptLines(String text, {int maxLineChars = 280}) {
  final lines = <String>[];
  for (final sentence in _roughSentences(text)) {
    var piece = sentence.trim();
    if (piece.isEmpty) {
      continue;
    }
    while (piece.length > maxLineChars) {
      var cut = piece.lastIndexOf(' ', maxLineChars);
      if (cut <= 0) {
        cut = maxLineChars;
      }
      lines.add(piece.substring(0, cut).trim());
      piece = piece.substring(cut).trim();
    }
    if (piece.isNotEmpty) {
      lines.add(piece);
    }
  }
  return lines;
}

/// The transcript as numbered lines for the selection pass.
String numberedTranscript(String text) {
  final lines = transcriptLines(text);
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    buffer.writeln('${i + 1}. ${lines[i]}');
  }
  return buffer.toString().trim();
}

/// The original text for the selected line numbers, verbatim and in order.
String selectTranscriptLines(String text, Iterable<int> numbers) {
  final lines = transcriptLines(text);
  final picked = <int>{};
  for (final n in numbers) {
    if (n >= 1 && n <= lines.length) {
      picked.add(n);
    }
  }
  return picksToText(picked, lines);
}

String picksToText(Set<int> picked, List<String> lines) {
  return [for (final n in picked) lines[n - 1]].join(' ');
}

String newsletterUserPrompt(
  String transcript, {
  int? part,
  int? of,
  String? hints,
}) {
  final buffer = StringBuffer();
  if (part != null && of != null && of > 1) {
    buffer.write(
      'Detta är del $part av $of av transkriptet. '
      'Sammanfatta bara denna del.\n\n',
    );
  }
  buffer.write('Transkript:\n$transcript');
  if (hints != null && hints.trim().isNotEmpty) {
    buffer.write(
      '\n\nDessa rader ur transkriptet nämner troligen prov, '
      'uppgifter eller material:\n$hints\n'
      'Ta med det som hör hemma i underlaget.',
    );
  }
  return buffer.toString();
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
