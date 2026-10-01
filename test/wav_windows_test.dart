import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/wav_format.dart';
import 'package:lecture_local/asr/wav_sink.dart';
import 'package:lecture_local/asr/wav_windows.dart';

/// 16 kHz mono 16-bit: one second is 32000 bytes.
const _bytesPerSecond = 32000;

/// The sample at index [i] of the synthetic lectures below. Distinct often
/// enough that the first value of a window says where that window started.
int _int16(int i) => (i % 30011) - 15011;

double _sample(int i) => _int16(i) / 32768.0;

Uint8List _pcm(int count) {
  final data = ByteData(count * 2);
  for (var i = 0; i < count; i++) {
    data.setInt16(i * 2, _int16(i), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A recording left behind by a process that died mid-lecture: a valid header
/// still declaring zero audio bytes, followed by the PCM it never got to
/// declare. This is the shape `WavFileSink.open` + a kill - no `close` - puts
/// on disk, and the reason the local path used to transcribe it to nothing.
File _crashed(Directory dir, String name, int seconds) {
  final header = wavHeader(dataBytes: 0);
  final pcm = _pcm(seconds * 16000);
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(
    Uint8List(header.length + pcm.length)
      ..setAll(0, header)
      ..setAll(header.length, pcm),
  );
  return file;
}

Future<File> _recording(Directory dir, String name, int seconds) async {
  final file = File('${dir.path}/$name');
  final sink = WavFileSink(file);
  await sink.open();
  sink.addPcm16(_pcm(seconds * 16000));
  await sink.close();
  return file;
}

Future<List<Float32List>> _windows(File file) async {
  final out = <Float32List>[];
  await readWavWindows(file, (samples, sampleRate) {
    expect(sampleRate, 16000, reason: 'the file rate reaches the recognizer');
    out.add(samples);
    return true;
  });
  return out;
}

/// The loop `transcribeWindows` walked over a whole decoded clip before the
/// bounded reader existed, transcribed here verbatim and with the window and
/// hop spelled out rather than named. It is the baseline the reader has to
/// reproduce sample for sample: the geometry decides where a sentence is cut,
/// so moving it is a transcript-quality change, not a refactor.
List<Float32List> _wholeFileWindows(Float32List samples) {
  if (samples.length <= 20 * 16000) {
    return [samples];
  }
  final out = <Float32List>[];
  var offset = 0;
  while (offset < samples.length) {
    final end = (offset + 20 * 16000).clamp(0, samples.length);
    out.add(Float32List.fromList(samples.sublist(offset, end)));
    if (end >= samples.length) {
      break;
    }
    offset += 15 * 16000;
  }
  return out;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wav_windows');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('a recording killed before close reads back as audio', () async {
    final file = _crashed(dir, 'killed.wav', 60);

    final info = await readWavInfo(file);
    expect(
      info.dataLength,
      60 * _bytesPerSecond,
      reason: 'a zero header must not hide the PCM behind it',
    );

    final windows = await _windows(file);
    expect(
      windows.map((w) => w.length),
      [20 * 16000, 20 * 16000, 20 * 16000, 15 * 16000],
    );
    expect(windows.first.first, _sample(0));
    expect(
      windows.last.last,
      _sample(60 * 16000 - 1),
      reason: 'the tail of the lecture is audio too',
    );
  });

  test('the bounded reader reproduces the whole-file loop', () async {
    final file = await _recording(dir, 'lecture.wav', 60);

    expect(
      await _windows(file),
      _wholeFileWindows(pcm16ToFloat(_pcm(60 * 16000))),
      reason: 'same windows, same samples, same order',
    );
  });

  test('windows step 15 s and the last one is clamped to the clip', () {
    expect(windowOffsets(60 * 16000), [0, 15 * 16000, 30 * 16000, 45 * 16000]);
    expect(windowRange(0, 60 * 16000, 2), (start: 0, length: 20 * 16000 * 2));
    expect(
      windowRange(45 * 16000, 60 * 16000, 2),
      (start: 45 * 16000 * 2, length: 15 * 16000 * 2),
    );
  });

  test('a clip that fits in one window is read once, whole', () async {
    final file = await _recording(dir, 'short.wav', 5);

    expect(windowOffsets(5 * 16000), [0]);
    final windows = await _windows(file);
    expect(windows, hasLength(1));
    expect(windows.single, pcm16ToFloat(_pcm(5 * 16000)));
  });

  test('a walk stops as soon as the callback says so', () async {
    final file = await _recording(dir, 'cancelled.wav', 60);
    final seen = <Float32List>[];

    await readWavWindows(file, (samples, _) {
      seen.add(samples);
      // What the isolate does when `stop()` lands between two windows. This
      // clip is four windows, so asking for three proves the walk keeps going
      // past the first one and then honours the refusal -- an implementation
      // that stopped immediately would also satisfy a length-of-one assertion.
      return seen.length < 3;
    });

    expect(seen, hasLength(3));
  });

  test('a recording that is not 16-bit mono is refused', () async {
    final header = wavHeader(dataBytes: 64, channels: 2, bitsPerSample: 8);
    final file = File('${dir.path}/stereo.wav');
    file.writeAsBytesSync(
      Uint8List(header.length + 64)
        ..setAll(0, header)
        ..fillRange(header.length, header.length + 64, 7),
    );

    await expectLater(
      readWavWindows(file, (samples, _) => true),
      throwsA(isA<WavFormatException>()),
    );
  });

  test('pcm16 is little-endian and scaled by 32768', () {
    expect(
      pcm16ToFloat(Uint8List.fromList([0x00, 0x80, 0xff, 0x7f])),
      [-1.0, 32767 / 32768.0],
    );
  });
}
