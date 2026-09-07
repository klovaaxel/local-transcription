// Hardware verification of the decode probe (skipped without LLM_PROBE=1):
// measures real tokens/s on the models in LLM_MODELS_DIR so the threshold
// in AppSettings.llmSlowTokPerSec stays grounded in measurements.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lecture_local/models/model_catalog.dart';
import 'package:lecture_local/perf/llm_speed_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final spec in [ModelCatalog.llmMedium, ModelCatalog.llmLarge]) {
    test(
      'decode probe: ${spec.label}',
      () async {
        final modelsDir =
            Platform.environment['LLM_MODELS_DIR'] ?? r'C:\Temp\llm-models';
        final path = '$modelsDir/${spec.file.fileName}';
        final tok = await LlmSpeedProbe.tokPerSec(modelPath: path, spec: spec);
        expect(tok, greaterThan(0));
        // ignore: avoid_print
        print('DECODE ${spec.label}: ${tok.toStringAsFixed(1)} tokens/s');
      },
      skip: Platform.environment['LLM_PROBE'] != '1'
          ? 'set LLM_PROBE=1 to run against real models'
          : null,
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
