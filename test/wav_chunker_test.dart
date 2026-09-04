import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/wav_chunker.dart';
import 'package:lecture_local/asr/wav_format.dart';
import 'package:lecture_local/asr/wav_sink.dart';

/// 16 kHz mono 16-bit: one second is 32000 bytes.
const _bytesPerSecond = 32000;

Future<File> _recording(Directory dir, Duration length) async {
  final file = File('${dir.path}/audio.wav');
  final sink = WavFileSink(file);
  await sink.open();
  final second = Uint8List(_bytesPerSecond);
  for (var i = 0; i < second.length; i++) {
    second[i] = i % 251;
  }
  for (var i = 0; i < length.inSeconds; i++) {
    sink.addPcm16(second);
  }
  await sink.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wav_chunker');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('reads back what the sink wrote', () async {
    final file = await _recording(dir, const Duration(seconds: 3));
    final info = await readWavInfo(file);

    expect(info.sampleRate, 16000);
    expect(info.channels, 1);
    expect(info.bitsPerSample, 16);
    expect(info.dataOffset, 44);
    expect(info.dataLength, 3 * _bytesPerSecond);
    expect(info.duration, const Duration(seconds: 3));
  });

  test('a short lecture is a single part', () async {
    final file = await _recording(dir, const Duration(seconds: 5));
    final chunker = await WavChunker.open(file);

    expect(chunker.isSingle, isTrue);
    expect(chunker.count, 1);
    final part = await chunker.part(0);
    expect(part.length, 44 + 5 * _bytesPerSecond);
  });

  test('a long lecture is cut into overlapping parts that cover it all',
      () async {
    final file = await _recording(dir, const Duration(seconds: 30));
    final chunker = await WavChunker.open(
      file,
      part: const Duration(seconds: 10),
      overlap: const Duration(seconds: 2),
    );

    expect(chunker.count, greaterThan(1));

    final ranges = chunker.ranges;
    expect(ranges.first.start, 0);
    expect(
      ranges.last.start + ranges.last.length,
      30 * _bytesPerSecond,
      reason: 'the tail of the lecture must be uploaded too',
    );
    for (var i = 1; i < ranges.length; i++) {
      expect(
        ranges[i].start,
        lessThan(ranges[i - 1].start + ranges[i - 1].length),
        reason: 'parts overlap so a sentence on the seam survives',
      );
    }
  });

  test('every part is a WAV a provider can read', () async {
    final file = await _recording(dir, const Duration(seconds: 25));
    final chunker = await WavChunker.open(
      file,
      part: const Duration(seconds: 10),
      overlap: const Duration(seconds: 2),
    );

    for (var i = 0; i < chunker.count; i++) {
      final bytes = await chunker.part(i);
      final info = parseWavHeader(bytes, fileLength: bytes.length);
      expect(info.sampleRate, 16000);
      expect(info.dataOffset, 44);
      expect(info.dataLength, bytes.length - 44);
      expect(info.dataLength, greaterThan(0));
    }
  });

  test('a truncated data size falls back to the rest of the file', () async {
    final file = await _recording(dir, const Duration(seconds: 2));
    // A crash mid-lecture leaves the header saying zero bytes of audio.
    final raf = await file.open(mode: FileMode.append);
    await raf.setPosition(40);
    await raf.writeFrom([0, 0, 0, 0]);
    await raf.close();

    final info = await readWavInfo(file);
    expect(info.dataLength, 2 * _bytesPerSecond);
  });

  test('a recording with no audio is refused, not a crash', () async {
    final file = await _recording(dir, Duration.zero);
    await expectLater(
      WavChunker.open(file),
      throwsA(isA<WavFormatException>()),
    );
  });

  test('a non-WAV file is refused', () async {
    final file = File('${dir.path}/notes.txt');
    await file.writeAsString('inte ljud');
    await expectLater(readWavInfo(file), throwsA(isA<WavFormatException>()));
  });
}
