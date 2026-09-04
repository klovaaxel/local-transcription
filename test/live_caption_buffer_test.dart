import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/live_caption_buffer.dart';

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
    final buffer = LiveCaptionBuffer()
      ..commit('hej alla barn vi tar rast');
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
}
