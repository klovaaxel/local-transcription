import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_catalog.dart';
import '../perf/device_bench.dart';
import '../summarize/brief_sections.dart';

/// The speech model for this device, picked when the teacher leaves the
/// choice to the app. kb-whisper-medium transcribes noticeably better
/// Swedish but costs ~2.5x the compute of small. Desktop CPUs handle that
/// fine (it runs after the lecture, with progress shown); phones transcribe
/// on the CPU and would crawl — small there, unless the desktop has fewer
/// than four cores.
AsrModelSize autoAsrForDevice() {
  if (Platform.isAndroid || Platform.isIOS) {
    return AsrModelSize.small;
  }
  if (Platform.numberOfProcessors < 4) {
    return AsrModelSize.small;
  }
  return AsrModelSize.medium;
}

/// The brief model for this device, picked when the teacher leaves the
/// choice to the app. Desktops get the 7B (GPU offload). Phones get the 3B —
/// big enough that keyword lists and invented dates stop, small enough for a
/// phone; Metal carries it on iPhone.
LlmModelSize autoLlmForDevice() {
  if (Platform.isAndroid || Platform.isIOS) {
    return LlmModelSize.medium;
  }
  return LlmModelSize.large;
}

class AppSettings {
  AppSettings({
    this.asrSize = AsrModelSize.small,
    this.autoAsr = true,
    this.llmSize = LlmModelSize.small,
    this.autoLlm = true,
    this.summarizer = SummarizerKind.local,
    this.transcriber = TranscriberKind.local,
    this.cloudProviderId = 'berget',
    this.cloudApiKey = '',
    String? cloudBaseUrl,
    String? cloudChatModel,
    String? cloudTranscribeModel,
    this.deleteAudioAfterTranscribe = false,
    this.autoUpdate = true,
    List<String>? briefSectionIds,
    this.cpuScoreMbs,
  }) : cloudBaseUrl = cloudBaseUrl ?? CloudCatalog.berget.baseUrl,
       cloudChatModel = cloudChatModel ?? CloudCatalog.berget.chatModel,
       cloudTranscribeModel =
           cloudTranscribeModel ?? CloudCatalog.berget.transcribeModel,
       briefSectionIds = briefSectionIds ?? BriefSectionCatalog.defaultIds;

  AsrModelSize asrSize;

  /// When true (the default) the app picks the speech model for this device:
  /// kb-whisper-medium on desktops with four or more cores, small on phones.
  /// [asrSize] is then only the explicit override, used when this is false.
  bool autoAsr;

  LlmModelSize llmSize;

  /// When true (the default) the app picks the brief model for this device:
  /// 7B on desktop, 3B on phones. [llmSize] is then only the explicit
  /// override, used when this is false.
  bool autoLlm;

  /// Measured SHA-256 throughput (MB/s) from the launch benchmark, or null
  /// before the first run. Benchmarked once per app version; see
  /// [DeviceBench] and [cpuWeakMbs].
  double? cpuScoreMbs;

  /// The app version the [cpuScoreMbs] measurement belongs to. A new version
  /// re-runs the benchmark.
  String? benchVersion;

  /// Wall time divided by audio length for the last on-device transcription
  /// (2.0 = two minutes of work per minute of lecture). Null before the
  /// first calibration.
  double? asrRealtimeRatio;

  /// Brief wall time in milliseconds per 1000 transcript characters, from
  /// the last on-device brief. Null before the first calibration.
  double? llmMsPerKchar;

  /// Auto-pick ceilings written by the calibration passes. A manual pick
  /// never sees them ([autoLlm]/[autoAsr] false) — "manually picked wins"
  /// over everything, including measurements.
  LlmModelSize? llmCap;
  AsrModelSize? asrCap;

  /// Generated tokens/second from the decode probe run right after a brief
  /// model downloaded ([LlmSpeedProbe]). Includes whatever GPU the device
  /// has, which the launch benchmark cannot.
  double? llmTokPerSec;

