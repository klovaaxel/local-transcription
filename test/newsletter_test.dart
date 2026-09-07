import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/cloud/openai_compatible.dart';
import 'package:lecture_local/models/model_catalog.dart';
import 'package:lecture_local/summarize/brief_pipeline.dart';
import 'package:lecture_local/summarize/brief_sections.dart';
import 'package:lecture_local/summarize/newsletter.dart';

void main() {
  test('parses the three Swedish platform-brief sections', () {
    const raw = '''
## Vad som togs upp
Prov i fredag och kapitel 4.

## Datum, prov och uppgifter
Diagnos onsdag. Läxa s. 42–45.

## För frånvarande och vårdnadshavare
Ta med miniräknare.
''';
    final summary = NewsletterSummary.parseModelOutput(raw);
    expect(summary.discussed, contains('Prov i fredag'));
    expect(summary.decided, contains('Diagnos onsdag'));
    expect(summary.absentees, contains('miniräknare'));
  });

  test('still reads the old newsletter headings', () {
    const raw = '''
## Vad som diskuterades
Prov i fredag och kapitel 4.

## Vad som beslutades
Inlämning flyttas till måndag.

## Vad de som inte var där behöver veta
Ta med miniräknare.
''';
    final summary = NewsletterSummary.parseModelOutput(raw);
    expect(summary.discussed, contains('Prov i fredag'));
    expect(summary.decided, contains('Inlämning flyttas'));
    expect(summary.absentees, contains('miniräknare'));
  });

  test('does not invent sections when the model dumps prose', () {
    final summary = NewsletterSummary.parseModelOutput('Bara löptext.');
    expect(summary.discussed, 'Bara löptext.');
    expect(summary.decided, NewsletterSummary.emptyPlaceholder);
    expect(summary.absentees, NewsletterSummary.emptyPlaceholder);
  });

  test('a placeholder line inside a filled section is stripped, not kept', () {
    const raw = '''
## Vad som togs upp
Virtualisering och hypervisorer.

## Datum, prov och uppgifter
20 frågor. Avslutar lektionen med ett prov.
Inget tydligt i transkriptet.

## För frånvarande och vårdnadshavare
Inget tydligt i transkriptet.
''';
    final summary = NewsletterSummary.parseModelOutput(raw);
    expect(summary.decided, contains('20 frågor'));
    expect(summary.decided, isNot(contains('Inget tydligt')));
  });

  test('parses only the requested sections, in their prompt order', () {
    const raw = '''
## Vad som togs upp
Virtualisering och hypervisorer.

## Datum, prov och uppgifter
Prov med 20 frågor, ingen tidpunkt given.

## Nästa lektion
Vi fortsätter med Vagrant.

## För frånvarande och vårdnadshavare
Ta med dator.
''';
    final summary = NewsletterSummary.parseModelOutput(
      raw,
      headings: [
        'Vad som togs upp',
        'Datum, prov och uppgifter',
        'Nästa lektion',
      ],
    );
    expect(summary.sections.map((s) => s.heading), [
      'Vad som togs upp',
      'Datum, prov och uppgifter',
      'Nästa lektion',
    ]);
    expect(summary.absentees, '');
    expect(summary.toMarkdown(), contains('Vagrant'));
    expect(summary.toMarkdown(), isNot(contains('Ta med dator')));
  });

  test('compactTranscriptForLlm keeps head and tail', () {
    final long = 'a' * 20000;
    final compact = compactTranscriptForLlm(long, maxChars: 14000);
    expect(compact.length, lessThan(long.length));
    expect(compact.startsWith('aaa'), isTrue);
    expect(compact.contains('[...]'), isTrue);
    expect(compact.endsWith('aaa'), isTrue);
  });

  test('drops preamble and fences before the first heading', () {
    const raw = '''
Här är underlaget:
```markdown
## Vad som togs upp
Bråk.

## Datum, prov och uppgifter
Inget tydligt i transkriptet.

## För frånvarande och vårdnadshavare
Ta med linjal.
```
''';
    final summary = NewsletterSummary.parseModelOutput(raw);
    expect(summary.discussed, 'Bråk.');
    expect(summary.decided, NewsletterSummary.emptyPlaceholder);
    expect(summary.absentees, 'Ta med linjal.');
  });

  test(
    'few-shot assistant uses the empty placeholder when dates are missing',
    () {
      final summary = NewsletterSummary.parseModelOutput(
        briefFewShotAssistant(BriefSectionCatalog.defaultSpecs),
      );
      expect(summary.discussed, 'Procent och moms.');
      expect(summary.decided, NewsletterSummary.emptyPlaceholder);
      expect(summary.absentees, contains('linjal'));
    },
  );

  group('brief sections', () {
    test('the overview is locked and always first', () {
      final resolved = BriefSectionCatalog.resolve(['concepts', 'nextLesson']);
      expect(resolved.first.id, 'overview');
      expect(resolved.map((s) => s.id), ['overview', 'nextLesson', 'concepts']);
    });

    test('unknown ids are dropped, catalog order wins', () {
      final resolved = BriefSectionCatalog.resolve([
        'concepts',
        'ghost',
        'schedule',
      ]);
      expect(resolved.map((s) => s.id), ['overview', 'schedule', 'concepts']);
    });

    test('the default ids produce the classic three-section brief', () {
      final resolved = BriefSectionCatalog.resolve(
        BriefSectionCatalog.defaultIds,
      );
      expect(resolved, BriefSectionCatalog.defaultSpecs);
    });

    test(
      'the schedule instruction is per tier: detail for 7B, simple for 3B',
      () {
        final sevenB = BriefSectionCatalog.resolveFor(
          LlmModelSize.large,
          BriefSectionCatalog.defaultIds,
        );
        final threeB = BriefSectionCatalog.resolveFor(
          LlmModelSize.medium,
          BriefSectionCatalog.defaultIds,
        );
        expect(
          sevenB.firstWhere((s) => s.id == 'schedule').instruction,
          contains('antal frågor'),
        );
        expect(
          threeB.firstWhere((s) => s.id == 'schedule').instruction,
          isNot(contains('antal frågor')),
        );
        expect(
          sevenB.map((s) => s.heading),
          threeB.map((s) => s.heading),
          reason: 'only the instruction wording differs, never the sections',
        );
      },
    );

    test('system prompt lists the enabled headings in order', () {
      final prompt = briefSystemPrompt(
        BriefSectionCatalog.resolve(['overview', 'schedule', 'nextLesson']),
      );
      final order = [
        prompt.indexOf('## Vad som togs upp'),
        prompt.indexOf('## Datum, prov och uppgifter'),
        prompt.indexOf('## Nästa lektion'),
      ];
      expect(order.every((i) => i >= 0), isTrue);
      expect([order[0] < order[1], order[1] < order[2]], everyElement(isTrue));
      expect(prompt, contains('Hitta inte på'));
      expect(prompt, contains(NewsletterSummary.emptyPlaceholder));
    });

    test('reduce prompt mentions the first enabled section', () {
      final prompt = briefReduceSystemPrompt(
        BriefSectionCatalog.resolve(['overview', 'concepts']),
      );
      expect(prompt, contains('## Nya begrepp'));
      expect(prompt, contains('Behåll'));
    });

    test('few-shot follows the enabled sections', () {
      final text = briefFewShotAssistant(
        BriefSectionCatalog.resolve(['overview', 'schedule', 'nextLesson']),
      );
      expect(text, contains('## Nästa lektion'));
      expect(text, contains(NewsletterSummary.emptyPlaceholder));
      final parsed = NewsletterSummary.parseModelOutput(
        text,
        headings: [
          'Vad som togs upp',
          'Datum, prov och uppgifter',
          'Nästa lektion',
        ],
      );
      expect(parsed.decided, NewsletterSummary.emptyPlaceholder);
    });

    test('map turns carry part headers, few-shot toggle keeps the shape', () {
      final turns = briefMapTurns(
        BriefSectionCatalog.defaultSpecs,
        'Transkripttext.',
        part: 2,
        of: 3,
      );
      expect(turns.first.role, ChatRole.system);
      expect(turns.last.content, contains('del 2 av 3'));
      expect(turns.length, 4);

      final bare = briefMapTurns(
        BriefSectionCatalog.defaultSpecs,
        'Transkripttext.',
        useFewShot: false,
      );
      expect(bare.length, 2);
    });
  });

  test('short transcripts stay a single chunk', () {
    const text = 'Vi gick igenom bråk. Prov på fredag.';
    expect(splitTranscriptForLlm(text, maxChars: 8000), [text]);
  });

  group('key-line hints', () {
    test('picks prov, läxa and material lines verbatim', () {
      const transcript =
          'Idag talar vi om virtualisering. Sen avslutar vi med ett prov. '
          'Det är 20 frågor. Vi tittar på lampstacken. '
          'Läs kapitel 4 till nästa gång. Ta med miniräknare.';
      final hints = keyLineHints(transcript);
      expect(hints, contains('avslutar vi med ett prov'));
      expect(hints, contains('Läs kapitel 4'));
      expect(hints, contains('Ta med miniräknare'));
    });

    test('skips ordinary teaching lines', () {
      const transcript = 'Virtualisering är användbart. Datorer är fina.';
      expect(keyLineHints(transcript), isEmpty);
    });

    test('clamps very long whisper runs at a word boundary', () {
      var line = 'provet kommer ${'ord ' * 200}här';
      final hints = keyLineHints(line);
      expect(hints.length, lessThan(400));
      expect(hints, isNot(endsWith(' ')));
    });

    test('transcript lines are numbered and round-trip verbatim', () {
      const text =
          'Första meningen. Andra meningen är länge — den mycket långa '
          'meningen fortsätter med flera ord så att den bör klyvas i rader.';
      final lines = transcriptLines(text);
      expect(lines, isNotEmpty);
      final numbered = numberedTranscript(text);
      expect(numbered, startsWith('1. '));
      final restored = selectTranscriptLines(text, [
        for (var i = 1; i <= lines.length; i++) i,
      ]);
      expect(
        restored.replaceAll(RegExp(r'\s+'), ' '),
        text.replaceAll(RegExp(r'\s+'), ' '),
      );
    });

    test('out-of-range line numbers are dropped', () {
      const text = 'Prov på fredag. Vi läser kapitel 4.';
      final restored = selectTranscriptLines(text, [1, 99, 0]);
      expect(restored, 'Prov på fredag.');
    });
  });

  test('a two-hour-sized transcript keeps the middle', () {
    const marker = 'PROV_I_MITTEN_FREDAG';
    final lecture = '${'Inledning. ' * 4000}$marker. ${'Avslutning. ' * 4000}';
    final budget = llmChunkCharBudget(contextSize: 4096, compactMaxChars: 8000);
    final chunks = splitTranscriptForLlm(lecture, maxChars: budget);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.length <= budget), isTrue);
    expect(chunks.any((c) => c.contains(marker)), isTrue);
    expect(
      compactTranscriptForLlm(lecture, maxChars: budget),
      isNot(contains(marker)),
    );
    expect(chunks.first, startsWith('Inledning.'));
    expect(chunks.last, contains('Avslutning.'));
  });

  test('a bigger prompt reserves more of the context window', () {
    final small = llmChunkCharBudget(
      contextSize: 4096,
      compactMaxChars: 8000,
      promptChars: 900,
    );
    final large = llmChunkCharBudget(
      contextSize: 4096,
      compactMaxChars: 8000,
      promptChars: 1600,
    );
    expect(large, lessThan(small));
  });

  test('reduce prompt keeps dates that only one part mentioned', () {
    final prompt = newsletterReduceUserPrompt([
      NewsletterSummary.legacy(discussed: 'Bråk.'),
      NewsletterSummary.legacy(
        decided: 'Prov på fredag.',
        absentees: 'Ta med linjal.',
      ),
    ]);
    expect(prompt, contains('Prov på fredag.'));
  });

  group('serialization', () {
    test('round-trips extra sections', () {
      const summary = NewsletterSummary(
        sections: [
          BriefSection(heading: 'Vad som togs upp', body: 'Virtualisering.'),
          BriefSection(heading: 'Nya begrepp', body: 'Hypervisor.'),
        ],
      );
      final restored = NewsletterSummary.fromJson(summary.toJson());
      expect(restored.sections.length, 2);
      expect(restored.bodyOf('Nya begrepp'), 'Hypervisor.');
      expect(restored.autoTitle, 'Virtualisering');
    });

    test('reads the legacy three-key summary', () {
      final restored = NewsletterSummary.fromJson({
        'discussed': 'Bråk och procent.',
        'decided': 'Prov på fredag.',
        'absentees': 'Läs kapitel 4.',
      });
      expect(restored.decided, 'Prov på fredag.');
      expect(restored.autoTitle, 'Bråk och procent');
    });

    test('new files keep the legacy keys readable by an older app', () {
      const summary = NewsletterSummary(
        sections: [
          BriefSection(heading: 'Vad som togs upp', body: 'Git.'),
          BriefSection(
            heading: 'Datum, prov och uppgifter',
            body: 'Inlämning måndag.',
          ),
          BriefSection(
            heading: 'För frånvarande och vårdnadshavare',
            body: 'Läs s. 4.',
          ),
        ],
      );
      final json = summary.toJson();
      expect(json['decided'], 'Inlämning måndag.');
      expect(json['absentees'], 'Läs s. 4.');
    });
  });

  group('autoTitle', () {
    NewsletterSummary of(String discussed) =>
        NewsletterSummary.legacy(discussed: discussed);

    test('a colon marks the topic and wins over length', () {
      expect(
        of(
          'Unionsupplösningen 1905: bakgrunden, konsulatfrågan och '
          'Karlstadskonventionen. Vi läste källtexten.',
        ).autoTitle,
        'Unionsupplösningen 1905',
      );
    });

    test('a short first line is the name as written', () {
      expect(of('Bråk och procent').autoTitle, 'Bråk och procent');
    });

    test('does not split on the period in a Swedish abbreviation', () {
      expect(of('Vi gick igenom kap. 4').autoTitle, 'Vi gick igenom kap. 4');
    });

    test('a long line is cut on a word boundary', () {
      final title = of(
        'Vi repeterade bråk och procent inför provet och räknade tillsammans',
      ).autoTitle!;
      expect(title.length, lessThanOrEqualTo(48));
      expect(title, endsWith('…'));
      expect(title, startsWith('Vi repeterade bråk och procent'));
      expect(title, isNot(contains('  ')));
    });

    test('takes the first bullet, without its marker', () {
      expect(
        of('- Bråk och procent\n- Uppgift 3 till 7').autoTitle,
        'Bråk och procent',
      );
    });

    test('an empty brief leaves the lecture unnamed', () {
      expect(of(NewsletterSummary.emptyPlaceholder).autoTitle, isNull);
      expect(of('   ').autoTitle, isNull);
    });
  });

  group('brief quality passes', () {
    String? retry(NewsletterSummary s, String hints) =>
        BriefPipeline.retryInstructionFor(
          s,
          BriefSectionCatalog.defaultSpecs,
          hints,
        );

    test('fires when prov hints exist but the schedule section is empty', () {
      const hints = '- sen avslutar vi med ett prov\n- Det är 20 frågor';
      final draft = NewsletterSummary.parseModelOutput(
        '## Vad som togs upp\nVirtualisering.\n'
        '## Datum, prov och uppgifter\nInget tydligt i transkriptet.\n'
        '## För frånvarande och vårdnadshavare\nInget tydligt i transkriptet.',
      );
      final instruction = retry(draft, hints);
      expect(instruction, isNotNull);
      expect(instruction, contains('Datum, prov och uppgifter'));
    });

    test('stays quiet when the draft covers what the hints found', () {
      const hints = '- sen avslutar vi med ett prov';
      final draft = NewsletterSummary.parseModelOutput(
        '## Vad som togs upp\nVirtualisering.\n'
        '## Datum, prov och uppgifter\nProv med 20 frågor.\n'
        '## För frånvarande och vårdnadshavare\nInget tydligt i transkriptet.',
      );
      expect(retry(draft, hints), isNull);
    });

    test('no hints, no retry', () {
      final draft = NewsletterSummary.parseModelOutput('');
      expect(retry(draft, ''), isNull);
    });
  });
}
