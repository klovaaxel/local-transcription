import 'dart:io';
import 'dart:typed_data';

import 'wav_format.dart';

/// 16-bit PCM WAV writer (mono). Header sizes are patched on [close].
class WavFileSink {
  WavFileSink(this.file, {this.sampleRate = 16000, this.channels = 1});

  final File file;
  final int sampleRate;
  final int channels;

  IOSink? _sink;
  int _dataBytes = 0;

  Future<void> open() async {
    await file.parent.create(recursive: true);
    _sink = file.openWrite();
    _sink!.add(_header(0));
  }

  void addPcm16(Uint8List bytes) {
    _sink?.add(bytes);
    _dataBytes += bytes.length;
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    final raf = await file.open(mode: FileMode.append);
    await raf.setPosition(0);
    await raf.writeFrom(_header(_dataBytes));
    await raf.flush();
    await raf.close();
  }

  Uint8List _header(int dataBytes) {
    return wavHeader(
      dataBytes: dataBytes,
      sampleRate: sampleRate,
      channels: channels,
    );
  }
}
