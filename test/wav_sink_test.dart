import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/wav_sink.dart';

void main() {
  test('close patches the header without truncating PCM', () async {
    final file = File(
      '${Directory.systemTemp.path}/lecture_wav_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    final sink = WavFileSink(file);
    await sink.open();
    sink.addPcm16(Uint8List.fromList(List<int>.filled(32000, 1)));
    await sink.close();

    final bytes = await file.readAsBytes();
    expect(bytes.length, 44 + 32000);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(bytes.sublist(44).every((b) => b == 1), isTrue);
  });
}
