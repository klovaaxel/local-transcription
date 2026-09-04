import 'package:flutter_test/flutter_test.dart';
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

  test('few-shot assistant uses the empty placeholder when dates are missing', () {
    final summary = NewsletterSummary.parseModelOutput(
      newsletterFewShotAssistant(),
    );
    expect(summary.discussed, 'Procent och moms.');
    expect(summary.decided, NewsletterSummary.emptyPlaceholder);
    expect(summary.absentees, contains('linjal'));
  });

  test('system prompt names the three brief headings', () {
    final prompt = newsletterSystemPrompt();
    expect(prompt, contains(NewsletterSummary.discussedHeading));
    expect(prompt, contains(NewsletterSummary.decidedHeading));
    expect(prompt, contains(NewsletterSummary.absenteesHeading));
    expect(prompt, contains('Hitta inte på'));
  });

  test('short transcripts stay a single chunk', () {
    const text = 'Vi gick igenom bråk. Prov på fredag.';
    expect(splitTranscriptForLlm(text, maxChars: 8000), [text]);
  });

  test('a two-hour-sized transcript keeps the middle', () {
    const marker = 'PROV_I_MITTEN_FREDAG';
    final lecture = '${'Inledning. ' * 4000}$marker. ${'Avslutning. ' * 4000}';
    final budget = llmChunkCharBudget(
      contextSize: 4096,
      compactMaxChars: 8000,
    );
    final chunks = splitTranscriptForLlm(lecture, maxChars: budget);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.length <= budget), isTrue);
    expect(chunks.any((c) => c.contains(marker)), isTrue);
    expect(compactTranscriptForLlm(lecture, maxChars: budget), isNot(contains(marker)));
    expect(chunks.first, startsWith('Inledning.'));
    expect(chunks.last, contains('Avslutning.'));
  });

  test('reduce prompt keeps dates that only one part mentioned', () {
    final prompt = newsletterReduceSystemPrompt();
    expect(prompt, contains('Behåll datum'));
    expect(
      newsletterReduceUserPrompt(const [
        NewsletterSummary(
          discussed: 'Bråk.',
          decided: NewsletterSummary.emptyPlaceholder,
          absentees: NewsletterSummary.emptyPlaceholder,
        ),
        NewsletterSummary(
          discussed: NewsletterSummary.emptyPlaceholder,
          decided: 'Prov på fredag.',
          absentees: 'Ta med linjal.',
        ),
      ]),
      contains('Prov på fredag.'),
    );
  });

  group('autoTitle', () {
    NewsletterSummary of(String discussed) => NewsletterSummary(
      discussed: discussed,
      decided: NewsletterSummary.emptyPlaceholder,
      absentees: NewsletterSummary.emptyPlaceholder,
    );

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
}
