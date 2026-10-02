import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/live_caption_buffer.dart';

import 'transcript_merge_reference.dart';

void main() {
  test('partial after a pause does not reprint committed speech', () {
    final buffer = LiveCaptionBuffer()
      ..commit('idag ska vi prata om addition och sen rast');
    buffer.setPartial(
      'hej allihopa idag ska vi prata om addition och sen rast och nya grejer',
    );
    expect(
      buffer.display,
      'idag ska vi prata om addition och sen rast och nya grejer',
    );
  });

  test('a restated window stays as replaceable partial', () {
    final buffer = LiveCaptionBuffer()..commit('hej alla barn vi tar rast');
    buffer.setPartial('hej alla barn vi tar rast');
    expect(buffer.display, 'hej alla barn vi tar rast');
    buffer.setPartial('och sen lunch');
    expect(buffer.display, 'hej alla barn vi tar rast och sen lunch');
  });

  test('commit clears the in-progress hypothesis', () {
    final buffer = LiveCaptionBuffer()
      ..setPartial('pågående')
      ..commit('klart');
    expect(buffer.partial, isEmpty);
    expect(buffer.display, 'klart');
  });

  // The buffer holds the word index now, and `display` merges the rolling
  // window's hypothesis against the committed text several times a second
  // without committing it. Both are new ways to be wrong about text the teacher
  // is reading, so the whole script is checked against the buffer as it was -
  // every partial and every commit, at the moment it happens.
  test('matches the previous buffer through a scripted lecture', () {
    final buffer = LiveCaptionBuffer();
    final reference = ReferenceCaptionBuffer();

    for (final (step, partial, commit) in _script) {
      if (partial != null) {
        buffer.setPartial(partial);
        reference.setPartial(partial);
      }
      expect(buffer.display, reference.display, reason: 'display at $step');
      expect(
        buffer.committed,
        reference.committed,
        reason: 'committed at $step',
      );
      expect(buffer.partial, reference.partial, reason: 'partial at $step');
      if (commit != null) {
        buffer.commit(commit);
        reference.commit(commit);
      }
    }
  });

  test('a previewed partial does not leak into the next commit', () {
    // `display` runs the same merge as `commit` against the same text. If the
    // words it derived were kept, the following commit would cut against a
    // hypothesis rather than against the committed transcript.
    final buffer = LiveCaptionBuffer()..commit('idag ska vi prata om addition');
    final reference = ReferenceCaptionBuffer()
      ..commit('idag ska vi prata om addition');
    for (final partial in [
      'idag ska vi prata om addition och sen rast',
      'om addition och sen rast och nya grejer',
      'nya grejer som vi inte pratat om ännu',
    ]) {
      buffer.setPartial(partial);
      reference.setPartial(partial);
      expect(buffer.display, reference.display, reason: partial);
    }

    buffer.commit('och sen rast');
    reference.commit('och sen rast');
    expect(buffer.committed, reference.committed);
    expect(buffer.partial, isEmpty);
  });

  test('clear starts a new lecture from nothing', () {
    final buffer = LiveCaptionBuffer()..commit('första föreläsningen');
    final reference = ReferenceCaptionBuffer()..commit('första föreläsningen');
    buffer
      ..setPartial('pågående')
      ..clear();
    reference
      ..setPartial('pågående')
      ..clear();
    expect(buffer.display, reference.display);
    expect(buffer.committed, isEmpty);

    // Same words as the lecture that was cleared: the cleared index must not
    // hand them back as if they had been merged.
    buffer.commit('första föreläsningen');
    reference.commit('första föreläsningen');
    expect(buffer.committed, reference.committed);
    expect(buffer.committed, 'första föreläsningen');
  });
}

/// One lecture as the recognizer would deliver it: a committed piece, then the
/// rolling window's re-readings of the same audio before it is committed, then
/// the restatement a window produces after a pause.
const _script = <(String, String?, String?)>[
  ('first piece', null, 'idag ska vi prata om addition'),
  ('window re-reads the piece', 'idag ska vi prata om addition', null),
  ('window extends it', 'idag ska vi prata om addition och', null),
  ('commit the window', null, 'idag ska vi prata om addition och sen rast'),
  (
    'a pause, then the window starts from the top',
    'hej allihopa idag ska vi prata om addition och sen rast',
    null,
  ),
  (
    'and goes on with new words',
    'hej allihopa idag ska vi prata om addition och sen rast och nya grejer',
    null,
  ),
  (
    'commit after the pause',
    null,
    'hej allihopa idag ska vi prata om addition och sen rast och nya grejer',
  ),
  (
    'same words, other case and punctuation',
    'Idag ska vi prata om addition. Och sen rast!',
    null,
  ),
  ('a punctuation-only window', '. ,', null),
  ('whitespace only', '  \t ', null),
  ('empty commit', null, '   '),
  ('a single word', null, 'multiplikation'),
  ('a repeated word', 'multiplikation multiplikation', null),
  (
    'the whole transcript restated',
    'idag ska vi prata om addition och sen rast och nya grejer multiplikation',
    null,
  ),
  ('the next piece', null, 'räkna med tabell tre'),
];
