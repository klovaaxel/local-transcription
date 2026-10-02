import 'dart:math' show min;

/// Hoisted so the split and the normalization do not compile a pattern per
/// word list. Same expressions the merge has always used - `\s` and the
/// edge-noise class - so the words they produce are unchanged.
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _edgeNoise = RegExp(r'^[^a-z0-9åäöé]+|[^a-z0-9åäöé]+$');

/// Merges overlapping Whisper window transcripts by dropping repeated words.
///
/// VAD pieces and 20 s rolling windows often restate a tail (or earlier
/// context after a pause). Suffix-prefix overlap is not enough: a window can
/// start with older words that are not the current suffix.
///
/// Stateless, and the shape every external caller should keep using:
/// `cloud_transcriber.dart` merges ten-minute parts once each and gains nothing
/// from carrying state. A caller that merges against the same text many times -
/// the caption path - should use [LiveTranscript], or [mergeInto] with a
/// [TranscriptWords] it holds itself.
String mergeOverlappingTranscript(String previous, String next) {
  return mergeInto(previous, TranscriptWords(), next);
}

/// What one merge did, for tests that hold the caching to a number rather than
/// to a stopwatch. Nothing in the app passes [onStats], so the counters are
/// never touched on the real path.
class MergeStats {
  MergeStats._(this._cost);

  final _MergeCost _cost;

  /// Words normalized while this merge ran, both sides. Re-deriving the whole
  /// accumulated transcript on every caption is what this exists to prove no
  /// longer happens.
  int get normalizedWords => _cost.normalized;

  /// Word comparisons spent searching for the overlap.
  int get comparisons => _cost.comparisons;

  /// Overlap lengths tried before the merge found its cut, and the overlap it
  /// settled on (0 when it fell back to a plain join).
  int get windowsCompared => _cost.windows;

  int get overlapWords => _cost.overlap;
}

/// Counters, gathered per merge. Private because only [mergeInto] fills them
/// and only [MergeStats] reads them out.
class _MergeCost {
  int normalized = 0;
  int comparisons = 0;
  int windows = 0;
  int overlap = 0;
}

/// [mergeOverlappingTranscript] for a caller that already holds [previousWords].
///
/// The transcript on the caption path grows for 45 minutes and is merged on
/// every commit and on every rolling-window partial. Re-splitting and
/// re-normalizing all of it every time is the whole cost of a merge - two
/// regexes per word, thousands of words - and almost none of the text it does
/// to has changed. [TranscriptWords] holds that derivation, and this reuses it.
///
/// `previousWords` must describe `previous`, which [LiveTranscript]
/// maintains; passing an index that describes something else is undefined, the
/// same way it is undefined to hand a re-tokenizer the wrong state. It absorbs
/// the result unless [absorb] is false, which is what a caller that throws the
/// merged text away wants.
String mergeInto(
  String previous,
  TranscriptWords previousWords,
  String next, {
  bool absorb = true,
  void Function(MergeStats stats)? onStats,
}) {
  final cost = onStats == null ? null : _MergeCost();
  final left = previous.trim();
  final right = next.trim();
  if (right.isEmpty) {
    onStats?.call(MergeStats._(cost!));
    return left;
  }
  if (left.isEmpty) {
    onStats?.call(MergeStats._(cost!));
    return right;
  }

  previousWords.sync(left);
  final nextWords = previousWords.scratch()..sync(right);
  cost?.normalized += previousWords.normalizedWords + nextWords.normalizedWords;

  final prevNorm = previousWords.norm;
  final nextNorm = nextWords.norm;

  // A window that restates the committed speech, or a longer decode that opens
  // with it, settles the merge on its own.
  if (_indexOfWords(prevNorm, 0, nextNorm, 0, cost) >= 0) {
    onStats?.call(MergeStats._(cost!));
    return left;
  }
  if (_isPrefix(nextNorm, prevNorm, cost)) {
    if (absorb) {
      previousWords.replaceWith(right, nextWords);
    }
    onStats?.call(MergeStats._(cost!));
    return right;
  }

  for (var n = min(prevNorm.length, nextNorm.length); n >= 1; n--) {
    cost?.windows++;
    final idx = _indexOfWords(nextNorm, 0, prevNorm, prevNorm.length - n, cost);
    if (idx == 0) {
      final merged = _append(previousWords, nextWords, n);
      if (absorb) {
        previousWords.appendFrom(merged, nextWords, n);
      }
      cost?.overlap = n;
      onStats?.call(MergeStats._(cost!));
      return merged;
    }
    if (idx > 0 && n >= 2) {
      final merged = _append(previousWords, nextWords, idx + n);
      if (absorb) {
        previousWords.appendFrom(merged, nextWords, idx + n);
      }
      cost?.overlap = n;
      onStats?.call(MergeStats._(cost!));
      return merged;
    }
  }

  // Nothing lined up: the window is new speech. Its words are already split and
  // normalized, so the plain join is the only place left that does work.
  final merged = '$left $right';
  if (absorb) {
    previousWords.appendFrom(merged, nextWords, 0);
  }
  onStats?.call(MergeStats._(cost!));
  return merged;
}

