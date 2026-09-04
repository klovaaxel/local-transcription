import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'asr/asr_engine.dart';
import 'asr/cloud_transcriber.dart';
import 'asr/model_downloader.dart';
import 'asr/pcm_level.dart';
import 'asr/wav_sink.dart';
import 'cloud/openai_compatible.dart';
import 'data/app_settings.dart';
import 'data/lecture_session.dart';
import 'data/session_store.dart';
import 'models/model_catalog.dart';
import 'summarize/cloud_summarizer.dart';
import 'summarize/local_summarizer.dart';
import 'summarize/summarizer.dart';

class LectureAppState extends ChangeNotifier {
  LectureAppState({
    SessionStore? store,
    ModelDownloader? downloader,
    AudioRecorder? recorder,
  }) : store = store ?? SessionStore(),
       downloader = downloader ?? ModelDownloader(),
       _recorder = recorder ?? AudioRecorder();

  final SessionStore store;
  final ModelDownloader downloader;
  final AudioRecorder _recorder;
  final AsrEngine asr = AsrEngine();
  final _uuid = const Uuid();

  AppSettings settings = AppSettings();
  List<LectureSession> sessions = [];
  LectureSession? active;
  String? statusMessage;

  /// True when [statusMessage] is a failure. The toast keeps those up until
  /// they are dismissed; confirmations clear themselves.
  bool statusIsError = false;
  DownloadProgress? downloadProgress;
  bool busy = false;
  Duration recordElapsed = Duration.zero;
  double inputLevel = 0;
  bool asrReady = false;
  bool llmReady = false;

  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<CaptionEvent>? _captionSub;
  WavFileSink? _wav;
  Timer? _ticker;
  DateTime? _levelTick;

  Future<void> init() async {
    settings = await AppSettings.load();
    sessions = await store.list();
    await refreshModelFlags();
    notifyListeners();
  }

  void clearStatus() {
    statusMessage = null;
    statusIsError = false;
    notifyListeners();
  }

  /// A short confirmation for something that already happened. It goes to the
  /// same toast as work and errors — the app has one way of speaking up — and
  /// the toast is what decides how long a notice stays.
  void notice(String message) {
    statusMessage = message;
    statusIsError = false;
    notifyListeners();
  }

  Future<void> refreshModelFlags() async {
    asrReady = await downloader.asrReady(settings.asrSize);
    llmReady = await downloader.llmReady(size: settings.llmSize);
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await settings.save();
    await refreshModelFlags();
    notifyListeners();
  }

  Future<void> downloadAsr() async {
    await _run('Laddar ner talmodell…', () async {
      await downloader.ensureAsr(
        size: settings.asrSize,
        onProgress: _onDownload,
      );
      downloadProgress = null;
      statusMessage = 'Talmodell redo.';
      await refreshModelFlags();
    });
  }

  Future<void> downloadLlm() async {
    await _run('Laddar ner språkmodell…', () async {
      await downloader.ensureLlm(
        size: settings.llmSize,
        onProgress: _onDownload,
      );
      downloadProgress = null;
      statusMessage = 'Språkmodell redo.';
      await refreshModelFlags();
    });
  }

