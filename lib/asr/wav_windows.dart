import 'dart:io';
import 'dart:typed_data';

import 'wav_format.dart';

/// Decode window and hop for a finished recording, in samples at the 16 kHz the
/// recognizer runs on: 20 s and 15 s, so consecutive windows share 5 s. The
/// live caption window and the post-lecture file walk both come from here --
/// the geometry decides where a sentence gets cut, and what the transcript
/// quality numbers in `feedback/quality/SCORES.md` were measured on, so the two
/// paths must not be free to drift apart.
///
/// Only the file walk uses [windowOffsets]. The live path holds one rolling
/// window of the same length and steps forward by [hopSamples]; it does not
/// walk offsets, and unifying the two is a trap rather than a tidy-up.
const windowSamples = 20 * 16000;
const hopSamples = 15 * 16000;

/// Sample offsets of the decode windows for a clip of [totalSamples], in order.
/// A window runs [windowSamples] past its offset, clamped to the end of the
/// clip, and the walk stops as soon as one of them reaches the end, so the tail
/// is decoded once and not again on a step that would repeat it.
Iterable<int> windowOffsets(int totalSamples) sync* {
  var offset = 0;
  while (offset < totalSamples) {
    yield offset;
    if (offset + windowSamples >= totalSamples) {
      return;
    }
    offset += hopSamples;
  }
}

/// Byte range of the window starting at [offsetSamples], inside a `data` chunk
/// of [blockAlign]-byte frames holding [totalSamples] samples: byte for byte
/// the slice `samples.sublist(offset, end)` produced back when the whole clip
/// sat in memory.
({int start, int length}) windowRange(
  int offsetSamples,
  int totalSamples,
  int blockAlign,
) {
  final end = (offsetSamples + windowSamples).clamp(0, totalSamples);
  return (
    start: offsetSamples * blockAlign,
    length: (end - offsetSamples) * blockAlign,
  );
}

/// Reads a recording off disk one decode window at a time, handing each window
/// to [onWindow] as floats; returning false from [onWindow] stops the walk.
///
/// Decoding the whole clip and sublisting it costs a 45-minute lecture twice
/// over: 86 MB of PCM expanded to ~173 MB of floats, of which the windowing
/// then uses 20 s at a time. Going through [readWavInfo] fixes the other half
/// too -- a lecture killed before `WavFileSink.close` patched the header still
/// declares zero audio bytes, and a reader that believes that returns silence.
Future<void> readWavWindows(
  File file,
  bool Function(Float32List samples, int sampleRate) onWindow,
) async {
  final info = await readWavInfo(file);
  if (info.channels != 1 || info.bitsPerSample != 16) {
    // pcm16ToFloat reads 16-bit little-endian frames and nothing else, so any
    // other layout would reach the teacher as noise instead of an error.
    throw WavFormatException(
      'Inspelningen är inte 16-bitars mono och kan inte transkriberas.',
    );
  }
  final totalSamples = info.dataLength ~/ info.blockAlign;
  final raf = await file.open();
  try {
    for (final offset in windowOffsets(totalSamples)) {
      final range = windowRange(offset, totalSamples, info.blockAlign);
      await raf.setPosition(info.dataOffset + range.start);
      final samples = pcm16ToFloat(await _readFully(raf, range.length));
      if (!onWindow(samples, info.sampleRate)) {
        return;
      }
    }
  } finally {
    await raf.close();
  }
}

/// 16-bit little-endian PCM in, the float range sherpa decodes. The live
/// captions and the file walk feed it the same layout, because `WavFileSink`
/// writes the same layout.
Float32List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Fills [length] bytes from the current position. `RandomAccessFile.read` is
/// allowed to come up short, and a window truncated in the middle would quietly
/// drop the end of a sentence -- an overlap exists to protect a seam, not to
/// have the file decide how much of it survives.
Future<Uint8List> _readFully(RandomAccessFile raf, int length) async {
  final out = Uint8List(length);
  var read = 0;
  while (read < length) {
    final chunk = await raf.read(length - read);
    if (chunk.isEmpty) {
      break;
    }
    out.setRange(read, read + chunk.length, chunk);
    read += chunk.length;
  }
  return read == length ? out : Uint8List.sublistView(out, 0, read);
}