  /// Which tier+app-version the speed measurement belongs to.
  String? llmTokBenchKey;

  /// First available GPU-compute backend name (device included), or null.
  /// Informational — it is what the speed measurement says that decides.
  String? gpuBackendName;

  /// Measured GPU preference for the local brief (LlmSpeedProbe on phones:
  /// keep whichever of GPU and CPU decoded faster). Null before the probe;
  /// true=GPU, false=CPU. Desktops default to the platform call.
  bool? llmGpuOffload;

  AsrModelSize get effectiveAsrSize => autoAsr ? _autoAsrPick() : asrSize;

  LlmModelSize get effectiveLlmSize => autoLlm ? _autoLlmPick() : llmSize;

  AsrModelSize _autoAsrPick() {
    var pick = autoAsrForDevice();
    // Without a GPU the CPU carries whisper; a measurement below the weak
    // line means medium would crawl even on a desktop — small it is.
    if (pick == AsrModelSize.medium &&
        cpuScoreMbs != null &&
        cpuScoreMbs! < cpuWeakMbs) {
      pick = AsrModelSize.small;
    }
    final cap = asrCap;
    if (cap != null && pick.index > cap.index) {
      pick = cap;
    }
    return pick;
  }

  LlmModelSize _autoLlmPick() {
    var pick = autoLlmForDevice();
    if (pick == LlmModelSize.large &&
        cpuScoreMbs != null &&
        cpuScoreMbs! < cpuWeakMbs) {
      pick = LlmModelSize.medium;
    }
    final cap = llmCap;
    if (cap != null && pick.index > cap.index) {
      pick = cap;
    }
    return pick;
  }

  /// Records the last on-device transcription and downgrades the automatic
  /// pick when the ratio says the machine cannot keep up. Returns true when
  /// the effective size changed as a result. Cloud timing never lands here
  /// (network latency is not device speed).
  bool applyAsrCalibration(double realtimeRatio) {
    asrRealtimeRatio = realtimeRatio;
    if (!autoAsr || realtimeRatio <= 8) {
      return false;
    }
    final current = _autoAsrPick();
    if (current.index == 0) {
      return false;
    }
    asrCap = AsrModelSize.values[current.index - 1];
    return true;
  }

  /// Same idea for the brief. Desktop reference: ~1 ms per 1000 characters
  /// (a 45-min lecture in ~20 s). Above 100 ms/kchar a lecture takes many
  /// minutes — a tier the teacher should not be handed by default, even if
  /// it technically loads.
  bool applyLlmCalibration(double msPerKchar) {
    llmMsPerKchar = msPerKchar;
    if (!autoLlm || msPerKchar <= 100) {
      return false;
    }
    final current = _autoLlmPick();
    if (current.index == 0) {
      return false;
    }
    llmCap = LlmModelSize.values[current.index - 1];
    return true;
  }

  /// Gate on the decode probe measured right after the download, before the
  /// teacher's first real brief. Desktop reference (Vulkan): tens of tokens
  /// per second. Below [llmSlowTokPerSec] even a full underlag would take
  /// minutes of decode, so the auto pick steps down a tier. The measurement
  /// is per tier + app version ([llmTokBenchKey]).
  bool applyLlmSpeedBench(double tokPerSec, LlmModelSize measuredSize) {
    llmTokPerSec = tokPerSec;
    if (!autoLlm || tokPerSec >= llmSlowTokPerSec) {
      return false;
    }
    final current = measuredSize.index > 0 ? measuredSize : _autoLlmPick();
    if (current.index == 0 || _autoLlmPick().index == 0) {
      return false;
    }
    final target = current.index - 1;
    if (llmCap != null && llmCap!.index <= target) {
      return false;
    }
    llmCap = LlmModelSize.values[target];
    return true;
  }

