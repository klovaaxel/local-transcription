import 'dart:io';
import 'dart:typed_data';

import 'wav_format.dart';

/// Cuts a long recording into upload-sized WAV parts.
///
/// A 45-minute lecture at 16 kHz mono is ~86 MB, well past what a hosted
/// transcription endpoint accepts in one request. Each part gets its own
/// 44-byte header so the provider sees a normal WAV, and parts overlap so a
/// sentence that lands on a boundary is not lost — [transcript_merge] drops
/// the restated text when the parts are joined.
class WavChunker {
  WavChunker._(this.file, this.info, this.partBytes, this.overlapBytes);

  /// 10 minutes of 16 kHz mono PCM is ~19 MB — under the 25 MB limit that
  /// Whisper-compatible endpoints commonly enforce.
  static const defaultPart = Duration(minutes: 10);
  static const defaultOverlap = Duration(seconds: 5);

  static Future<WavChunker> open(
    File file, {
    Duration part = defaultPart,
    Duration overlap = defaultOverlap,
  }) async {
    final info = await readWavInfo(file);
    final align = info.blockAlign <= 0 ? 2 : info.blockAlign;
    if (info.dataLength < align) {
      throw WavFormatException('Inspelningen är tom.');
    }
    int aligned(Duration d) {
      final bytes = info.byteRate * d.inMilliseconds ~/ 1000;
      return (bytes ~/ align) * align;
    }

    final partBytes = aligned(part).clamp(align, info.dataLength);
    final overlapBytes = aligned(overlap).clamp(0, partBytes ~/ 4);
    return WavChunker._(file, info, partBytes, overlapBytes);
  }

  final File file;
  final WavInfo info;
  final int partBytes;
  final int overlapBytes;

  /// Byte ranges into the `data` chunk, in order.
  List<({int start, int length})> get ranges {
    final out = <({int start, int length})>[];
    final step = partBytes - overlapBytes;
    var start = 0;
    while (start < info.dataLength) {
      final length = (info.dataLength - start).clamp(0, partBytes);
      out.add((start: start, length: length));
      if (start + length >= info.dataLength) {
        break;
      }
      start += step <= 0 ? partBytes : step;
    }
    return out;
  }

  int get count => ranges.length;

  /// The whole recording fits in one request.
  bool get isSingle => count <= 1;

  /// Part [index] as a standalone WAV file in memory.
  Future<Uint8List> part(int index) async {
    final range = ranges[index];
    final raf = await file.open();
    try {
      await raf.setPosition(info.dataOffset + range.start);
      final pcm = await raf.read(range.length);
      final header = wavHeader(
        dataBytes: pcm.length,
        sampleRate: info.sampleRate,
        channels: info.channels,
        bitsPerSample: info.bitsPerSample,
      );
      final out = Uint8List(header.length + pcm.length)
        ..setAll(0, header)
        ..setAll(header.length, pcm);
      return out;
    } finally {
      await raf.close();
    }
  }
}
