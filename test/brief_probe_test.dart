// Quality harness. Runs the feedback transcript plus the synthetic golden
// lectures through the real pipeline for each candidate (model x sampling x
// instruction), scores each brief mechanically, and appends a table to
// feedback/quality/SCORES.md. Planted facts in the golden lectures make
// detection an exact metric instead of substring luck.
//
// Skipped by default; run explicitly with:
//   $env:LLM_PROBE='1'; $env:LLM_MODELS_DIR='C:\Temp\llm-models';
//   flutter test test/brief_probe_test.dart
// LLM_PROBE_RUNS=N runs each row N times with pinned seeds per run.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lecture_local/models/model_catalog.dart';
import 'package:lecture_local/summarize/brief_sections.dart';
import 'package:lecture_local/summarize/local_summarizer.dart';
import 'package:lecture_local/summarize/newsletter.dart';

/// Real fragmented lecture from the field, plus synthetic golden lectures
/// with planted facts. The planted substrings are what a GOOD brief must
/// carry through — rewording may gentlify the sentence but the facts
/// (weekday, number, chapter) survive rewriting.
class Golden {
  const Golden(this.label, this.path, this.planted);
  final String label;
  final String path;
  final List<String> planted;
}

final corpus = <Golden>[
  Golden('kfn (verklighet)', 'feedback/kfn-om_virtualisering.txt', [
    'prov',
    '20 frågor',
  ]),
  Golden('fysik (golden)', 'feedback/golden/golden1_fysik.txt', [
    'torsdag',
    '20 frågor',
    'kapitel 8',
    'miniräknare',
  ]),
  Golden('historia (golden)', 'feedback/golden/golden2_historia.txt', [
    'måndag',
    'uppsats',
    'kapitel 7',
    'sida 84',
  ]),
];

/// Sampling/instruction rows under test.
class Row {
  const Row(this.tag, {this.temperature, this.specs});
  final String tag;
  final double? temperature;
  final List<BriefSectionSpec>? specs;
}

/// A schedule instruction that asks for the prov DETAILS spelled out —
/// shipped for the large tier ([BriefSectionCatalog.resolveFor]); the row
/// keeps it under harness as a regression check.
final rows = <Row>[
  Row('base'),
  Row('temp0', temperature: 0.0),
  Row(
    'provdetail',
    specs: [
      BriefSectionCatalog.overview,
      BriefSectionCatalog.scheduleDetail,
      BriefSectionCatalog.absentees,
    ],
  ),
];

final candidates = <LlmModelSpec>[
  ModelCatalog.llmMedium,
  ModelCatalog.llmLarge,
];

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

class Score {
  Score(
    this.model,
    this.rowTag,
    this.run,
    this.lecture,
    this.elapsed,
    this.plantedHits,
    this.plantedTotal,
    this.emptySections,
    this.overviewWords,
  );

  final String model;
  final String rowTag;
  final int run;
  final String lecture;
  final Duration elapsed;
  final int plantedHits;
  final int plantedTotal;
  final int emptySections;
  final int overviewWords;

  @override
  String toString() =>
      '| $model | $rowTag | $run | $lecture | ${elapsed.inSeconds}s '
      '| $plantedHits/$plantedTotal | $emptySections | $overviewWords |';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'quality harness: corpus x rows x runs',
    () async {
      final runs =
          int.tryParse(Platform.environment['LLM_PROBE_RUNS'] ?? '') ?? 1;
      final modelsDir =
          Platform.environment['LLM_MODELS_DIR'] ?? r'C:\Temp\llm-models';
      final dumpDir = Directory('feedback/quality/dumps')
        ..createSync(recursive: true);

      final table = StringBuffer()
        ..writeln(
          '| Model | Rad | Run | Föreläsning | Tid | Fakta | Tomma | Översiktsord |',
        )
        ..writeln('|---|---|---|---|---|---|---|---|');

      for (final spec in candidates) {
        for (final row in rows) {
          for (final golden in corpus) {
            final transcript = await File(golden.path).readAsString();
            for (var run = 1; run <= runs; run++) {
              final modelPath = File('$modelsDir/${spec.file.fileName}').path;
              expect(
                File(modelPath).existsSync(),
                isTrue,
                reason: 'missing model file: $modelPath',
              );
              final sw = Stopwatch()..start();
              final summarizer = LocalLlmSummarizer(
                modelPath: modelPath,
                spec: spec,
                specs: row.specs ?? BriefSectionCatalog.defaultSpecs,
                useKeyLineHints: true,
                seed: run * 97 + 13,
                temperature: row.temperature,
                onMapRaw: (stage, raw) {
                  final safeStage = stage.replaceAll(RegExp(r'\W+'), '-');
                  final safeLecture = golden.label.replaceAll(
                    RegExp(r'[^a-zA-Z0-9åäöÅÄÖ]+'),
                    '-',
                  );
                  File(
                    '${dumpDir.path}/${spec.label.replaceAll(' ', '_')}_${row.tag}_${safeLecture}_r${run}_$safeStage.md',
                  ).writeAsStringSync(raw);
                },
              );
              final summary = await summarizer.summarize(transcript);
              sw.stop();

              final briefText = _normalize(summary.toMarkdown());
              final plantedHits = golden.planted
                  .where((f) => briefText.contains(_normalize(f)))
                  .length;
              final emptySections = summary.sections
                  .where(
                    (s) => s.body.trim() == NewsletterSummary.emptyPlaceholder,
                  )
                  .length;
              final words = summary.discussed
                  .split(RegExp(r'\s+'))
                  .where((w) => w.isNotEmpty)
                  .length;

              final score = Score(
                spec.label,
                row.tag,
                run,
                golden.label,
                sw.elapsed,
                plantedHits,
                golden.planted.length,
                emptySections,
                words,
              );
              stdout.writeln(score);
              table.writeln(score);

              await File(
                'feedback/quality/${spec.label.replaceAll(' ', '_')}_${row.tag}_${golden.label.split(' ').first}_r$run.md',
              ).writeAsString('''
# ${spec.label} · ${row.tag} · ${golden.label} · run $run

- model: `${spec.file.fileName}`, context ${spec.contextSize}, temp ${row.temperature ?? '0.2 (default)'}
- planted facts: $plantedHits/${golden.planted.length} of ${golden.planted.join(', ')}
- elapsed: ${sw.elapsed}

---

${summary.toMarkdown()}
''');
            }
          }
        }
      }

      await File('feedback/quality/SCORES.md').writeAsString(table.toString());
    },
    timeout: const Timeout(Duration(hours: 3)),
    skip: Platform.environment['LLM_PROBE'] != '1',
  );
}
