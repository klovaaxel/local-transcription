import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/cloud/openai_compatible.dart';
import 'package:lecture_local/summarize/brief_pipeline.dart';
import 'package:lecture_local/summarize/cloud_summarizer.dart';
import 'package:lecture_local/summarize/summarizer.dart';

/// A pipeline with no model behind it, so cancellation can be tested without
/// loading gigabytes. [complete] counts calls and can be told to stop the
/// teacher mid-lecture.
class FakeBrief extends BriefPipeline {
  FakeBrief({required this.onChunk});

  /// Runs between chunks, i.e. what `cancelBrief` would reach from the UI.
  final void Function(int chunk) onChunk;

  final completed = <String>[];
  int completions = 0;
  int prepared = 0;
  int released = 0;

  /// Small on purpose: a chunk budget this size splits the lecture below into
  /// several parts, which is the only state where a cancel has somewhere to
  /// land between two chunks. It has to clear the overlap `splitTranscriptForLlm`
  /// requires, or the splitter cannot make a single window at all.
  @override
  int get chunkCharBudget => 600;

  @override
  Future<void> prepare() async => prepared++;

  /// Releasing is what actually stops a local decode, so it must happen even
  /// when cancellation unwinds -- that is the whole reason cancel can be
  /// instant in its effect rather than just its reporting.
  @override
  Future<void> release() async => released++;

  @override
  Future<String> complete(List<ChatTurn> turns, {bool longOutput = false}) async {
    completions++;
    onChunk(completions);
    completed.add(turns.last.content);
    return 'Vad som togs upp\nIngen substans.';
  }
}

/// Enough transcript to split into several map parts at a small budget, so the
/// chunk loop has somewhere to be interrupted.
/// Several times [FakeBrief.chunkCharBudget], so the splitter really does
/// produce more than one window. One window would make a cancel unobservable:
/// there is no boundary for it to land on.
String lecture({int chunks = 12}) {
  return List.filled(
    chunks,
    'Föreläsningsdag med lång förklaring om historia som rymmer mer än fyrtio tecken.',
  ).join('\n\n');
}

void main() {
  group('cancellation', () {
    test('a brief that is never cancelled finishes and releases once', () async {
      final brief = FakeBrief(onChunk: (_) {});
      final summary = await brief.summarize(lecture());

      expect(summary.discussed, 'Ingen substans.');
      expect(brief.prepared, 1);
      expect(brief.released, 1);
      expect(brief.cancelled, isFalse);
    });

    test('cancelling between chunks stops before the work is done', () async {
      late FakeBrief brief;
      brief = FakeBrief(onChunk: (chunk) {
        // From the UI this is a tap; here it lands between two decodes.
        if (chunk == 2) {
          brief.cancel();
        }
      });

      await expectLater(
        brief.summarize(lecture()),
        throwsA(isA<BriefCancelled>()),
      );
      expect(brief.completions, lessThan(3));
    });

    test('cancelling releases the model, because that is what stops the decode',
        () async {
      late FakeBrief brief;
      brief = FakeBrief(onChunk: (chunk) {
        if (chunk == 1) {
          brief.cancel();
        }
      });

      await expectLater(
        brief.summarize(lecture()),
        throwsA(isA<BriefCancelled>()),
      );
      // Without this the CPU would stay pinned after the teacher walked away,
      // which is the failure mode cancel exists to avoid.
      expect(brief.released, 1);
    });

    test('a cancel before the first chunk costs no decode at all', () async {
      late FakeBrief brief;
      brief = FakeBrief(onChunk: (_) => brief.cancel());

      // Cancelled before any chunk is reachable, so nothing runs at all.
      brief.cancel();
      await expectLater(
        brief.summarize(lecture()),
        throwsA(isA<BriefCancelled>()),
      );
      expect(brief.completions, 0);
      expect(brief.released, 1);
    });

    test('cancelled is observable, so the UI can hide its button', () async {
      final brief = FakeBrief(onChunk: (_) {});
      expect(brief.cancelled, isFalse);
      brief.cancel();
      expect(brief.cancelled, isTrue);
    });
  });

  group('a real backend honours the interface', () {
    test('CloudSummarizer accepts and records a cancel', () {
      // The cloud path has no chunk loop of its own, but it must still satisfy
      // the interface the UI drives -- otherwise `cancelBrief` is a
      // compile-time lie for cloud users.
      final summarizer = CloudSummarizer(
        config: const CloudConfig(
          baseUrl: 'https://example.invalid/v1',
          apiKey: 'x',
          chatModel: 'x',
          transcribeModel: 'x',
        ),
        specs: const [],
      );
      expect(summarizer, isA<Summarizer>());
      summarizer.cancel();
      expect(summarizer.cancelled, isTrue);
    });
  });
}