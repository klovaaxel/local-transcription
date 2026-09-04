import 'dart:io';
import 'dart:typed_data';

/// 44-byte canonical PCM WAV header. [WavFileSink] writes it, and
/// [WavChunker] puts a fresh one in front of every uploaded part.
Uint8List wavHeader({
  required int dataBytes,
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final buffer = BytesBuilder(copy: false);
  void ascii(String s) => buffer.add(s.codeUnits);
  void u16(int v) {
    buffer.add([v & 0xff, (v >> 8) & 0xff]);
  }

  void u32(int v) {
    buffer.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  }

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  ascii('data');
  u32(dataBytes);
  return buffer.toBytes();
}

/// What the `fmt ` and `data` chunks of a WAV file say.
class WavInfo {
  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  int get blockAlign => channels * bitsPerSample ~/ 8;
  int get byteRate => sampleRate * blockAlign;

  Duration get duration {
    if (byteRate <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: dataLength * 1000 ~/ byteRate);
  }
}

class WavFormatException implements Exception {
  WavFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Walks the RIFF chunk list of [bytes] (the head of a WAV file).
///
/// `data` is the last chunk a recorder writes, so its declared length can be
/// zero or stale after a crash; callers pass [fileLength] and the rest of the
/// file is treated as audio in that case.
WavInfo parseWavHeader(Uint8List bytes, {required int fileLength}) {
  final view = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw WavFormatException('Filen är inte en WAV-fil.');
  }

  var offset = 12;
  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      bitsPerSample = view.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (sampleRate == null || channels == null || bitsPerSample == null) {
        throw WavFormatException('WAV-filen saknar formatinformation.');
      }
      final declared = size;
      final available = fileLength - body;
      final length = declared > 0 && declared <= available
          ? declared
          : (available > 0 ? available : 0);
      return WavInfo(
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
        dataOffset: body,
        dataLength: length,
      );
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw WavFormatException('WAV-filen saknar ljuddata.');
}

/// Reads [WavInfo] from disk without loading the audio.
Future<WavInfo> readWavInfo(File file) async {
  final length = await file.length();
  final raf = await file.open();
  try {
    final head = await raf.read(length < 4096 ? length : 4096);
    return parseWavHeader(head, fileLength: length);
  } finally {
    await raf.close();
  }
}
