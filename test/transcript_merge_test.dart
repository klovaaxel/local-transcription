import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/transcript_merge.dart';

import 'transcript_merge_reference.dart';

/// Words a Swedish lecture really leans on, duplicates included: the merge sees
/// the same short word again and again, and a corpus of distinct words would
/// never make it look for an overlap twice.
const _words = [
  'och',
  'att',
  'det',
  'som',
  'en',
  'är',
  'för',
  'med',
  'på',
  'av',
  'vi',
  'ni',
  'kan',
  'ska',
  'kommer',
  'till',
  'barnen',
  'läraren',
  'hej',
  'räkna',
  'räknesättet',
  'addition',
  'subtraktion',
  'multiplikation',
  'division',
  'tabell',
  'problemet',
  'uppgift',
  'uppgifterna',
  'provet',
  'läxan',
  'torsdag',
  'fredag',
  'måndag',
  'kapitlet',
  'sidan',
  'nummer',
  'och',
  'som',
  'att',
  'räkna',
  'ni',
  'vi',
  'en',
];

/// Deterministic lecture text of [wordCount] words, each carrying its own index
/// so no two positions hold the same words. A merge into this has to search
/// every overlap length and find nothing, which is the case that was quadratic.
String _lecture(int wordCount) {
  final out = StringBuffer();
  for (var i = 0; i < wordCount; i++) {
    out.write('${_words[i % _words.length]}$i ');
  }
  return out.toString().trim();
}

/// [wordCount] words of lecture speech, roughly as [Random] shuffling the
/// vocabulary would produce them.
List<String> _speech(Random random, int wordCount) {
  return [
    for (var i = 0; i < wordCount; i++) _words[random.nextInt(_words.length)],
  ];
}

String _joined(List<String> words) => words.join(' ');