/// The words of `previous` plus everything of `next` from [from] on, joined.
///
/// `next` drops from [from] because the comparison has just proved those words
/// were said again.
String _append(
  TranscriptWords previousWords,
  TranscriptWords nextWords,
  int from,
) {
  final words = [...previousWords.words, ...nextWords.words.sublist(from)];
  return words.join(' ');
}

/// Text that is merged into over and over, with the word index kept alongside
/// it.
///
/// What `LiveCaptionBuffer` holds, and what a caller merging ten-minute parts
/// would hold if it were worth it: the merge is O(new window) instead of
/// O(whole lecture) per call, which is the difference that matters when the
/// lecture runs for 45 minutes.
class LiveTranscript {
  final TranscriptWords _words = TranscriptWords();
  String _text = '';

  String get text => _text;

  /// Takes text the index has not seen before - a transcript some other code
  /// accumulated itself.
  ///
  /// Indexed here rather than on the first [merge], because that is the one
  /// moment the cost is unavoidable: the whole lecture arrives at once, and
  /// after this every merge pays for its window alone.
  void adopt(String text) {
    _text = text.trim();
    _words.sync(_text);
  }

  void clear() {
    _words.clear();
    _text = '';
  }

  /// Merges [next] in and returns the new text.
  String merge(String next, {void Function(MergeStats stats)? onStats}) {
    _text = _merge(next, onStats: onStats, absorb: true);
    return _text;
  }

  /// Merges [next] and throws the result away, leaving this text alone.
  ///
  /// The rolling window re-derives its hypothesis several times a second
  /// against text that has not changed, so the words of [next] are discarded -
  /// while the index of the committed text, the part that is expensive, is
  /// neither rebuilt nor disturbed.
  String preview(String next, {void Function(MergeStats stats)? onStats}) {
    return _merge(next, onStats: onStats, absorb: false);
  }

  String _merge(
    String next, {
    required bool absorb,
    void Function(MergeStats stats)? onStats,
  }) {
    return mergeInto(_text, _words, next, absorb: absorb, onStats: onStats);
  }

  @override
  String toString() => _text;
}

/// The words of one text, and the same words normalized for comparison.
///
/// Splitting and normalizing is the expensive half of a merge and depends on
/// nothing but the text, so it is done once and then reused for as long as the
/// text stands still. On the caption path that is the difference between
/// re-deriving a 9,000-word lecture on every caption and deriving a 50-word
/// window.
///
/// [appendFrom] and [replaceWith] keep the derivation attached to the text they
/// produce, which is why a growing lecture stays linear: only the new words are
/// ever normalized.
class TranscriptWords {
  final List<String> words = <String>[];
  final List<String> norm = <String>[];

