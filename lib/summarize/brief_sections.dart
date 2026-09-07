import '../cloud/openai_compatible.dart';
import '../models/model_catalog.dart';
import 'newsletter.dart';

/// The brief's sections are data. A teacher enables or disables blocks in
/// settings; the system prompt, the reduce prompt, the output parser, the
/// JSON store and the session screen are all composed from the same list.
///
/// A section is deliberately a heading plus ONE instruction line. Short
/// instructions keep the small on-device model on track, and keep the prompt
/// reservation in [llmChunkCharBudget] predictable.
class BriefSectionSpec {
  const BriefSectionSpec({
    required this.id,
    required this.heading,
    required this.instruction,
    this.locked = false,
    this.defaultEnabled = false,
  });

  final String id;
  final String heading;

  /// The one-line rule the model gets for this section.
  final String instruction;

  /// The overview names the lecture (autoTitle) and anchors the brief, so it
  /// is always present and always first.
  final bool locked;
  final bool defaultEnabled;
}

abstract final class BriefSectionCatalog {
  static const overview = BriefSectionSpec(
    id: 'overview',
    heading: 'Vad som togs upp',
    instruction:
        'Ämnen och innehåll som togs upp. Inte datum, prov eller läxor.',
    locked: true,
    defaultEnabled: true,
  );

  static const schedule = BriefSectionSpec(
    id: 'schedule',
    heading: 'Datum, prov och uppgifter',
    instruction:
        'Endast prov, inlämningar, läxor och datum som faktiskt sägs. '
        'Nämn ett prov även om ingen tidpunkt sägs. Inget annat.',
    defaultEnabled: true,
  );

  /// The same block for the large tier: it can take the extra instruction to
  /// spell out prov DETAILS (antal frågor, tid). The harness measured 16/16
  /// planted facts with this wording on the 7B, while the 3B lost a fact —
  /// hence per-tier instructions, chosen for the small one (see
  /// [resolveFor] and test/brief_probe_test.dart).
  static const scheduleDetail = BriefSectionSpec(
    id: 'schedule',
    heading: 'Datum, prov och uppgifter',
    instruction:
        'Endast prov, inlämningar, läxor och datum som faktiskt sägs. Nämn '
        'ett prov även om ingen tidpunkt sägs, och skriv ut detaljer som '
        'sägs om det, till exempel antal frågor eller hur lång tid det tar. '
        'Inget annat.',
    defaultEnabled: true,
  );

  static const absentees = BriefSectionSpec(
    id: 'absentees',
    heading: 'För frånvarande och vårdnadshavare',
    instruction:
        'Vad den som missade lektionen behöver göra, läsa eller ta med.',
    defaultEnabled: true,
  );

  static const nextLesson = BriefSectionSpec(
    id: 'nextLesson',
    heading: 'Nästa lektion',
    instruction:
        'Vad som sägs om nästa lektion: innehåll och förberedelser, '
        'till exempel att läsa ett kapitel eller skriva ut material. Inget annat.',
  );

  static const concepts = BriefSectionSpec(
    id: 'concepts',
    heading: 'Nya begrepp',
    instruction:
        'Fackbegrepp som togs upp i lektionen, var och en med en kort '
        'förklaring från orden i transkriptet. Hitta inte på förklaringar.',
  );

  /// Catalog order is prompt order; the catalog is the whole surface for
  /// what a brief can contain.
  static const all = [overview, schedule, absentees, nextLesson, concepts];

  /// Section ids enabled for a fresh install.
  static const defaultIds = ['overview', 'schedule', 'absentees'];

  /// The default brief, resolved ([BriefSectionCatalog.resolve] of
  /// [defaultIds]) — the shape every brief has had until now.
  static const defaultSpecs = [overview, schedule, absentees];

  /// Resolves stored ids into prompt order. The overview is always included
  /// (locked); unknown and disabled ids are dropped; catalog order wins over
  /// stored order.
  static List<BriefSectionSpec> resolve(List<String> ids) {
    final enabled = ids.toSet();
    return [
      for (final spec in all)
        if (spec.locked || enabled.contains(spec.id)) spec,
    ];
  }

