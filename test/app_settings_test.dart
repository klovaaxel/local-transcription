import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/data/app_settings.dart';
import 'package:lecture_local/models/model_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'llm catalog keeps 1.5B, adds 3B for phones and 7B as the desk option',
    () {
      expect(
        ModelCatalog.llm(LlmModelSize.small).file.fileName,
        contains('1.5b'),
      );
      expect(
        ModelCatalog.llm(LlmModelSize.medium).file.fileName,
        contains('3b'),
      );
      expect(ModelCatalog.llmLarge.files, hasLength(2));
      expect(ModelCatalog.llmLarge.file.fileName, contains('00001-of-00002'));
      expect(
        ModelCatalog.llmLarge.shards.single.fileName,
        contains('00002-of-00002'),
      );
      expect(
        ModelCatalog.llmLarge.contextSize,
        greaterThan(ModelCatalog.llmSmall.contextSize),
      );
    },
  );

  test('auto model pick: 3B on phones, 7B on desktop', () {
    expect(
      AppSettings().effectiveLlmSize,
      LlmModelSize.large,
      reason: 'the test host is a desktop OS',
    );
    expect(
      AppSettings(autoLlm: false, llmSize: LlmModelSize.small).effectiveLlmSize,
      LlmModelSize.small,
      reason: 'a manual pick wins over the device default',
    );
  });

  test('auto speech model: kb-whisper-medium on desktops, manual wins', () {
    expect(
      AppSettings().effectiveAsrSize,
      AsrModelSize.medium,
      reason: 'the test host is a desktop OS with several cores',
    );
    expect(
      AppSettings(autoAsr: false, asrSize: AsrModelSize.small).effectiveAsrSize,
      AsrModelSize.small,
      reason: 'a manual pick wins over the device default',
    );
  });

  test('a weak CPU benchmark downgrades the automatic picks', () {
    expect(
      AppSettings(cpuScoreMbs: 112).effectiveLlmSize,
      LlmModelSize.large,
      reason: 'the reference desktop stays on 7B',
    );
    expect(
      AppSettings(cpuScoreMbs: 20).effectiveLlmSize,
      LlmModelSize.medium,
      reason: 'a CPU-only 7B brief would take minutes',
    );
    expect(AppSettings(cpuScoreMbs: 20).effectiveAsrSize, AsrModelSize.small);
  });
  test('persists the measured GPU preference for the local brief', () async {
    SharedPreferences.setMockInitialValues({});
    final gpu = AppSettings()..llmGpuOffload = true;
    await gpu.save();
    expect((await AppSettings.load()).llmGpuOffload, isTrue);

    SharedPreferences.setMockInitialValues({});
    final cpu = AppSettings()..llmGpuOffload = false;
    await cpu.save();
    expect((await AppSettings.load()).llmGpuOffload, isFalse);

    SharedPreferences.setMockInitialValues({});
    final unset = AppSettings()..llmGpuOffload = null;
    await unset.save();
    expect((await AppSettings.load()).llmGpuOffload, isNull);
  });

  test(
    'the decode-speed bench downgrades a slow tier before the first brief',
    () {
      final fast = AppSettings();
      expect(
        fast.applyLlmSpeedBench(5, LlmModelSize.large),
        isFalse,
        reason: 'the measured reference desktop does ~5 tok/s on the 7B',
      );
      expect(fast.effectiveLlmSize, LlmModelSize.large);

      final slow = AppSettings();
      expect(slow.applyLlmSpeedBench(1.5, LlmModelSize.large), isTrue);
      expect(slow.effectiveLlmSize, LlmModelSize.medium);

      final manual = AppSettings(autoLlm: false, llmSize: LlmModelSize.large);
      expect(
        manual.applyLlmSpeedBench(1.5, LlmModelSize.large),
        isFalse,
        reason: 'manual picks are never second-guessed',
      );
    },
  );

  test(
    'calibration downgrades a slow tier and manual picks are untouched',
    () async {
      SharedPreferences.setMockInitialValues({});

      final slowLlm = AppSettings();
      final changed = slowLlm.applyLlmCalibration(5000);
      expect(changed, isTrue);
      expect(slowLlm.effectiveLlmSize, LlmModelSize.medium);

      final fastLlm = AppSettings();
      expect(fastLlm.applyLlmCalibration(20), isFalse);
      expect(fastLlm.effectiveLlmSize, LlmModelSize.large);

      final manual = AppSettings(autoLlm: false, llmSize: LlmModelSize.large);
      expect(manual.applyLlmCalibration(5000), isFalse);
      expect(
        manual.effectiveLlmSize,
        LlmModelSize.large,
        reason: 'manual picks are never second-guessed',
      );

      final slowAsr = AppSettings(cpuScoreMbs: 112);
      expect(slowAsr.applyAsrCalibration(12), isTrue);
      expect(slowAsr.effectiveAsrSize, AsrModelSize.small);
    },
  );

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