  SummarizerKind summarizer;
  TranscriberKind transcriber;
  String cloudProviderId;
  String cloudApiKey;
  String cloudBaseUrl;
  String cloudChatModel;
  String cloudTranscribeModel;
  bool deleteAudioAfterTranscribe;

  /// Which brief sections the teacher wants. Ids are matched against
  /// [BriefSectionCatalog] at use time, so an id from a retired block is
  /// silently dropped rather than breaking anything.
  List<String> briefSectionIds;

  /// The brief's section specs in prompt order. The overview is locked and
  /// always comes first (it names the lecture).
  List<BriefSectionSpec> get briefSpecs =>
      BriefSectionCatalog.resolve(briefSectionIds);

  /// Same, with the schedule instruction chosen for the model tier that
  /// will write the brief (7B answers prov-detail questions well enough
  /// that the extra instruction measurably pays off; the 3B screens it).
  List<BriefSectionSpec> briefSpecsFor(LlmModelSize size) =>
      BriefSectionCatalog.resolveFor(size, briefSectionIds);

  /// When true the app checks the update feed at startup and installs a newer
  /// release in the background (never during a lecture). The check itself is
  /// a single HTTPS GET to the release feed.
  bool autoUpdate;

  /// True when anything at all would leave the device. The record and session
  /// screens read this to tell the teacher before audio or text is sent.
  bool get usesCloud =>
      summarizer == SummarizerKind.cloud ||
      transcriber == TranscriberKind.cloud;

  /// Live captions need the on-device model. Cloud transcription happens
  /// after the lecture, on the finished file, so there is nothing to show
  /// while recording.
  bool get liveCaptionsEnabled => transcriber == TranscriberKind.local;

  /// Copies the preset's URL and model ids over the current values. Custom
  /// keeps whatever the teacher typed.
  void applyProvider(CloudProvider provider) {
    cloudProviderId = provider.id;
    if (provider.baseUrl.isEmpty) {
      return;
    }
    cloudBaseUrl = provider.baseUrl;
    cloudChatModel = provider.chatModel;
    cloudTranscribeModel = provider.transcribeModel;
  }

  static const _asr = 'asrSize';
  static const _autoAsr = 'autoAsr';
  static const _llm = 'llmSize';
  static const _autoLlm = 'autoLlm';
  static const _sum = 'summarizer';
  static const _asrKind = 'transcriber';
  static const _provider = 'cloudProviderId';
  static const _key = 'cloudApiKey';
  static const _url = 'cloudBaseUrl';
  static const _chatModel = 'cloudChatModel';
  static const _asrModel = 'cloudTranscribeModel';
  static const _del = 'deleteAudioAfterTranscribe';
  static const _autoUpdate = 'autoUpdate';
  static const _briefSections = 'briefSectionIds';
  static const _cpuScore = 'cpuScoreMbs';
  static const _benchVersion = 'benchVersion';
  static const _asrRatio = 'asrRealtimeRatio';
  static const _llmMsKchar = 'llmMsPerKchar';
  static const _llmCap = 'llmCap';
  static const _asrCap = 'asrCap';
  static const _llmTok = 'llmTokPerSec';
  static const _llmTokKey = 'llmTokBenchKey';
  static const _gpuBackend = 'gpuBackendName';
  static const _llmGpu = 'llmGpuOffload';