  /// [resolve] with the schedule instruction chosen for the model tier: the
  /// 7B gets the detail-spelling wording (measured 16/16 planted facts), the
  /// 3B keeps the simple one (the detail wording loses a fact there).
  static List<BriefSectionSpec> resolveFor(
    LlmModelSize size,
    List<String> ids,
  ) {
    return [
      for (final spec in resolve(ids))
        if (spec.id == schedule.id)
          size == LlmModelSize.large ? scheduleDetail : schedule
        else
          spec,
    ];
  }
}

String briefSystemPrompt(List<BriefSectionSpec> specs) {
  final buffer = StringBuffer();
  buffer.write("""
Du skriver ett underlag från en svensk föreläsning som läraren klistrar in i skolplattformen.
Svara ENDAST med dessa rubriker, i denna ordning, med korta meningar eller punktlistor:
""");
  for (final spec in specs) {
    buffer
      ..writeln()
      ..write('## ${spec.heading}')
      ..writeln()
      ..write(spec.instruction);
  }
  buffer
    ..writeln()
    ..writeln()
    ..writeln('Regler:')
    ..writeln('- Svenska, kort, sakligt.')
    ..writeln(
      '- Hitta inte på datum, namn, prov eller fakta som inte finns i transkriptet.',
    )
    ..writeln('- Kopiera inte transkriptet. Sammanfatta.')
    ..writeln(
      '- Om en del saknar underlag, skriv exakt: ${NewsletterSummary.emptyPlaceholder}',
    )
    ..write('- Ingen inledning, ingen avslutning, inga kodstängsel.');
  return buffer.toString();
}

String briefReduceSystemPrompt(List<BriefSectionSpec> specs) {
  final buffer = StringBuffer();
  buffer.write("""
Du slår ihop delunderlag från en lång föreläsning till ETT underlag läraren klistrar in i skolplattformen.
Svara ENDAST med dessa rubriker, i denna ordning:
""");
  for (final spec in specs) {
    buffer
      ..writeln()
      ..write('## ${spec.heading}');
  }
  buffer
    ..writeln()
    ..writeln()
    ..writeln('Regler:')
    ..writeln('- Svenska, kort, sakligt.')
    ..writeln(
      '- Behåll prov, datum, uppgifter och "ta med" från ALLA delar. '
      'Om en del saknar något men en annan har det, behåll det som finns.',
    )
    ..writeln(
      '- Slå ihop "${specs.first.heading}" till en kort översikt i '
      'ungefär den ordning det togs upp. Ta bort dubbletter.',
    )
    ..writeln('- Hitta inte på något som inte står i delarna.')
    ..writeln(
      '- Om inget finns i någon del, skriv exakt: ${NewsletterSummary.emptyPlaceholder}',
    )
    ..write('- Ingen inledning, ingen avslutning, inga kodstängsel.');
  return buffer.toString();
}

//! The few-shot pair teaches the exact output shape. Its example bodies are
//! deliberately banal; see the quality notes in test/brief_probe_test.dart.
const briefFewShotTranscript =
    'Vi räknade procent och moms. Ta med linjal nästa gång.';

String briefFewShotAssistant(List<BriefSectionSpec> specs) {
  final buffer = StringBuffer();
  var first = true;
  for (final spec in specs) {
    buffer.write(first ? '' : '\n\n');
    first = false;
    buffer
      ..write('## ${spec.heading}')
      ..writeln()
      ..write(_fewShotBodyFor(spec.id));
  }
  return buffer.toString();
}

String _fewShotBodyFor(String id) {
  switch (id) {
    case 'overview':
      return 'Procent och moms.';
    case 'absentees':
      return 'Ta med linjal nästa gång.';
    default:
      return NewsletterSummary.emptyPlaceholder;
  }
}

/// The cleaning pass's system prompt. The task is selection, not summarizing
/// and not copying: the model writes line numbers only, and Dart reassembles
/// the kept lines verbatim. Noise removal therefore costs ~50 decode tokens
/// instead of a full copy — and can never rewrite or invent anything.
String extractSystemPrompt() {
  return """
Du väljer ut rader ur ett rörigt transkript av en svensk lektion.
Svara ENDAST med radnumren för rader som innehåller:

- skolämne eller undervisning: begrepp, förklaringar, exempel, instruktioner,
- prov, test, diagnos, läxa, kapitel, sida, uppgift, inlämning, tid
  (veckodag, datum, klockslag) eller material som ska med ("ta med").

Hoppa över rader med småprat, skämt, repliker från eleverna och upprepningar.
Svara med ett radnummer per rad, inget annat. Ta med ALLT undervisningsinnehåll
— hellre en rad för mycket än en för lite.
""";
}