void main() {
  test('keeps unique continuation', () {
    expect(
      mergeOverlappingTranscript('hej alla barn', 'barn vi tar rast'),
      'hej alla barn vi tar rast',
    );
  });

  test('joins when there is no overlap', () {
    expect(mergeOverlappingTranscript('första', 'andra'), 'första andra');
  });

  test('ignores empty next window', () {
    expect(mergeOverlappingTranscript('kvar', '  '), 'kvar');
  });

  test('keeps previous when the window restates committed speech', () {
    expect(
      mergeOverlappingTranscript(
        'hej alla barn vi tar rast',
        'alla barn vi tar rast',
      ),
      'hej alla barn vi tar rast',
    );
  });

  test('takes the longer decode when it starts with the committed text', () {
    expect(
      mergeOverlappingTranscript(
        'hej alla barn vi tar rast',
        'Hej alla barn vi tar rast och sen lunch.',
      ),
      'Hej alla barn vi tar rast och sen lunch.',
    );
  });

  test('drops earlier window context after a pause and keeps new words', () {
    expect(
      mergeOverlappingTranscript(
        'idag ska vi prata om addition och sen rast',
        'hej allihopa idag ska vi prata om addition och sen rast och nya grejer',
      ),
      'idag ska vi prata om addition och sen rast och nya grejer',
    );
  });

  test('prefers a later restatement over a one-word suffix hit', () {
    expect(
      mergeOverlappingTranscript(
        'vi tar rast nu',
        'nu vi tar rast nu och lunch',
      ),
      'vi tar rast nu och lunch',
    );
  });

  test(
    'ignores punctuation when the new decode starts with the committed text',
    () {
      expect(
        mergeOverlappingTranscript(
          'vi tar rast nu barnen',
          'Vi tar rast nu. Barnen går ut',
        ),
        'Vi tar rast nu. Barnen går ut',
      );
    },
  );

  // The merge is what writes the transcript the teacher reads and the brief is
  // built from, and the quality baselines in feedback/quality/SCORES.md were
  // measured against the implementation below. Faster is only allowed to mean
  // the same words in the same order.
  test('matches the previous implementation on every hand-written case', () {
    for (final (name, previous, next) in _corpus) {
      expect(
        mergeOverlappingTranscript(previous, next),
        mergeReference(previous, next),
        reason: name,
      );
    }
  });

  test('matches the previous implementation on overlap after overlap', () {
    // The geometry the merge is actually asked about: a window that shares
    // anywhere from nothing to its whole length with the text before it.
    final random = Random(4711);
    for (var overlap = 0; overlap <= 30; overlap++) {
      final previous = _speech(random, 60);
      final next = [...previous.sublist(60 - overlap), ..._speech(random, 25)];
      expect(
        mergeOverlappingTranscript(_joined(previous), _joined(next)),
        mergeReference(_joined(previous), _joined(next)),
        reason: 'overlap of $overlap words',
      );
    }
  });

  test('matches the previous implementation on randomized windows', () {
    final random = Random(20261001);
    for (var run = 0; run < 600; run++) {
      final previous = _speech(random, random.nextInt(120));
      final next = switch (random.nextInt(5)) {
        // New speech, nothing restated.
        0 => _speech(random, random.nextInt(60)),
        // The tail restated, as a 15 s hop into a 20 s window does.
        1 => [
          ...previous.sublist(
            previous.length - random.nextInt(previous.length + 1),
          ),
          ..._speech(random, random.nextInt(30)),
        ],
        // A restatement from earlier in the lecture, as a window does after a
        // pause: older words first, then the tail, then new speech.
        2 => [
          ...previous.take(random.nextInt(previous.length + 1)),
          ..._speech(random, random.nextInt(20)),
          ..._speech(random, random.nextInt(30)),
        ],
        // The same words decoded differently: case and punctuation move.
        3 => [
          for (final word in previous) word.toUpperCase(),
          ..._speech(random, random.nextInt(20)),
        ],
        // Words dropped, as a lossy decode does.
        _ => [
          for (var i = 0; i < previous.length; i++)
            if (random.nextInt(8) != 0) previous[i],
          ..._speech(random, random.nextInt(20)),
        ],
      };
      expect(
        mergeOverlappingTranscript(_joined(previous), _joined(next)),
        mergeReference(_joined(previous), _joined(next)),
        reason: 'run $run of ${previous.length} previous words',
      );
    }
  });

  test('a merge into a 9,000-word lecture normalizes the window alone', () {
    final committed = _lecture(9000);
    final committedWords = committed.split(' ');
    // A 20 s window on a 15 s hop: the tail restated, then 15 s of new speech.
    final window = _joined([
      ...committedWords.sublist(committedWords.length - 25),
      ..._speech(Random(7), 25),
    ]);
    final windowWords = window.split(' ').length;

    resetReferenceWork();
    final expected = mergeReference(committed, window);
    expect(
      referenceNormalizedWords,
      greaterThan(9000),
      reason: 'the old merge re-derived the whole lecture per caption',
    );

    final transcript = LiveTranscript()..adopt(committed);
    MergeStats? cold;
    final merged = transcript.merge(window, onStats: (stats) => cold = stats);
    expect(merged, expected, reason: 'the text is byte-identical');
    expect(
      cold!.normalizedWords,
      windowWords,
      reason: 'only the new window is normalized',
    );

    MergeStats? warm;
    transcript.merge(
      '${window.split(' ').sublist(20).join(' ')} och lite till',
      onStats: (stats) => warm = stats,
    );
    expect(
      warm!.normalizedWords,
      lessThanOrEqualTo(windowWords),
      reason: 'the next caption keeps the index instead of rebuilding it',
    );
  });

  test('a 45-minute lecture normalizes each word a couple of times, not per caption', () {
    // 180 windows of 50 words sharing 10: the shape of a 45-minute lecture, and
    // the ~9,000 words the review measured.
    const windows = 180;
    const shared = 10;
    const fresh = 40;
    final random = Random(99);
    var previous = _speech(random, 50);
    final pieces = <List<String>>[previous];
    for (var i = 0; i < windows; i++) {
      previous = [
        ...previous.sublist(previous.length - shared),
        ..._speech(random, fresh),
      ];
      pieces.add(previous);
    }

    resetReferenceWork();
    final expected = ReferenceCaptionBuffer();
    expected.commit(_joined(pieces[0]));
    for (var i = 1; i < pieces.length; i++) {
      expected.commit(_joined(pieces[i].sublist(shared)));
    }
    final referenceCost = referenceNormalizedWords;

    var liveCost = 0;
    var unplaced = 0;
    // The real shape, which is the opposite way round from what this first
    // assumed: `previous` accumulates the lecture and `next` is one window.
    // `LiveCaptionBuffer.commit` is handed a VAD piece and the buffer carries
    // the rest, so the first window is adopted and every later merge carries
    // only what that window added. Feeding the whole lecture in as `next` would
    // make every merge cost the whole lecture, which is the thing being fixed.
    final transcript = LiveTranscript()..adopt(_joined(pieces[0]));
    for (var i = 1; i < pieces.length; i++) {
      final window = _joined(pieces[i].sublist(shared));
      transcript.merge(
        window,
        onStats: (stats) {
          liveCost += stats.normalizedWords;
          unplaced += stats.windowsCompared;
        },
      );
    }

    expect(transcript.text, expected.committed, reason: 'same transcript');
    expect(
      referenceCost,
      greaterThan(500000),
      reason: 'the old path re-derived the growing lecture per window',
    );
    expect(
      liveCost,
      lessThan(3 * 9000),
      reason: 'the cached path derives every word about twice',
    );
    // The overlap search tries the longest overlap first, so a window that only
    // restates ten words still costs the lengths above ten first. What matters
    // is that the search is bounded by the window and not by the lecture: the
    // old path's cost grew with every word already committed.
    expect(
      unplaced,
      lessThan(pieces.length * fresh),
      reason: 'the overlap search is bounded by the window, not the lecture',
    );
  });

  test('a merge that finds nothing gives up after trying every overlap', () {
    final transcript = LiveTranscript()..adopt(_lecture(500));
    MergeStats? stats;
    transcript.merge('helt nya ord', onStats: (s) => stats = s);

    expect(stats!.overlapWords, 0, reason: 'nothing lined up');
    expect(
      stats!.windowsCompared,
      3,
      reason: 'three words in, three lengths tried',
    );
  });

  test('a previewed window leaves the committed text and its index alone', () {
    // `LiveCaptionBuffer.display` merges the rolling window's hypothesis against
    // the committed transcript several times a second and throws the result
    // away. It reuses the same word index as `commit`, so it has to leave both
    // the text and the derivation exactly as it found them - otherwise the next
    // commit would cut against a hypothesis.
    final committed = _lecture(200);
    final window =
        '${committed.split(' ').sublist(190).join(' ')} och lite till';
    final next = 'lunch vid halv tolv';

    final transcript = LiveTranscript()..adopt(committed);
    MergeStats? preview;
    expect(
      transcript.preview(window, onStats: (stats) => preview = stats),
      mergeReference(committed, window),
      reason: 'a preview merges the same way a commit does',
    );
    expect(transcript.text, committed, reason: 'the committed text stands');
    expect(preview!.normalizedWords, window.split(' ').length);

    MergeStats? committedStats;
    final merged = transcript.merge(
      next,
      onStats: (stats) => committedStats = stats,
    );
    expect(merged, mergeReference(committed, next));
    expect(
      committedStats!.normalizedWords,
      next.split(' ').length,
      reason:
          'the index survived the preview, so only the new words are derived',
    );
  });
}