  Future<void> startRecording() async {
    await _run('Förbereder inspelning…', () async {
      final hasMic = await _recorder.hasPermission();
      if (!hasMic) {
        throw StateError('Mikrofonbehörighet saknas.');
      }
      final live = settings.liveCaptionsEnabled;
      if (live) {
        final paths = await downloader.ensureAsr(
          size: settings.asrSize,
          onProgress: _onDownload,
        );
        downloadProgress = null;
        await asr.start(paths);
      }

      final id = _uuid.v4();
      final dir = await store.sessionDir(id);
      final audioFile = File(p.join(dir.path, 'audio.wav'));
      final session = LectureSession(
        id: id,
        startedAt: DateTime.now(),
        audioPath: audioFile.path,
        status: SessionStatus.recording,
      );
      active = session;
      await store.upsert(session);
      sessions = await store.list();

      await _captionSub?.cancel();
      if (live) {
        _captionSub = asr.captions.listen((event) {
          final current = active;
          if (current == null) {
            return;
          }
          current.liveCaptions = event.text;
          notifyListeners();
          unawaited(store.upsert(current));
        }, onError: (Object e) {
          statusMessage = e.toString();
          notifyListeners();
        });
      }

      _wav = WavFileSink(audioFile);
      await _wav!.open();

      final stream = await _startPcmStream();
      await _pcmSub?.cancel();
      _pcmSub = stream.listen(_onPcm);

      recordElapsed = Duration.zero;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final start = active?.startedAt;
        if (start == null) {
          return;
        }
        recordElapsed = DateTime.now().difference(start);
        notifyListeners();
      });
      statusMessage = null;
    });
  }

  Future<LectureSession?> stopRecording() async {
    LectureSession? finished;
    await _run('Avslutar inspelning…', () async {
      await _pcmSub?.cancel();
      _pcmSub = null;
      inputLevel = 0;
      await _recorder.stop();
      _ticker?.cancel();
      await _wav?.close();
      _wav = null;

      final session = active;
      if (session == null) {
        return;
      }
      session.endedAt = DateTime.now();
      session.status = SessionStatus.transcribing;
      await store.upsert(session);
      notifyListeners();

      try {
        final live = settings.liveCaptionsEnabled ? await asr.flushLive() : '';
        session.liveCaptions = live;
        var text = live;
        if (session.audioPath != null) {
          statusMessage = 'Transkriberar hela inspelningen…';
          notifyListeners();
          text = await _transcribeAudio(session.audioPath!);
        }
        session.transcript = text.trim().isEmpty ? live : text;
        session.status = SessionStatus.ready;
        session.error = null;
        if (settings.deleteAudioAfterTranscribe && session.audioPath != null) {
          final file = File(session.audioPath!);
          if (await file.exists()) {
            await file.delete();
          }
          session.audioPath = null;
        }
      } catch (e) {
        session.status = SessionStatus.ready;
        session.error = e.toString();
        if (session.transcript.isEmpty) {
          session.transcript = session.liveCaptions;
        }
      }

      await store.upsert(session);
      sessions = await store.list();
      finished = session;
      active = null;
      await asr.stop();
      await _captionSub?.cancel();
      statusMessage = 'Inspelning sparad.';
    });
    return finished;
  }

  Future<void> transcribeSession(LectureSession session) async {
    await _run('Transkriberar…', () async {
      if (session.audioPath == null || !await File(session.audioPath!).exists()) {
        throw StateError('Ingen ljudfil att transkribera.');
      }
      session.status = SessionStatus.transcribing;
      await store.upsert(session);
      notifyListeners();
      try {
        session.transcript = await _transcribeAudio(session.audioPath!);
        session.status = SessionStatus.ready;
        session.error = null;
        if (settings.deleteAudioAfterTranscribe) {
          await File(session.audioPath!).delete();
          session.audioPath = null;
        }
      } catch (e) {
        session.status = SessionStatus.ready;
        session.error = e.toString();
      }
      await store.upsert(session);
      sessions = await store.list();
    });
  }

  Future<void> summarizeSession(LectureSession session) async {
    await _run('Skriver underlag…', () async {
      final transcript = session.displayTranscript.trim();
      if (transcript.isEmpty) {
        throw StateError('Ingen transkription att sammanfatta.');
      }
      session.status = SessionStatus.summarizing;
      await store.upsert(session);
      notifyListeners();

      void briefProgress(int done, int total) {
        if (total <= 1) {
          return;
        }
        statusMessage = 'Skriver underlag ($done/$total)…';
        notifyListeners();
      }

      final Summarizer summarizer;
      if (settings.summarizer == SummarizerKind.cloud) {
        summarizer = CloudSummarizer(
          config: CloudConfig.fromSettings(settings),
          onProgress: briefProgress,
        );
      } else {
        final spec = ModelCatalog.llm(settings.llmSize);
        final modelPath = await downloader.ensureLlm(
          size: settings.llmSize,
          onProgress: _onDownload,
        );
        downloadProgress = null;
        summarizer = LocalLlmSummarizer(
          modelPath: modelPath,
          spec: spec,
          onProgress: briefProgress,
        );
      }

      try {
        session.summary = await summarizer.summarize(transcript);
        session.error = null;
      } catch (e) {
        session.error = e.toString();
        rethrow;
      } finally {
        session.status = SessionStatus.ready;
        await store.upsert(session);
        sessions = await store.list();
      }
    });
  }

  /// Speech to text for a finished recording, through whichever backend the
  /// teacher chose. Cloud is the only path on which audio leaves the device.
  Future<String> _transcribeAudio(String wavPath) async {
    if (settings.transcriber == TranscriberKind.cloud) {
      final transcriber = CloudTranscriber(
        config: CloudConfig.fromSettings(settings),
        onProgress: (done, total) {
          if (total <= 1) {
            return;
          }
          statusMessage = 'Transkriberar del $done av $total…';
          notifyListeners();
        },
      );
      return transcriber.transcribeFile(wavPath);
    }

    // Recording already left the engine running; only a re-run has to load it.
    final alreadyRunning = asr.running;
    if (!alreadyRunning) {
      final paths = await downloader.ensureAsr(
        size: settings.asrSize,
        onProgress: _onDownload,
      );
      downloadProgress = null;
      await asr.start(paths);
    }
    try {
      return await asr.transcribeFile(wavPath);
    } finally {
      if (!alreadyRunning) {
        await asr.stop();
      }
    }
  }

  /// Checks the key and the URL before a lecture, and says whether the two
  /// model names actually exist at the provider. Sends no lecture data.
  Future<void> testCloudConnection() async {
    await _run('Testar anslutning…', () async {
      final client = OpenAiCompatibleClient(
        config: CloudConfig.fromSettings(settings),
      );
      try {
        final models = await client.listModels();
        final missing = <String>[
          if (settings.summarizer == SummarizerKind.cloud)
            settings.cloudChatModel.trim(),
          if (settings.transcriber == TranscriberKind.cloud)
            settings.cloudTranscribeModel.trim(),
        ].where((name) => name.isNotEmpty && !models.contains(name)).toList();

        if (models.isEmpty) {
          statusMessage =
              'Anslutningen fungerar. Leverantören listade inga modeller.';
        } else if (missing.isEmpty) {
          statusMessage =
              'Anslutningen fungerar. ${models.length} modeller tillgängliga.';
        } else {
          statusMessage =
              'Nyckeln fungerar, men ${missing.join(' och ')} '
              'finns inte i leverantörens lista.';
        }
      } finally {
        client.close();
      }
    });
  }

  Future<void> deleteSession(LectureSession session) async {
    if (active?.id == session.id) {
      return;
    }
    await store.delete(session.id);
    sessions = await store.list();
    notifyListeners();
  }

  /// `record_linux` shells out to `parecord` (PulseAudio, or pipewire-pulse on
  /// a PipeWire desktop). A distro without it throws a raw English
  /// ProcessException; every other error the teacher sees here is Swedish.
  Future<Stream<Uint8List>> _startPcmStream() async {
    try {
      return await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
    } on ProcessException catch (e) {
      throw StateError(
        'Ljudinspelning kunde inte starta: hittade inte "${e.executable}". '
        'Installera pulseaudio-utils (eller pipewire-pulse).',
      );
    }
  }

  Future<void> _run(String message, Future<void> Function() body) async {
    busy = true;
    statusMessage = message;
    statusIsError = false;
    notifyListeners();
    try {
      await body();
      if (_isSameWorkStatus(statusMessage, message)) {
        statusMessage = null;
      }
    } catch (e) {
      statusMessage = e.toString();
      statusIsError = true;
      rethrow;
    } finally {
      busy = false;
      downloadProgress = null;
      notifyListeners();
    }
  }

  bool _isSameWorkStatus(String? current, String original) {
    if (current == null || current == original) {
      return current == original;
    }
    if (original.endsWith('…')) {
      return current.startsWith(original.substring(0, original.length - 1));
    }
    return false;
  }

  void _onPcm(Uint8List chunk) {
    _wav?.addPcm16(chunk);
    if (settings.liveCaptionsEnabled) {
      asr.pushPcm16(chunk);
    }
    final now = DateTime.now();
    if (_levelTick != null &&
        now.difference(_levelTick!) < const Duration(milliseconds: 50)) {
      return;
    }
    _levelTick = now;
    final next = pcm16Level(chunk);
    inputLevel = next > inputLevel ? next : inputLevel * 0.55 + next * 0.45;
    notifyListeners();
  }

  void _onDownload(DownloadProgress progress) {
    downloadProgress = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_pcmSub?.cancel());
    unawaited(_captionSub?.cancel());
    _ticker?.cancel();
    unawaited(_recorder.dispose());
    unawaited(asr.stop());
    super.dispose();
  }
}
