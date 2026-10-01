import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart' show BackendDetector;
import 'package:package_info_plus/package_info_plus.dart';
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
import 'data/session_entry.dart';
import 'data/session_store.dart';
import 'models/model_catalog.dart';
import 'perf/device_bench.dart';
import 'perf/llm_speed_probe.dart';
import 'summarize/brief_pipeline.dart' show BriefCancelled;
import 'summarize/cloud_summarizer.dart';
import 'summarize/local_summarizer.dart';
import 'summarize/summarizer.dart';
import 'update/update_feed.dart';
import 'update/update_installer.dart';

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

  /// The lecture list, manifest only. Everything the cards render is derived
  /// at write time, so the home screen costs one small file however long the
  /// lectures in it are. The lecture itself is read per screen, from its own
  /// file.
  List<SessionEntry> sessions = [];
  LectureSession? active;
  String? statusMessage;

  /// The full lecture behind a manifest row, read on demand. Throws if the id
  /// is unknown -- a row without a file means a half-finished write, and the
  /// session screen reports that rather than showing an empty lecture.
  Future<LectureSession> loadSession(String id) => store.load(id);

  /// A caption event, for tests that need to drive the caption stream without
  /// a Whisper model. [_onCaption] is the whole of the behaviour.
  @visibleForTesting
  Future<void> onCaptionForTest(CaptionEvent event) async {
    _onCaption(event);
    // The append is deliberately not awaited, so let it land before counting.
    await Future<void>.delayed(Duration.zero);
  }

  /// A lecture left mid-flight by a killed process. Its status on disk is a
  /// promise nothing is going to keep, so the card would say "Spelar in" for
  /// good. Reconcile each one: say it was interrupted, fold in whatever the
  /// caption log caught, and drop an audio path that is not there -- offering
  /// "Transkribera om" for a file that does not exist is the one way this
  /// makes things worse than leaving it alone.
  ///
  /// Runs once at launch, before anything reads [sessions] for display. Every
  /// write is a [SessionStore.save], so a lecture reconciled twice is the same
  /// lecture twice rather than a second row.
  /// The launch path as it reaches the reconciliation: read the manifest, then
  /// settle whatever it found. [init] does this as its first two statements --
  /// separating them is only so a test does not need settings and package info.
  @visibleForTesting
  Future<void> reconcileForTest() async {
    sessions = await store.list();
    await _reconcileInterrupted();
  }

  Future<void> _reconcileInterrupted() async {
    final stranded = sessions.where((e) => _inProgress.contains(e.status)).toList();
    if (stranded.isEmpty) {
      return;
    }
    for (final entry in stranded) {
      try {
        final session = await _loadOrRebuild(entry);
        session.status = SessionStatus.interrupted;

        // A kill cuts the recording off at an unknown point, so there is no
        // honest value to invent for `endedAt` -- leave whatever was written.
        if (session.displayTranscript.trim().isEmpty) {
          // The log is the one copy written outside the process that died.
          final recovered = await store.readCaptions(session.id);
          if (recovered.trim().isNotEmpty) {
            session.liveCaptions = recovered;
          }
        }

        final audio = session.audioPath;
        if (audio != null && !await File(audio).exists()) {
          session.audioPath = null;
        }

        await store.save(session);
      } on Object {
        // A lecture that cannot be read back is left exactly as it was. The
        // store writes the session before the manifest row, so this should not
        // happen, and a row that is unreachable is a smaller problem than one
        // that was rewritten into a state nobody asked for.
      }
    }
    sessions = await store.list();
  }

  /// Statuses that mean work is genuinely in flight. `active` is null at
  /// launch, so anything still claiming one of these was left behind.
  static const _inProgress = {
    SessionStatus.recording,
    SessionStatus.transcribing,
    SessionStatus.summarizing,
  };

  /// The lecture behind a row, or a stand-in built from the row itself when
  /// the session file is missing. A row with no file should not exist -- the
  /// store writes the file first -- but a store written by an older build, or
  /// one whose file was deleted under it, can leave one, and a row in a
  /// progress status with no file behind it is exactly the case this method
  /// exists to stop lying about.
  Future<LectureSession> _loadOrRebuild(SessionEntry entry) async {
    try {
      return await store.load(entry.id);
    } on StateError {
      return LectureSession(
        id: entry.id,
        startedAt: entry.startedAt,
        endedAt: entry.endedAt,
        audioPath: entry.audioPath,
      );
    }
  }

  /// True when [statusMessage] is a failure. The toast keeps those up until
  /// they are dismissed; confirmations clear themselves.
  bool statusIsError = false;
  DownloadProgress? downloadProgress;
  bool busy = false;
  Duration recordElapsed = Duration.zero;
  double inputLevel = 0;
  bool asrReady = false;
  bool llmReady = false;

  /// "1.0.0+1" from the platform metadata, shown in settings.
  String appVersionLabel = '';
  String _appVersion = '';
  int _appBuild = 0;

  /// Set when the update feed offers a newer version. The settings card
  /// offers an update button; auto mode installs it without asking.
  UpdateManifest? updateInfo;

  /// Startup-only: checks the feed once and either installs an update (auto
  /// mode) or just shows the settings card. Never runs during a lecture and
  /// never surfaces a network failure — a missing feed must not scold the
  /// teacher who is recording.
  Timer? _updateCheck;
  final UpdateInstaller _installer = UpdateInstaller();

  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<CaptionEvent>? _captionSub;
  WavFileSink? _wav;
  Timer? _ticker;
  DateTime? _levelTick;

  Future<void> init() async {
    settings = await AppSettings.load();
    sessions = await store.list();
    await _reconcileInterrupted();
    await refreshModelFlags();
    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version;
    _appBuild = int.tryParse(info.buildNumber) ?? 0;
    appVersionLabel =
        '${info.version}${info.buildNumber.isNotEmpty ? '+${info.buildNumber}' : ''}';
    notifyListeners();
    // The auto check waits a few seconds after launch so it never competes
    // with the app warming up; it also skips while recording or busy.
    _updateCheck = Timer(const Duration(seconds: 8), _autoUpdateCheck);
    unawaited(_runStartupBench());
  }

  /// Runs the CPU benchmark once per app version (first launch counts as a
  /// version change). Pure Dart, under a second, in a background isolate.
  /// The score gates the auto model pick (see [AppSettings._autoLlmPick]);
  /// the real-work calibrations below refine it further. A new benchmark
  /// cycle also clears the measured caps: thresholds are per device, a new
  /// app version re-measures everything, and a one-off slow run (background
  /// load during the first brief, say) must not demote a device forever.
  Future<void> _runStartupBench() async {
    final label = appVersionLabel;
    if (label.isEmpty || settings.benchVersion == label) {
      return;
    }
    try {
      final score = await DeviceBench.cpuScoreMbs();
      settings.cpuScoreMbs = score;
      settings.benchVersion = label;
      settings.llmCap = null;
      settings.asrCap = null;
      await settings.save();
      await refreshModelFlags();
    } catch (_) {
      // A failed benchmark must never block the app; the platform
      // heuristics carry the pick.
    }
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
    asrReady = await downloader.asrReady(settings.effectiveAsrSize);
    llmReady = await downloader.llmReady(size: settings.effectiveLlmSize);
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
        size: settings.effectiveAsrSize,
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
        size: settings.effectiveLlmSize,
        onProgress: _onDownload,
      );
      downloadProgress = null;
      statusMessage = 'Språkmodell redo.';
      await refreshModelFlags();
    });
  }

  Future<void> _autoUpdateCheck() async {
    if (busy || active?.status == SessionStatus.recording) {
      return;
    }
    try {
      final manifest = await UpdateManifest.fetch();
      if (manifest == null || !_updateIsNewer(manifest)) {
        return;
      }
      updateInfo = manifest;
      notifyListeners();
      if (settings.autoUpdate && _installer.platformSupported) {
        await updateNow();
      }
    } catch (_) {
      // Update checks are opportunistic; a feed outage is nobody's error to
      // show. A manual check reports properly through the settings screen.
    }
  }

  /// Manual check from settings. Reports in Swedish through the toast, like
  /// every other piece of work in the app.
  Future<void> checkForUpdates() async {
    await _run('Söker efter uppdatering…', () async {
      final manifest = await UpdateManifest.fetch();
      if (manifest == null) {
        statusMessage =
            'Ingen uppdateringslista hittad. Har första versionen '
            'publicerats?';
        statusIsError = true;
        return;
      }
      if (!versionIsNewer(
        _appVersion,
        _appBuild,
        manifest.version,
        manifest.build,
      )) {
        statusMessage = 'Du har den senaste versionen.';
        return;
      }
      updateInfo = manifest;
      notifyListeners();
      if (settings.autoUpdate && _installer.platformSupported) {
        await updateNow();
        return;
      }
      statusMessage = 'Version ${manifest.version} finns.';
    });
  }

  /// Downloads the offered update and installs it. Windows and Linux exit the
  /// app (the installer respawns it), Android hands over to the system
  /// installer, macOS reveals the zip in Finder.
  Future<void> updateNow() async {
    final manifest = updateInfo;
    if (manifest == null || !_installer.platformSupported) {
      return;
    }
    final artifact = _installer.artifactFor(manifest);
    if (artifact == null || !artifact.isValid) {
      throw StateError(
        'Version ${manifest.version} saknar uppdateringsfil för den här '
        'plattformen ännu.',
      );
    }
    await _run('Laddar ner uppdatering ${manifest.version}…', () async {
      if (Platform.isAndroid) {
        final allowed = await _installer.canRequestInstall();
        if (!allowed) {
          await _installer.openInstallPermissionSettings();
          throw StateError(
            'Tillåt appen att installera uppdateringar i Android-inställningarna '
            'och försök igen.',
          );
        }
      }
      final path = await _installer.download(
        artifact,
        onProgress: (received, total) => _onDownload(
          DownloadProgress(
            label: artifact.file,
            received: received,
            total: total,
          ),
        ),
      );
      downloadProgress = null;
      statusMessage = 'Installerar uppdatering…';
      notifyListeners();
      await _installer.install(path);
    });
  }

  /// Manifest is newer than the running app?
  bool _updateIsNewer(UpdateManifest manifest) {
    return versionIsNewer(
      _appVersion,
      _appBuild,
      manifest.version,
      manifest.build,
    );
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
          size: settings.effectiveAsrSize,
          onProgress: _onDownload,
        );
        downloadProgress = null;
        await asr.start(paths, numThreads: settings.effectiveAsrThreads);
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
      await store.save(session);
      sessions = await store.list();

      await _captionSub?.cancel();
      if (live) {
        _captionSub = asr.captions.listen(
          (event) {
            final current = active;
            if (current == null) {
              return;
            }
            _onCaption(event);
          },
          onError: (Object e) {
            statusMessage = e.toString();
            notifyListeners();
          },
        );
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
      await store.save(session);
      notifyListeners();

      try {
        final flushed = settings.liveCaptionsEnabled ? await asr.flushLive() : '';
        // The engine's flush is the live text as this run of the app heard it,
        // and it wins. A lecture that did not get this far -- the app was
        // killed mid-recording, the flush failed, the engine never started --
        // has nothing in memory but has everything in the caption log, which is
        // the one copy written outside the process that can die.
        final live = flushed.trim().isEmpty
            ? await store.readCaptions(session.id)
            : flushed;
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

      await store.save(session);
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
      if (session.audioPath == null ||
          !await File(session.audioPath!).exists()) {
        throw StateError('Ingen ljudfil att transkribera.');
      }
      session.status = SessionStatus.transcribing;
      await store.save(session);
      notifyListeners();
      try {
        final started = Stopwatch()..start();
        session.transcript = await _transcribeAudio(session.audioPath!);
        started.stop();
        await _calibrateAsr(session.audioPath!, started.elapsedMilliseconds);
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
      await store.save(session);
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
          specs: settings.briefSpecs,
        );
      } else {
        final size = settings.effectiveLlmSize;
        final modelPath = await downloader.ensureLlm(
          size: size,
          onProgress: _onDownload,
        );
        downloadProgress = null;
        // The probe may step the tier down for what settings say and for
        // the NEXT brief+download, but this run keeps the spec that matches
        // the file already on the device.
        final spec = ModelCatalog.llm(size);
        await _speedProbeLlm(size, modelPath);
        summarizer = LocalLlmSummarizer(
          modelPath: modelPath,
          spec: spec,
          onProgress: briefProgress,
          specs: settings.briefSpecsFor(size),
          gpuLayers: settings.llmGpuOffload == null
              ? null
              : (settings.llmGpuOffload! ? 99 : 0),
        );
      }

      try {
        final started = Stopwatch()..start();
        session.summary = await summarizer.summarize(transcript);
        started.stop();
        if (settings.summarizer == SummarizerKind.local) {
          await _calibrateLlm(transcript.length, started.elapsedMilliseconds);
        }
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

  /// A short, fixed decode right after the model is on the device — the
  /// only measurement that includes the GPU. Runs once per tier+app
  /// version, before the teacher's first real brief. If the tier cannot
  /// generate at a sane speed the auto pick steps down and says so; this
  /// brief still uses the file that is already downloaded.
  Future<void> _speedProbeLlm(LlmModelSize size, String modelPath) async {
    _captureGpuBackend();
    final key = '${size.name}:$_appVersion';
    if (settings.llmTokBenchKey == key) {
      return;
    }
    statusMessage = 'Mäter modellens hastighet (en gång)…';
    notifyListeners();
    var downgraded = false;
    double? tokPerSec;
    try {
      // On phones this first measures GPU vs CPU for the OFFLOAD policy,
      // then reports the winner's speed as the device number.
      final preferGpu = await LlmSpeedProbe.measureGpuPreference(
        modelPath: modelPath,
        spec: ModelCatalog.llm(size),
      );
      settings.llmGpuOffload = preferGpu;
      tokPerSec = await LlmSpeedProbe.tokPerSec(
        modelPath: modelPath,
        spec: ModelCatalog.llm(size),
        nGpuLayers: preferGpu == null ? null : (preferGpu ? 99 : 0),
      );
      downgraded = settings.applyLlmSpeedBench(tokPerSec, size);
    } catch (_) {
      // One attempt per version, then stand down — an unreachable probe
      // must never block summarizing.
    }
    settings.llmTokBenchKey = key;
    await settings.save();
    await refreshModelFlags();
    if (downgraded && tokPerSec != null) {
      notice(
        'Modellen är för långsam på den här datorn '
        '(${tokPerSec.toStringAsFixed(0)} tokens/s). Nästa underlag '
        'använder ${ModelCatalog.llm(settings.effectiveLlmSize).label}.',
      );
    }
  }

  /// First available GPU-compute backend, remembered for the settings page.
  /// Informational: what decides is the measured decode speed.
  void _captureGpuBackend() {
    if (settings.gpuBackendName != null) {
      return;
    }
    try {
      final gpu = BackendDetector.getAvailableBackends()
          .where((b) => b.isAvailable && b.name != 'CPU')
          .toList();
      if (gpu.isEmpty) {
        return;
      }
      final b = gpu.first;
      settings.gpuBackendName =
          '${b.name}${b.deviceName != null ? ' (${b.deviceName})' : ''}';
    } catch (_) {
      // Backend probing shells out (nvidia-smi) where allowed; a failure
      // here costs nothing.
    }
  }

  /// The device says how fast it really transcribed. A ratio far above a
  /// few x realtime means the auto pick over-reached; the pick steps down a
  /// tier and says so. Manual picks are never second-guessed.
  Future<void> _calibrateAsr(String wavPath, int wallMs) async {
    double? audioSeconds;
    try {
      final bytes = await File(wavPath).length();
      audioSeconds = bytes / 32000.0; // 16 kHz mono, 16-bit PCM
    } catch (_) {
      return;
    }
    if (audioSeconds < 5) {
      return;
    }
    final ratio = wallMs / 1000.0 / audioSeconds;
    final downgraded = settings.applyAsrCalibration(ratio);
    await settings.save();
    await refreshModelFlags();
    if (downgraded) {
      notice(
        'Datorn/enheten var långsam — talmodellen växlade till '
        '${ModelCatalog.asr(settings.effectiveAsrSize).label}.',
      );
    }
  }

  /// Same idea for the brief: measured ms per 1000 characters decides
  /// whether the automatic tier stands. Manual picks are never touched.
  Future<void> _calibrateLlm(int transcriptChars, int wallMs) async {
    if (transcriptChars < 2000) {
      return;
    }
    final perKchar = wallMs / (transcriptChars / 1000);
    final downgraded = settings.applyLlmCalibration(perKchar);
    await settings.save();
    await refreshModelFlags();
    if (downgraded) {
      notice(
        'Underlaget var långsamt på den här datorn — språkmodellen växlade '
        'till ${ModelCatalog.llm(settings.effectiveLlmSize).label}.',
      );
    }
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
        size: settings.effectiveAsrSize,
        onProgress: _onDownload,
      );
      downloadProgress = null;
      await asr.start(paths, numThreads: settings.effectiveAsrThreads);
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

  /// A caption arrived. Split out from the subscription so it can be driven
  /// directly: which store call this makes is the thing worth a test, and it is
  /// the one write that used to cost what the whole lecture cost.
  void _onCaption(CaptionEvent event) {
    final current = active;
    if (current == null) {
      return;
    }
    current.liveCaptions = event.text;
    notifyListeners();
    // The stream hands over the whole buffer every time and it grows with the
    // lecture, so this is an append and nothing more: the log diffs the text
    // itself, and the manifest row is not touched because nothing the card
    // shows has changed yet.
    unawaited(store.appendCaptions(current.id, event.text));
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
    _updateCheck?.cancel();
    unawaited(_recorder.dispose());
    unawaited(asr.stop());
    super.dispose();
  }
}