/// Output cap for the line-selection pass: the model writes line numbers
/// only, so 512 is far more than an 80-line transcript needs, while the
/// pipeline reserves room for it in [llmChunkCharBudget].
const keySelectMaxTokens = 512;

/// The self-edit pass's system prompt. The editor only LOOSENS problems in
/// the draft (echoed transcript lines, missed schedule items); it may not
/// shorten the overview into nothing or invent anything. Parsing accepts the
/// result only when it has fewer gaps than the draft, see [BriefPipeline].
String verifySystemPrompt(List<BriefSectionSpec> specs) {
  final buffer = StringBuffer();
  buffer.write("""
Du redigerar ett underlag från en svensk lektion mot transkriptet.
Rätta ENDAST följande, annars behåller du underlaget oförändrat:

- meningar som är kopierade ordagrant ur transkriptet skrivs kort i egna ord,
- prov, inlämningar, läxor och material som sägs i transkriptet men saknas
  i underlaget läggs in under rubriken för datum, prov och uppgifter,
- rubrikerna ska vara exakt dessa, i denna ordning:
""");
  for (final spec in specs) {
    buffer
      ..writeln()
      ..write('## ${spec.heading}');
  }
  buffer
    ..writeln()
    ..writeln()
    ..writeln('Regler:')
    ..writeln(
      '- Hitta inte på datum, namn, prov eller fakta som inte finns i transkriptet.',
    )
    ..writeln('- Rör inte det som redan står, förutom punkterna ovan.')
    ..writeln(
      '- Saknas det fortfarande underlag för en rubrik, skriv exakt: '
      '${NewsletterSummary.emptyPlaceholder}',
    )
    ..write('- Ingen inledning, ingen avslutning, inga kodstängsel.');
  return buffer.toString();
}

/// MaxOutput budget for Brief. Brief generation options, the JSON store and
/// the session screen all come back to this constant.
const briefMaxTokens = 768;

/// Turns a rendered map step into chat turns, so the pipeline and any
/// experiment run exactly the same prompt.
List<ChatTurn> briefMapTurns(
  List<BriefSectionSpec> specs,
  String transcript, {
  bool useFewShot = true,
  String? keyLineHints,
  int? part,
  int? of,
}) {
  final turns = <ChatTurn>[ChatTurn.system(briefSystemPrompt(specs))];
  if (useFewShot) {
    turns
      ..add(ChatTurn.user('Transkript:\n$briefFewShotTranscript'))
      ..add(ChatTurn.assistant(briefFewShotAssistant(specs)));
  }
  turns.add(
    ChatTurn.user(
      newsletterUserPrompt(transcript, part: part, of: of, hints: keyLineHints),
    ),
  );
  return turns;
}

List<ChatTurn> briefReduceTurns(
  List<BriefSectionSpec> specs,
  List<NewsletterSummary> parts,
) {
  return [
    ChatTurn.system(briefReduceSystemPrompt(specs)),
    ChatTurn.user(newsletterReduceUserPrompt(parts)),
  ];
}

/// Characters of transcript that fit beside the prompt and the output.
///
/// The *3 chars/token estimate is deliberately conservative: fragmented
/// whisper Swedish tokenizes worse than normal prose (~2.2 chars/token at
/// worst), and an over-full chunk now fails decode instead of crashing.
///
/// [promptChars] is the full fixed prompt around a chunk (system prompt,
/// few-shot, part headers). Its token estimate is added to the output budget.
int llmChunkCharBudget({
  required int contextSize,
  required int compactMaxChars,
  int promptChars = 900,
  int extraReservedTokens = 0,
}) {
  final reserved =
      briefMaxTokens + (promptChars * 10 ~/ 25) + 200 + extraReservedTokens;
  return ((contextSize - reserved) * 22 ~/ 10).clamp(2500, compactMaxChars);
}