  /// Below this decode speed the auto brief pick steps down. Anchored in
  /// measured devices ([LlmSpeedProbe]): a known-good desktop measures ~5
  /// tok/s on the 7B (Vulkan) and finishes a 90-300-token underlag in well
  /// under a minute. At 4 tok/s that is already two minutes of decode —
  /// the line where a tier stops being a sensible default.
  static const llmSlowTokPerSec = 4.0;

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
        asrSize: AsrModelSize.values.firstWhere(
          (e) => e.name == p.getString(_asr),
          orElse: () => AsrModelSize.small,
        ),
        autoAsr: p.getBool(_autoAsr) ?? true,
        llmSize: LlmModelSize.values.firstWhere(
          (e) => e.name == p.getString(_llm),
          orElse: () => LlmModelSize.small,
        ),
        autoLlm: p.getBool(_autoLlm) ?? true,
        summarizer: SummarizerKind.values.firstWhere(
          (e) => e.name == p.getString(_sum),
          orElse: () => SummarizerKind.local,
        ),
        transcriber: TranscriberKind.values.firstWhere(
          (e) => e.name == p.getString(_asrKind),
          orElse: () => TranscriberKind.local,
        ),
        cloudProviderId: p.getString(_provider) ?? CloudCatalog.berget.id,
        cloudApiKey: p.getString(_key) ?? '',
        cloudBaseUrl: p.getString(_url),
        cloudChatModel: p.getString(_chatModel),
        cloudTranscribeModel: p.getString(_asrModel),
        deleteAudioAfterTranscribe: p.getBool(_del) ?? false,
        autoUpdate: p.getBool(_autoUpdate) ?? true,
        briefSectionIds: p.getString(_briefSections)?.split(','),
      )
      ..cpuScoreMbs = p.getDouble(_cpuScore)
      ..benchVersion = p.getString(_benchVersion)
      ..asrRealtimeRatio = p.getDouble(_asrRatio)
      ..llmMsPerKchar = p.getDouble(_llmMsKchar)
      ..llmCap = LlmModelSize.values
          .where((e) => e.name == p.getString(_llmCap))
          .firstOrNull
      ..asrCap = AsrModelSize.values
          .where((e) => e.name == p.getString(_asrCap))
          .firstOrNull
      ..llmTokPerSec = p.getDouble(_llmTok)
      ..llmTokBenchKey = p.getString(_llmTokKey)
      ..gpuBackendName = p.getString(_gpuBackend)
      ..llmGpuOffload = p.getString(_llmGpu) == ''
          ? null
          : p.getString(_llmGpu) == 'true';
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_asr, asrSize.name);
    await p.setBool(_autoAsr, autoAsr);
    await p.setString(_llm, llmSize.name);
    await p.setBool(_autoLlm, autoLlm);
    await p.setString(_sum, summarizer.name);
    await p.setString(_asrKind, transcriber.name);
    await p.setString(_provider, cloudProviderId);
    await p.setString(_key, cloudApiKey);
    await p.setString(_url, cloudBaseUrl);
    await p.setString(_chatModel, cloudChatModel);
    await p.setString(_asrModel, cloudTranscribeModel);
    await p.setBool(_del, deleteAudioAfterTranscribe);
    await p.setBool(_autoUpdate, autoUpdate);
    await p.setString(_briefSections, briefSectionIds.join(','));
    final score = cpuScoreMbs;
    if (score == null) {
      await p.remove(_cpuScore);
    } else {
      await p.setDouble(_cpuScore, score);
    }
    await p.setString(_benchVersion, benchVersion ?? '');
    final ratio = asrRealtimeRatio;
    if (ratio == null) {
      await p.remove(_asrRatio);
    } else {
      await p.setDouble(_asrRatio, ratio);
    }
    final ms = llmMsPerKchar;
    if (ms == null) {
      await p.remove(_llmMsKchar);
    } else {
      await p.setDouble(_llmMsKchar, ms);
    }
    await p.setString(_llmCap, llmCap?.name ?? '');
    await p.setString(_asrCap, asrCap?.name ?? '');
    final tok = llmTokPerSec;
    if (tok == null) {
      await p.remove(_llmTok);
    } else {
      await p.setDouble(_llmTok, tok);
    }
    await p.setString(_llmTokKey, llmTokBenchKey ?? '');
    await p.setString(_gpuBackend, gpuBackendName ?? '');
    await p.setString(
      _llmGpu,
      llmGpuOffload == null ? '' : (llmGpuOffload! ? 'true' : 'false'),
    );
  }
}
