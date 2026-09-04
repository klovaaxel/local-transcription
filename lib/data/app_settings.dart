import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_catalog.dart';

class AppSettings {
  AppSettings({
    this.asrSize = AsrModelSize.small,
    this.llmSize = LlmModelSize.small,
    this.summarizer = SummarizerKind.local,
    this.transcriber = TranscriberKind.local,
    this.cloudProviderId = 'berget',
    this.cloudApiKey = '',
    String? cloudBaseUrl,
    String? cloudChatModel,
    String? cloudTranscribeModel,
    this.deleteAudioAfterTranscribe = false,
    this.autoUpdate = true,
  }) : cloudBaseUrl = cloudBaseUrl ?? CloudCatalog.berget.baseUrl,
       cloudChatModel = cloudChatModel ?? CloudCatalog.berget.chatModel,
       cloudTranscribeModel =
           cloudTranscribeModel ?? CloudCatalog.berget.transcribeModel;

  AsrModelSize asrSize;
  LlmModelSize llmSize;
  SummarizerKind summarizer;
  TranscriberKind transcriber;
  String cloudProviderId;
  String cloudApiKey;
  String cloudBaseUrl;
  String cloudChatModel;
  String cloudTranscribeModel;
  bool deleteAudioAfterTranscribe;

  /// When true the app checks the update feed at startup and installs a newer
  /// release in the background (never during a lecture). The check itself is
  /// a single HTTPS GET to the release feed.
  bool autoUpdate;

  /// True when anything at all would leave the device. The record and session
  /// screens read this to tell the teacher before audio or text is sent.
  bool get usesCloud =>
      summarizer == SummarizerKind.cloud || transcriber == TranscriberKind.cloud;

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
  static const _llm = 'llmSize';
  static const _sum = 'summarizer';
  static const _asrKind = 'transcriber';
  static const _provider = 'cloudProviderId';
  static const _key = 'cloudApiKey';
  static const _url = 'cloudBaseUrl';
  static const _chatModel = 'cloudChatModel';
  static const _asrModel = 'cloudTranscribeModel';
  static const _del = 'deleteAudioAfterTranscribe';
  static const _autoUpdate = 'autoUpdate';

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      asrSize: AsrModelSize.values.firstWhere(
        (e) => e.name == p.getString(_asr),
        orElse: () => AsrModelSize.small,
      ),
      llmSize: LlmModelSize.values.firstWhere(
        (e) => e.name == p.getString(_llm),
        orElse: () => LlmModelSize.small,
      ),
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
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_asr, asrSize.name);
    await p.setString(_llm, llmSize.name);
    await p.setString(_sum, summarizer.name);
    await p.setString(_asrKind, transcriber.name);
    await p.setString(_provider, cloudProviderId);
    await p.setString(_key, cloudApiKey);
    await p.setString(_url, cloudBaseUrl);
    await p.setString(_chatModel, cloudChatModel);
    await p.setString(_asrModel, cloudTranscribeModel);
    await p.setBool(_del, deleteAudioAfterTranscribe);
    await p.setBool(_autoUpdate, autoUpdate);
  }
}
