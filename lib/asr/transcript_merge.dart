import 'dart:math';

/// Merges overlapping Whisper window transcripts by dropping repeated words.
///
/// VAD pieces and 20 s rolling windows often restate a tail (or earlier
/// context after a pause). Suffix-prefix overlap is not enough: a window can
/// start with older words that are not the current suffix.
String mergeOverlappingTranscript(String previous, String next) {
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
  final prevNorm = [for (final w in prevWords) _normWord(w)];
  final nextNorm = [for (final w in nextWords) _normWord(w)];

  if (_indexOfWords(prevNorm, nextNorm) >= 0) {
    return left;
  }
  if (_isPrefix(nextNorm, prevNorm)) {
    return right;
  }

  for (var n = min(prevNorm.length, nextNorm.length); n >= 1; n--) {
    final idx = _indexOfWords(nextNorm, prevNorm.sublist(prevNorm.length - n));
    if (idx == 0) {
      return [...prevWords, ...nextWords.sublist(n)].join(' ');
    }
    if (idx > 0 && n >= 2) {
      return [...prevWords, ...nextWords.sublist(idx + n)].join(' ');
    }
  }

  return '$left $right';
}

String _normWord(String word) {
  return word.toLowerCase().replaceAll(
    RegExp(r'^[^a-z0-9åäöé]+|[^a-z0-9åäöé]+$'),
    '',
  );
}

bool _isPrefix(List<String> words, List<String> prefix) {
  if (prefix.length > words.length) {
    return false;
  }
  return _wordsEqual(words.sublist(0, prefix.length), prefix);
}

int _indexOfWords(List<String> haystack, List<String> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return -1;
  }
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    if (_wordsEqual(haystack.sublist(i, i + needle.length), needle)) {
      return i;
    }
  }
  return -1;
}

bool _wordsEqual(List<String> a, List<String> b) {
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
