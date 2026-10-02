// The merge and the caption buffer exactly as they were before the merge kept
// normalized words, stopped allocating a `sublist` per comparison and stopped
// searching the whole accumulated transcript for a tail overlap.
//
// This is the oracle, not a second implementation to keep in step. The
// optimized merge in lib/asr/ must agree with it on every input, byte for
// byte: the transcripts this app ships, and the quality baselines in
// feedback/quality/SCORES.md, were all measured against this behaviour. When
// the two disagree the optimized one is wrong, never the reference.
//
// It lives in its own file so the merge tests and the buffer tests cannot end
// up checking against two different baselines.

/// Words [_refNormWord] has run over since [resetReferenceWork].
///
/// The old cost of a merge was dominated by this: `prevNorm` was rebuilt for
/// the whole accumulated transcript on every single caption.
int referenceNormalizedWords = 0;

/// Fallback scans the old loop has made since [resetReferenceWork].
int referenceWindowsScanned = 0;

/// Numbers of word normalizations and fallback scans, read once per scenario.
(int words, int windows) referenceWork() {
  final work = (referenceNormalizedWords, referenceWindowsScanned);
  resetReferenceWork();
  return work;
}

void resetReferenceWork() {
  referenceNormalizedWords = 0;
  referenceWindowsScanned = 0;
}

String mergeReference(String previous, String next) {
  final left = previous.trim();
  final right = next.trim();
  if (right.isEmpty) {
    return left;
  }
  if (left.isEmpty) {
    return right;
  }

  final prevWords = left.split(RegExp(r'\s+'));
  final nextWords = right.split(RegExp(r'\s+'));
  final prevNorm = [for (final w in prevWords) _refNormWord(w)];
  final nextNorm = [for (final w in nextWords) _refNormWord(w)];

  if (_refIndexOfWords(prevNorm, nextNorm) >= 0) {
    return left;
  }
  if (_refIsPrefix(nextNorm, prevNorm)) {
    return right;
  }

  for (var n = _refMin(prevNorm.length, nextNorm.length); n >= 1; n--) {
    referenceWindowsScanned++;
    final idx = _refIndexOfWords(nextNorm, prevNorm.sublist(prevNorm.length - n));
    if (idx == 0) {
      return [...prevWords, ...nextWords.sublist(n)].join(' ');
    }
    if (idx > 0 && n >= 2) {
      return [...prevWords, ...nextWords.sublist(idx + n)].join(' ');
    }
  }

  return '$left $right';
}

/// [LiveCaptionBuffer] as it was: every call went back to the free function with
/// the whole committed text.
class ReferenceCaptionBuffer {
  String committed = '';
  String partial = '';

  void setPartial(String text) {
    partial = text.trim();
  }

  void commit(String text) {
    final piece = text.trim();
    if (piece.isNotEmpty) {
      committed = mergeReference(committed, piece);
    }
    partial = '';
  }

  void clear() {
    committed = '';
    partial = '';
  }

  String get display {
    if (partial.isEmpty) {
      return committed;
    }
    if (committed.isEmpty) {
      return partial;
    }
    return mergeReference(committed, partial);
  }
}

String _refNormWord(String word) {
  referenceNormalizedWords++;
  return word.toLowerCase().replaceAll(
    RegExp(r'^[^a-z0-9åäöé]+|[^a-z0-9åäöé]+$'),
    '',
  );
}

bool _refIsPrefix(List<String> words, List<String> prefix) {
  if (prefix.length > words.length) {
    return false;
  }
  return _refWordsEqual(words.sublist(0, prefix.length), prefix);
}

int _refIndexOfWords(List<String> haystack, List<String> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return -1;
  }
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    if (_refWordsEqual(haystack.sublist(i, i + needle.length), needle)) {
      return i;
    }
  }
  return -1;
}

bool _refWordsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

int _refMin(int a, int b) => a < b ? a : b;