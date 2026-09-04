import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lecture_local/asr/cloud_transcriber.dart';
import 'package:lecture_local/asr/wav_sink.dart';
import 'package:lecture_local/cloud/openai_compatible.dart';
import 'package:lecture_local/summarize/cloud_summarizer.dart';
import 'package:lecture_local/summarize/newsletter.dart';

const _config = CloudConfig(
  baseUrl: 'https://api.berget.ai/v1',
  apiKey: 'sk-test',
  chatModel: 'meta-llama/Llama-3.3-70B-Instruct',
  transcribeModel: 'KBLab/kb-whisper-large',
);

http.Response _brief(String discussed, String decided, String absentees) {
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {
            'content':
                '## ${NewsletterSummary.discussedHeading}\n$discussed\n\n'
                '## ${NewsletterSummary.decidedHeading}\n$decided\n\n'
                '## ${NewsletterSummary.absenteesHeading}\n$absentees',
          },
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  test('a short lecture is one request', () async {
    var calls = 0;
    final summarizer = CloudSummarizer(
      config: _config,
      client: OpenAiCompatibleClient(
        config: _config,
        client: MockClient((request) async {
          calls++;
          return _brief('Procent och moms.', 'Prov på fredag.', 'Ta linjal.');
        }),
      ),
    );

    final summary = await summarizer.summarize('Vi räknade procent och moms.');

    expect(calls, 1);
    expect(summary.discussed, 'Procent och moms.');
    expect(summary.decided, 'Prov på fredag.');
    expect(summary.absentees, 'Ta linjal.');
  });

  test('a lecture past the window is mapped in parts and then reduced',
      () async {
    final prompts = <String>[];
    final summarizer = CloudSummarizer(
      config: _config,
      client: OpenAiCompatibleClient(
        config: _config,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          prompts.add(
            ((body['messages'] as List).first as Map)['content'] as String,
          );
          return _brief('Del.', 'Inlämning måndag.', 'Läs kapitel 4.');
        }),
      ),
    );

    // Three windows' worth of transcript, on sentence breaks.
    final transcript = List.generate(
      CloudSummarizer.chunkChars ~/ 20 * 3,
      (i) => 'Mening nummer $i om ämnet. ',
    ).join();

    final progress = <String>[];
    final tracked = CloudSummarizer(
      config: _config,
      client: OpenAiCompatibleClient(
        config: _config,
        client: MockClient((request) async {
          return _brief('Del.', 'Inlämning måndag.', 'Läs kapitel 4.');
        }),
      ),
      onProgress: (done, total) => progress.add('$done/$total'),
    );

    final summary = await summarizer.summarize(transcript);
    await tracked.summarize(transcript);

    expect(summary.decided, 'Inlämning måndag.');
    expect(prompts.length, greaterThan(1));
    expect(
      prompts.last,
      contains('slår ihop'),
      reason: 'the last call must be the reduce step, not another part',
    );
    expect(progress.first, endsWith('/${progress.length}'));
  });

  test('a provider error surfaces as a Swedish message', () async {
    final summarizer = CloudSummarizer(
      config: _config,
      client: OpenAiCompatibleClient(
        config: _config,
        client: MockClient((request) async => http.Response('nope', 500)),
      ),
    );

    await expectLater(
      summarizer.summarize('Vi räknade procent.'),
      throwsA(
        isA<CloudException>().having(
          (e) => e.message,
          'message',
          contains('Leverantören'),
        ),
      ),
    );
  });

  group('CloudTranscriber', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cloud_transcriber');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<File> recording(Duration length) async {
      final file = File('${dir.path}/audio.wav');
      final sink = WavFileSink(file);
      await sink.open();
      final second = Uint8List(32000);
      for (var i = 0; i < length.inSeconds; i++) {
        sink.addPcm16(second);
      }
      await sink.close();
      return file;
    }

    test('uploads one part for a short lecture', () async {
      var calls = 0;
      final file = await recording(const Duration(seconds: 4));
      final transcriber = CloudTranscriber(
        config: _config,
        client: OpenAiCompatibleClient(
          config: _config,
          client: MockClient((request) async {
            calls++;
            return http.Response(
              jsonEncode({'text': 'Hej på er.'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );

      expect(await transcriber.transcribeFile(file.path), 'Hej på er.');
      expect(calls, 1);
    });

    test('a missing file never opens a connection', () async {
      var calls = 0;
      final transcriber = CloudTranscriber(
        config: _config,
        client: OpenAiCompatibleClient(
          config: _config,
          client: MockClient((request) async {
            calls++;
            return http.Response('{}', 200);
          }),
        ),
      );

      await expectLater(
        transcriber.transcribeFile('${dir.path}/borta.wav'),
        throwsA(isA<CloudException>()),
      );
      expect(calls, 0);
    });
  });
}
