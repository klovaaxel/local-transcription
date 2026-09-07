import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/transcript_merge.dart';

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
}
