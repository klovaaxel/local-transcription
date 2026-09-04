import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/data/app_settings.dart';
import 'package:lecture_local/models/model_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('llm catalog keeps 1.5B as default and 7B as the desk option', () {
    expect(ModelCatalog.llm(LlmModelSize.small).file.fileName, contains('1.5b'));
    expect(ModelCatalog.llmLarge.files, hasLength(2));
    expect(
      ModelCatalog.llmLarge.file.fileName,
      contains('00001-of-00002'),
    );
    expect(
      ModelCatalog.llmLarge.shards.single.fileName,
      contains('00002-of-00002'),
    );
    expect(ModelCatalog.llmLarge.contextSize, greaterThan(ModelCatalog.llmSmall.contextSize));
  });

  test('cloud defaults point at Berget AI but nothing is switched on', () {
    final settings = AppSettings();
    expect(settings.summarizer, SummarizerKind.local);
    expect(settings.transcriber, TranscriberKind.local);
    expect(settings.usesCloud, isFalse);
    expect(settings.liveCaptionsEnabled, isTrue);
    expect(settings.cloudBaseUrl, CloudCatalog.berget.baseUrl);
    expect(settings.cloudTranscribeModel, contains('kb-whisper'));
    expect(settings.cloudApiKey, isEmpty);
  });

  test('cloud transcription turns live captions off', () {
    final settings = AppSettings(transcriber: TranscriberKind.cloud);
    expect(settings.liveCaptionsEnabled, isFalse);
    expect(settings.usesCloud, isTrue);
  });

  test('a preset rewrites url and models, a custom provider keeps them', () {
    final settings = AppSettings(
      cloudBaseUrl: 'https://eget.example/v1',
      cloudChatModel: 'egen-modell',
    );

    settings.applyProvider(CloudCatalog.custom);
    expect(settings.cloudProviderId, 'custom');
    expect(settings.cloudBaseUrl, 'https://eget.example/v1');
    expect(settings.cloudChatModel, 'egen-modell');

    settings.applyProvider(CloudCatalog.berget);
    expect(settings.cloudBaseUrl, CloudCatalog.berget.baseUrl);
    expect(settings.cloudChatModel, CloudCatalog.berget.chatModel);
  });

  test('persists the cloud provider across a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      summarizer: SummarizerKind.cloud,
      transcriber: TranscriberKind.cloud,
      cloudApiKey: 'sk-test',
      cloudBaseUrl: 'https://eget.example/v1',
      cloudChatModel: 'egen-chatt',
      cloudTranscribeModel: 'egen-tal',
      cloudProviderId: 'custom',
    );
    await settings.save();

    final loaded = await AppSettings.load();
    expect(loaded.summarizer, SummarizerKind.cloud);
    expect(loaded.transcriber, TranscriberKind.cloud);
    expect(loaded.cloudApiKey, 'sk-test');
    expect(loaded.cloudBaseUrl, 'https://eget.example/v1');
    expect(loaded.cloudChatModel, 'egen-chatt');
    expect(loaded.cloudTranscribeModel, 'egen-tal');
    expect(loaded.cloudProviderId, 'custom');
  });

  test('an old install without cloud keys stays local', () async {
    SharedPreferences.setMockInitialValues({'asrSize': 'medium'});
    final loaded = await AppSettings.load();
    expect(loaded.asrSize, AsrModelSize.medium);
    expect(loaded.usesCloud, isFalse);
    expect(loaded.cloudBaseUrl, CloudCatalog.berget.baseUrl);
  });

  test('persists llm size', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(llmSize: LlmModelSize.large);
    await settings.save();

    final loaded = await AppSettings.load();
    expect(loaded.llmSize, LlmModelSize.large);
    expect(loaded.asrSize, AsrModelSize.small);
  });
}
