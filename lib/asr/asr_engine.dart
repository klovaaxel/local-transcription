import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sox;

import 'live_caption_buffer.dart';
import 'model_downloader.dart';
import 'pcm_level.dart';
import 'wav_windows.dart';

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
    _commands!.send({'cmd': 'listen', 'port': _events!.sendPort});
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
const _vadWindow = 512;

/// Samples the live path keeps: one decode window plus one hop of history, so
/// the window read at the next hop still has audio to read [hopSamples] back
/// into.
const _rollingKeep = windowSamples + hopSamples;

/// The live path's decode history: appended to on every PCM callback, and
/// holding the most recent [_rollingKeep] samples.
///
/// The store is a ring. The live samples are the [_len] slots from [_start]
/// onwards, wrapping at the end of the store, so a push overwrites exactly the
/// room the last [trim] declared unreachable and nothing is ever moved to make
/// room. That is the whole point of the class: the implementation it replaces
/// allocated and copied the whole 35-second buffer on every one of the ~8 PCM
/// callbacks a second and then allocated two more lists to trim it back down,
/// which is ~54 MB/s of garbage inside the decode isolate for a whole lecture.
///
/// Growth is the only copy, and it stops: once the store is at least a kept
/// window plus the biggest callback the ring has seen, a callback can neither
/// overflow it nor resize it, so [capacity] stops moving and the steady state
/// allocates nothing at all.
///
/// [window] copies. The decode happens synchronously inside a push, so the
/// caller could hold a view, but the window the recognizer is handed is the one
/// array the decode owns for its duration -- the same isolation the previous
/// `sublist` gave it -- and at one window per 15 s it costs nothing.
class RollingBuffer {
  Float32List _buf = Float32List(0);

  /// Live samples, from [_start] onwards and wrapping at the end of the store.
  int _len = 0;
  int _start = 0;

  int get length => _len;

  /// Elements allocated for the backing store. Every allocation this buffer
  /// ever makes shows up here, so a steady state that does not touch it is
  /// allocating nothing at all.
  int get capacity => _buf.length;

  /// Appends [samples], overwriting whatever the last [trim] declared out of
  /// reach. A push longer than the whole store is not an error: it resizes, and
  /// what is left of the lecture stays in front of it.
  void add(Float32List samples) {
    if (samples.isEmpty) {
      return;
    }
    if (_len + samples.length > _buf.length) {
      _grow(_len + samples.length);
    }
    final begin = (_start + _len) % _buf.length;
    final head = _run(samples.length, _buf.length - begin);
    _buf.setRange(begin, begin + head, samples);
    if (head < samples.length) {
      _buf.setRange(0, samples.length - head, samples, head);
    }
    _len += samples.length;
  }

  /// Where the store goes when the ring is full: double, or take what the push
  /// needs when that is more. Doubling because a store that exactly fits would
  /// be reallocated every time it filled. Only the live samples are worth
  /// carrying over, and they land unwrapped at the front -- one growth is what
  /// leaves the ring straight again for good.
  void _grow(int needed) {
    final grown = Float32List(
      needed > _buf.length * 2 ? needed : _buf.length * 2,
    );
    if (_len > 0) {
      _copyLast(grown, _len);
    }
    _buf = grown;
    _start = 0;
  }

  /// Drops the front the next decode window cannot reach, so [length] is
  /// [_rollingKeep] again. Two integers: the ring hands those slots to the next
  /// push, and a decode reads a suffix, never an offset into the store.
  void trim() {
    if (_len > _rollingKeep) {
      _start = (_start + _len - _rollingKeep) % _buf.length;
      _len = _rollingKeep;
    }
  }

  /// The most recent [count] samples, copied out.
  Float32List window(int count) => _read(count.clamp(0, _len));

  /// Everything pushed so far that has not been trimmed away, copied out. This
  /// is what `flush` hands the window walk, so it has to be the trimmed length:
  /// a longer clip would be cut into more, differently placed windows.
  Float32List toSamples() => _read(_len);

  /// The last [take] samples.
  Float32List _read(int take) {
    final out = Float32List(take);
    if (take > 0) {
      _copyLast(out, take);
    }
    return out;
  }

  /// The last [take] live samples into [out] at its start. A ring is only ever
  /// read as one contiguous run or two, so the wrap is the one place that has
  /// to know about it.
  void _copyLast(Float32List out, int take) {
    final begin = (_start + _len - take) % _buf.length;
    final head = _run(take, _buf.length - begin);
    out.setRange(0, head, _buf, begin);
    if (head < take) {
      out.setRange(head, take, _buf);
    }
  }

  /// How much of a [length]-sample run starting [room] from the end of the store
  /// fits before it has to wrap: all of it, or the rest of the store.
  int _run(int length, int room) => length < room ? length : room;

  /// Forgets the lecture. The store is dropped rather than cleared, so a
  /// window taken before a reconfigure cannot be written through.
  void reset() {
    _buf = Float32List(0);
    _len = 0;
    _start = 0;
  }
}