/// The hand-written corpus, named so a failure says which shape broke: overlap
/// at every length, restatement after a pause, no overlap, full restatement,
/// punctuation and case variants, empty and whitespace-only input, single
/// words, and the words `String.split(RegExp(r'\s+'))` breaks on.
List<(String, String, String)> get _corpus => [
  ('both empty', '', ''),
  ('empty previous', '', 'hej alla barn'),
  ('empty next', 'hej alla barn', ''),
  ('whitespace-only previous', ' \t\r\n ', 'hej'),
  ('whitespace-only next', 'hej', ' \t\r\n '),
  ('leading and trailing space', '  hej alla barn  ', '  barn vi  '),
  ('one word, same', 'en', 'en'),
  ('one word, other case', 'en', 'EN'),
  ('one word, punctuated', 'en', 'en.'),
  ('one word, disjoint', 'en', 'två'),
  ('one word, repeated inside', 'ett tre', 'tre'),
  ('identical repeat', 'hej alla barn', 'hej alla barn'),
  ('identical repeat, other case', 'hej alla barn', 'Hej Alla Barn'),
  ('identical repeat, punctuated', 'hej alla barn', 'hej, alla barn!'),
  ('next extends previous', 'hej alla barn', 'hej alla barn och sen lunch'),
  (
    'next restates the tail',
    'hej alla barn vi tar rast',
    'alla barn vi tar rast',
  ),
  (
    'next restates from the top after a pause',
    'idag ska vi prata om addition och sen rast',
    'hej allihopa idag ska vi prata om addition och sen rast och nya grejer',
  ),
  (
    'later restatement beats a one-word suffix',
    'vi tar rast nu',
    'nu vi tar rast nu och lunch',
  ),
  ('no overlap', 'första', 'andra'),
  ('punctuation-only words', 'hej . alla barn', 'alla barn'),
  ('punctuation-only both sides', '. ,', '. , nytt'),
  ('repeated punctuation', 'hej -- alla barn', 'alla barn'),
  ('digits inside words', 'rad 1: hej', 'rad 1: hej och 2: hej'),
  ('double space', 'hej  alla barn', 'alla barn'),
  ('newline inside', 'hej\nalla barn', 'alla barn'),
  ('tab inside', 'hej\talla barn', 'alla\tbarn'),
  ('carriage return and newline', 'hej\r\nalla barn', 'alla barn'),
  ('vertical tab and form feed', 'hej\valla\f barn', 'alla barn'),
  ('whitespace on both sides of the overlap', 'hej  alla  barn', 'alla  barn'),
  ('a pattern that matches more than once', 'a b a b', 'a b c'),
  ('a pattern that matches more than once, long', 'en ö en ö en ö', 'en ö två'),
  ('no overlap in a long lecture', _lecture(300), 'helt nya ord här'),
  (
    'tail overlap in a long lecture',
    _lecture(300),
    '${_lecture(300).split(' ').sublist(275).join(' ')} och sen lite till',
  ),
  (
    'restated head in a long lecture',
    _lecture(300),
    '${_lecture(300).split(' ').take(12).join(' ')} och nya grejer',
  ),
  ('next much longer than previous', 'kort', _lecture(60)),
  ('previous much longer than next', _lecture(60), 'kort'),
  ('swedish letters with punctuation', 'räkna med ÅÄÖ', 'RÄKNA med åäö.'),
];
