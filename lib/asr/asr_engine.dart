import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sox;

import 'live_caption_buffer.dart';
import 'model_downloader.dart';
import 'pcm_level.dart';

class CaptionEvent {
  const CaptionEvent(this.text, {this.authoritative = false});

  final String text;
  final bool authoritative;
}

class AsrEngine {
  AsrEngine();

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _events;
  StreamController<CaptionEvent>? _captions;
  Completer<void>? _configured;
  Completer<String>? _pendingText;
  Completer<void>? _disposed;

  Stream<CaptionEvent> get captions =>
      _captions?.stream ?? const Stream.empty();

  /// True between [start] and [stop]. Lets a caller reuse a loaded model
  /// instead of paying the load twice.
  bool get running => _commands != null;

  Future<void> start(AsrPaths paths) async {
    await stop();
    _captions = StreamController<CaptionEvent>.broadcast();
    _configured = Completer<void>();
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_asrIsolateMain, ready.sendPort);
    _commands = await ready.first as SendPort;
    ready.close();
    _events?.close();
    _events = ReceivePort();
    _events!.listen(_onEvent);
    _commands!.send({
      'cmd': 'listen',
      'port': _events!.sendPort,
    });
    _commands!.send({
      'cmd': 'configure',
      'encoder': paths.encoder,
      'decoder': paths.decoder,
      'tokens': paths.tokens,
      'vad': paths.vad,
    });
    await _configured!.future.timeout(const Duration(seconds: 120));
  }

  void pushPcm16(Uint8List bytes) {
    _commands?.send({'cmd': 'pcm', 'bytes': bytes});
  }

  Future<String> flushLive() async {
    _pendingText = Completer<String>();
    _commands?.send({'cmd': 'flush'});
    return _pendingText!.future.timeout(const Duration(minutes: 10));
  }

  Future<String> transcribeFile(String wavPath) async {
    _pendingText = Completer<String>();
    _commands?.send({'cmd': 'file', 'path': wavPath});
    return _pendingText!.future.timeout(const Duration(hours: 4));
  }

  Future<void> stop() async {
    final isolate = _isolate;
    final commands = _commands;
    if (commands != null) {
      _disposed = Completer<void>();
      commands.send({'cmd': 'dispose'});
      try {
        await _disposed!.future.timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _commands = null;
    _events?.close();
    _events = null;
    await _captions?.close();
    _captions = null;
  }

  void _onEvent(dynamic message) {
    if (message is! Map) {
      return;
    }
    final type = message['type'] as String?;
    if (type == 'ready') {
      _configured?.complete();
    } else if (type == 'error') {
      final err = StateError(message['message'] as String? ?? 'ASR-fel');
      if (_configured?.isCompleted == false) {
        _configured?.completeError(err);
      }
      if (_pendingText?.isCompleted == false) {
        _pendingText?.completeError(err);
      }
      _captions?.addError(err);
    } else if (type == 'caption') {
      _captions?.add(
        CaptionEvent(
          message['text'] as String? ?? '',
          authoritative: message['authoritative'] == true,
        ),
      );
    } else if (type == 'text') {
      if (_pendingText?.isCompleted == false) {
        _pendingText?.complete(message['text'] as String? ?? '');
      }
    } else if (type == 'disposed') {
      if (_disposed?.isCompleted == false) {
        _disposed?.complete();
      }
    }
  }
}

const _sampleRate = 16000;
const _windowSamples = 20 * _sampleRate;
const _hopSamples = 15 * _sampleRate;
const _vadWindow = 512;

void _asrIsolateMain(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);

  sox.OfflineRecognizer? recognizer;
  sox.VoiceActivityDetector? vad;
  sox.CircularBuffer? ring;
  SendPort? client;
  final captions = LiveCaptionBuffer();
  var rolling = Float32List(0);
  var samplesSinceWindow = 0;

  String decodeSamples(Float32List samples, int sampleRate) {
    if (samples.isEmpty || recognizer == null) {
      return '';
    }
    final stream = recognizer!.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    recognizer!.decode(stream);
    final text = recognizer!.getResult(stream).text.trim();
    stream.free();
    return text;
  }

  void emitCaption(String piece, {bool authoritative = false}) {
    if (piece.isEmpty) {
      return;
    }
    if (authoritative) {
      captions.commit(piece);
    } else {
      captions.setPartial(piece);
    }
    client?.send({
      'type': 'caption',
      'text': captions.display,
      'authoritative': authoritative,
    });
  }

  void transcribeWindows(Float32List samples, int sampleRate) {
    if (samples.isEmpty) {
      return;
    }
    if (samples.length <= _windowSamples) {
      emitCaption(decodeSamples(samples, sampleRate), authoritative: true);
      return;
    }
    var offset = 0;
    while (offset < samples.length) {
      final end = (offset + _windowSamples).clamp(0, samples.length);
      final slice = samples.sublist(offset, end);
      emitCaption(decodeSamples(Float32List.fromList(slice), sampleRate),
          authoritative: true);
      if (end >= samples.length) {
        break;
      }
      offset += _hopSamples;
    }
  }

  void consumeVad() {
    if (vad == null) {
      return;
    }
    while (!vad!.isEmpty()) {
      final segment = vad!.front();
      emitCaption(decodeSamples(segment.samples, _sampleRate),
          authoritative: true);
      vad!.pop();
    }
  }

  void pushFloats(Float32List samples) {
    rolling = _concat(rolling, samples);
    samplesSinceWindow += samples.length;
    ring?.push(samples);

    final r = ring;
    final detector = vad;
    if (r != null && detector != null) {
      while (r.size > _vadWindow) {
        final window = r.get(startIndex: r.head, n: _vadWindow);
        r.pop(_vadWindow);
        detector.acceptWaveform(window);
        consumeVad();
      }
    }

    if (samplesSinceWindow >= _hopSamples && rolling.length >= _windowSamples) {
      final start = rolling.length - _windowSamples;
      final window = rolling.sublist(start);
      samplesSinceWindow = 0;
      if (!trailingFloatsAreSilent(window)) {
        emitCaption(decodeSamples(window, _sampleRate));
      }
    }
  }

  inbox.listen((message) {
    if (message is! Map) {
      return;
    }
    final cmd = message['cmd'] as String?;
    try {
      switch (cmd) {
        case 'listen':
          client = message['port'] as SendPort;
        case 'configure':
          sox.initBindings();
          recognizer?.free();
          vad?.free();
          final whisper = sox.OfflineWhisperModelConfig(
            encoder: message['encoder'] as String,
            decoder: message['decoder'] as String,
            language: 'sv',
            task: 'transcribe',
          );
          recognizer = sox.OfflineRecognizer(
            sox.OfflineRecognizerConfig(
              model: sox.OfflineModelConfig(
                whisper: whisper,
                tokens: message['tokens'] as String,
                modelType: 'whisper',
                numThreads: 2,
              ),
            ),
          );
          vad = sox.VoiceActivityDetector(
            config: sox.VadModelConfig(
              sileroVad: sox.SileroVadModelConfig(
                model: message['vad'] as String,
                minSilenceDuration: 0.4,
                minSpeechDuration: 0.3,
                maxSpeechDuration: 20,
              ),
              sampleRate: _sampleRate,
              numThreads: 1,
            ),
            bufferSizeInSeconds: 60,
          );
          ring = sox.CircularBuffer(capacity: 60 * _sampleRate);
          captions.clear();
          rolling = Float32List(0);
          samplesSinceWindow = 0;
          client?.send({'type': 'ready'});
        case 'pcm':
          final bytes = message['bytes'] as Uint8List;
          pushFloats(_pcm16ToFloat(bytes));
        case 'flush':
          vad?.flush();
          consumeVad();
          if (rolling.isNotEmpty && captions.display.trim().isEmpty) {
            transcribeWindows(rolling, _sampleRate);
          }
          client?.send({'type': 'text', 'text': captions.display});
        case 'file':
          captions.clear();
          final wave = sox.readWave(message['path'] as String);
          transcribeWindows(wave.samples, wave.sampleRate);
          client?.send({'type': 'text', 'text': captions.display});
        case 'dispose':
          recognizer?.free();
          vad?.free();
          ring?.free();
          client?.send({'type': 'disposed'});
          inbox.close();
      }
    } catch (e) {
      client?.send({'type': 'error', 'message': e.toString()});
    }
  });
}

Float32List _pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

Float32List _concat(Float32List a, Float32List b) {
  if (a.isEmpty) {
    return b;
  }
  final out = Float32List(a.length + b.length);
  out.setAll(0, a);
  out.setAll(a.length, b);
  const keep = _windowSamples + _hopSamples;
  if (out.length <= keep) {
    return out;
  }
  return Float32List.fromList(out.sublist(out.length - keep));
}