/// Whisper decode threads on a phone. Phones keep the [asrThreadsForDevice]
/// value this used to be hardcoded to, and the reason is core topology, not
/// caution about big numbers: a phone SoC is big.LITTLE, and handing the
/// decoder more threads than there are big cores pushes work onto the little
/// ones, where it runs at a fraction of the clock and steals from the UI and
/// the audio capture thread. `app_settings.dart` already keeps phones on the
/// `small` model for the same reason.
const _phoneAsrThreads = 2;

/// Ceiling on the decoder's threads. This is the ceiling whisper.cpp -- the
/// reference implementation of the model family, and where the "4 threads is
/// enough" rule comes from -- puts on its own default
/// (`std::min(4, std::thread::hardware_concurrency())` in `whisper_params`).
/// Above it the encoder is memory-bandwidth bound and the extra threads take
/// cores away from the UI, the WAV writer and the VAD instead of finishing
/// sooner.
const _maxAsrThreads = 4;

/// Threads for the whisper decoder, from what the platform can report.
///
/// [logicalCores] is `Platform.numberOfProcessors`, which counts *logical*
/// CPUs: on a hyperthreaded desktop it is twice the number of cores that can
/// actually run a whisper matmul at once. There is no physical-core count to
/// ask for -- `dart:io` exposes exactly one core API and it is the logical one
/// (`Platform.numberOfProcessors`, "the number of individual execution units"),
/// on Windows, macOS and Linux alike -- so the ceiling does the work instead:
/// capped at [_maxAsrThreads] a hyperthreaded machine never gets more threads
/// than it has physical cores, while a plain 4-core desktop still gets all
/// four. The old hardcoded 2 did the opposite of both.
///
/// [phone] short-circuits to [_phoneAsrThreads]: a desktop rule applied to a
/// big.LITTLE phone is exactly the oversubscription described above.
int asrThreadsFor({required int logicalCores, required bool phone}) {
  if (phone) {
    return _phoneAsrThreads;
  }
  return logicalCores.clamp(1, _maxAsrThreads);
}

/// [asrThreadsFor] for the device the app is running on.
int asrThreadsForDevice() => asrThreadsFor(
  logicalCores: Platform.numberOfProcessors,
  phone: Platform.isAndroid || Platform.isIOS,
);

void _asrIsolateMain(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);

  sox.OfflineRecognizer? recognizer;
  sox.VoiceActivityDetector? vad;
  sox.CircularBuffer? ring;
  SendPort? client;
  final captions = LiveCaptionBuffer();
  final rolling = RollingBuffer();
  var samplesSinceWindow = 0;
  var disposing = false;

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
    if (samples.length <= windowSamples) {
      emitCaption(decodeSamples(samples, sampleRate), authoritative: true);
      return;
    }
    for (final offset in windowOffsets(samples.length)) {
      final end = (offset + windowSamples).clamp(0, samples.length);
      final slice = samples.sublist(offset, end);
      emitCaption(
        decodeSamples(Float32List.fromList(slice), sampleRate),
        authoritative: true,
      );
    }
  }

  /// The recording on disk, one window at a time, so peak memory is a window
  /// rather than the lecture and a header that never got patched no longer
  /// reads as silence. `false` from [readWavWindows] means `stop()` landed
  /// between two windows: the recognizer is freed while this walk is still
  /// holding it, which is a crash, so bail out instead of decoding.
  Future<void> transcribeFileWindows(File file) async {
    await readWavWindows(file, (samples, sampleRate) {
      if (disposing) {
        return false;
      }
      emitCaption(decodeSamples(samples, sampleRate), authoritative: true);
      return true;
    });
  }

  void consumeVad() {
    if (vad == null) {
      return;
    }
    while (!vad!.isEmpty()) {
      final segment = vad!.front();
      emitCaption(
        decodeSamples(segment.samples, _sampleRate),
        authoritative: true,
      );
      vad!.pop();
    }
  }

  void pushFloats(Float32List samples) {
    rolling.add(samples);
    // Trimmed before anything reads the length, not after the decode: the
    // guard below and the window `flush` hands the walk both see this length,
    // and a live region longer than one window plus one hop would be cut into
    // differently placed windows than it used to be.
    rolling.trim();
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

    if (samplesSinceWindow >= hopSamples && rolling.length >= windowSamples) {
      final window = rolling.window(windowSamples);
      samplesSinceWindow = 0;
      if (!trailingFloatsAreSilent(window)) {
        emitCaption(decodeSamples(window, _sampleRate));
      }
    }
  }

  // Async so the file walk can yield between windows; every other command runs
  // straight through, it has nothing to await.
  inbox.listen((message) async {
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
          rolling.reset();
          samplesSinceWindow = 0;
          client?.send({'type': 'ready'});
        case 'pcm':
          final bytes = message['bytes'] as Uint8List;
          pushFloats(pcm16ToFloat(bytes));
        case 'flush':
          vad?.flush();
          consumeVad();
          if (rolling.length > 0 && captions.display.trim().isEmpty) {
            transcribeWindows(rolling.toSamples(), _sampleRate);
          }
          client?.send({'type': 'text', 'text': captions.display});
        case 'file':
          captions.clear();
          await transcribeFileWindows(File(message['path'] as String));
          client?.send({'type': 'text', 'text': captions.display});
        case 'dispose':
          disposing = true;
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