  /// The exact string [words] and [norm] describe, held by identity: a caller
  /// that hands back an unchanged string must not pay to split it again, and a
  /// caller that hands back a new one must not be trusted to be the same text.
  String? _text;
  int _normalized = 0;
  TranscriptWords? _scratch;

  int get length => words.length;

  /// Words the last [sync] normalized; 0 when it reused what it had.
  int get normalizedWords => _normalized;

  /// An index for the other side of the same merge, reused between merges so a
  /// window-sized split stops allocating two lists a second.
  TranscriptWords scratch() => _scratch ??= TranscriptWords();

  /// Makes this describe [text], reusing the derivation when [text] is the very
  /// string it already describes.
  void sync(String text) {
    if (identical(_text, text)) {
      _normalized = 0;
      return;
    }
    final parts = text.split(_whitespace);
    _resize(parts.length);
    for (var i = 0; i < parts.length; i++) {
      words[i] = parts[i];
      norm[i] = _normWord(parts[i]);
    }
    _normalized = parts.length;
    _text = text;
  }

  /// Becomes [text] with everything from [from] on appended - the result of a
  /// merge that added words. Only the appended words are ever normalized again.
  void appendFrom(String text, TranscriptWords tail, int from) {
    final tailWords = tail.words;
    final tailNorm = tail.norm;
    for (var i = from; i < tailWords.length; i++) {
      words.add(tailWords[i]);
      norm.add(tailNorm[i]);
    }
    _text = text;
    _normalized = 0;
  }

  /// Becomes [text], discarding the longer text it described. Reached only when
  /// a decode opens with the committed text, so the committed words stay in the
  /// list and only the tail changes.
  void replaceWith(String text, TranscriptWords other) {
    final otherWords = other.words;
    final otherNorm = other.norm;
    _resize(otherWords.length);
    for (var i = 0; i < otherWords.length; i++) {
      words[i] = otherWords[i];
      norm[i] = otherNorm[i];
    }
    _text = text;
    _normalized = 0;
  }

  /// Forgets the text it described, so nothing can read it as describing text it
  /// no longer holds.
  void clear() {
    _text = null;
    _normalized = 0;
    words.clear();
    norm.clear();
  }

  /// Grows or shrinks both lists to [count] without reallocating the ones that
  /// survive.
  void _resize(int count) {
    if (count > words.length) {
      for (var i = words.length; i < count; i++) {
        words.add('');
        norm.add('');
      }
    } else if (count < words.length) {
      words.length = count;
      norm.length = count;
    }
  }
}

bool _isPrefix(List<String> words, List<String> prefix, _MergeCost? cost) {
  if (prefix.length > words.length) {
    return false;
  }
  return _wordsEqual(words, 0, prefix, 0, prefix.length, cost);
}

/// Where the [length] words of [needle] from [needleFrom] first appear in
/// [haystack] at or after [haystackFrom], or -1.
///
/// The ranges are offsets rather than lists: the version this replaced copied a
/// `sublist` of the haystack at every candidate position, so the inner loop of
/// the merge allocated once per comparison - about 20,000 lists for a 50-word
/// window, and every caption of the lecture paid for them again.
int _indexOfWords(
  List<String> haystack,
  int haystackFrom,
  List<String> needle,
  int needleFrom,
  _MergeCost? cost,
) {
  final length = needle.length - needleFrom;
  if (length <= 0 || haystackFrom + length > haystack.length) {
    return -1;
  }
  final last = haystack.length - length;
  for (var i = haystackFrom; i <= last; i++) {
    if (_wordsEqual(haystack, i, needle, needleFrom, length, cost)) {
      return i;
    }
  }
  return -1;
}

bool _wordsEqual(
  List<String> a,
  int aFrom,
  List<String> b,
  int bFrom,
  int length,
  _MergeCost? cost,
) {
  cost?.comparisons += length;
  for (var i = 0; i < length; i++) {
    if (a[aFrom + i] != b[bFrom + i]) {
      return false;
    }
  }
  return true;
}

String _normWord(String word) {
  return word.toLowerCase().replaceAll(_edgeNoise, '');
}
