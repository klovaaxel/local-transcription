import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/data/app_settings.dart';
import 'package:lecture_local/models/model_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'llm catalog ships the Qwen3.5 tiers as single-file Q4_K_M GGUFs',
    () {
      expect(
        ModelCatalog.llm(LlmModelSize.small).file.fileName,
        'Qwen3.5-2B-Q4_K_M.gguf',
      );
      expect(
        ModelCatalog.llm(LlmModelSize.medium).file.fileName,
        'Qwen3.5-4B-Q4_K_M.gguf',
      );
      expect(
        ModelCatalog.llmLarge.files,
        hasLength(1),
        reason: 'every Qwen3.5 GGUF is a single file, not the old two-shard 7B',
      );
      expect(ModelCatalog.llmLarge.shards, isEmpty);
      for (final size in LlmModelSize.values) {
        expect(
          ModelCatalog.llm(size).file.url,
          startsWith('https://huggingface.co/unsloth/Qwen3.5-'),
          reason: 'every tier comes from its unsloth GGUF repo',
        );
      }
      expect(
        ModelCatalog.llmLarge.contextSize,
        greaterThan(ModelCatalog.llmSmall.contextSize),
      );
      expect(
        ModelCatalog.llmMedium.contextSize,
        lessThan(ModelCatalog.llmLarge.contextSize),
        reason:
            'the tiers differ by window, not by weights — the large tier only '
            'earns its name if it fits a whole lecture in one chunk',
      );
    },
  );

  test(
    'no shipped tier is large enough to fail on a 6 GB card',
    () {
      // The Qwen3.5-9B was measured and rejected: 5.68 GB could not get a
      // context at all on a 6 GB laptop GPU, and the smaller IQ3 rung that
      // did fit crashed in prefill. These are the guard against a future tier
      // swap reintroducing a model that cannot load — a test that merely
      // mirrored the catalog's filenames could not catch that.
      for (final size in LlmModelSize.values) {
        final spec = ModelCatalog.llm(size);
        expect(
          spec.contextSize,
          lessThanOrEqualTo(16384),
          reason: '${spec.label}: batchSize mirrors contextSize, and the KV '
              'cache has to fit beside the weights on a small card',
        );
        expect(
          spec.label,
          isNot(contains('9B')),
          reason: 'the 9B tier was measured unloadable or uncrashable on 6 GB '
              'hardware — see the llmLarge doc comment',
        );
      }
    },
  );

  test('auto model pick: 4B on phones, wide window on desktop', () {
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

  test('auto speech model: kb-whisper-large on desktops, manual wins', () {
    expect(
      AppSettings().effectiveAsrSize,
      AsrModelSize.large,
      reason: 'the test host is a desktop OS with several cores',
    );
    expect(
      AppSettings(autoAsr: false, asrSize: AsrModelSize.small).effectiveAsrSize,
      AsrModelSize.small,
      reason: 'a manual pick wins over the device default',
    );
  });

  test('kb-whisper-large is the same three files from the same repo', () {
    final large = ModelCatalog.large;
    expect(large.size, AsrModelSize.large);
    expect(ModelCatalog.asr(AsrModelSize.large), same(large));
    expect(large.encoder.fileName, 'kb-whisper-large-encoder.int8.onnx');
    expect(large.decoder.fileName, 'kb-whisper-large-decoder.int8.onnx');
    expect(large.tokens.fileName, 'kb-whisper-large-tokens.txt');
    for (final file in [large.encoder, large.decoder, large.tokens]) {
      expect(
        file.url,
        contains('/frictional123/sherpa-onnx-kb-whisper-int8/'),
        reason: 'same base URL as the existing tiers, so no new source',
      );
    }
  });

  test('a weak CPU benchmark downgrades the automatic picks', () {
    expect(
      AppSettings(cpuScoreMbs: 112).effectiveLlmSize,
      LlmModelSize.large,
      reason: 'the reference desktop stays on the large brief tier',
    );
    expect(
      AppSettings(cpuScoreMbs: 20).effectiveLlmSize,
      LlmModelSize.medium,
      reason: 'a CPU-only large brief would take minutes',
    );
    expect(
      AppSettings(cpuScoreMbs: 20).effectiveAsrSize,
      AsrModelSize.small,
      reason: 'the weak line demotes any tier the device rule asked for',
    );
    expect(
      AppSettings(cpuScoreMbs: 112).effectiveAsrSize,
      AsrModelSize.large,
      reason: 'a strong desktop keeps kb-whisper-large',
    );
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
        reason: 'the reference desktop does ~5 tok/s on the large tier',
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

      // The speech calibration steps down one tier per measured lecture, so
      // from the new desktop default it takes large -> medium -> small.
      final slowAsr = AppSettings(cpuScoreMbs: 112);
      expect(slowAsr.applyAsrCalibration(12), isTrue);
      expect(slowAsr.effectiveAsrSize, AsrModelSize.medium);
      expect(slowAsr.applyAsrCalibration(12), isTrue);
      expect(slowAsr.effectiveAsrSize, AsrModelSize.small);
      expect(
        slowAsr.applyAsrCalibration(12),
        isFalse,
        reason: 'small is the floor; nothing left to step down to',
      );
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
