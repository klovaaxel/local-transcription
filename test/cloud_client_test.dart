import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lecture_local/cloud/openai_compatible.dart';

const _config = CloudConfig(
  baseUrl: 'https://api.berget.ai/v1',
  apiKey: 'sk-test',
  chatModel: 'meta-llama/Llama-3.3-70B-Instruct',
  transcribeModel: 'KBLab/kb-whisper-large',
);

void main() {
  test('chat posts an OpenAI-compatible body and reads the reply', () async {
    late http.Request sent;
    final client = OpenAiCompatibleClient(
      config: _config,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Ett underlag'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final text = await client.chat(
      turns: const [ChatTurn.system('regler'), ChatTurn.user('transkript')],
    );

    expect(text, 'Ett underlag');
    expect(sent.url.toString(), 'https://api.berget.ai/v1/chat/completions');
    expect(sent.headers['Authorization'], 'Bearer sk-test');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'meta-llama/Llama-3.3-70B-Instruct');
    expect(body['stream'], false);
    expect(body['temperature'], 0.2);
    expect((body['messages'] as List).first, {
      'role': 'system',
      'content': 'regler',
    });
  });

  test('a trailing slash in the base url does not double up', () async {
    late Uri url;
    final client = OpenAiCompatibleClient(
      config: const CloudConfig(
        baseUrl: 'https://api.berget.ai/v1/',
        apiKey: 'sk-test',
        chatModel: 'm',
        transcribeModel: 'w',
      ),
      client: MockClient((request) async {
        url = request.url;
        return http.Response(jsonEncode({'data': []}), 200);
      }),
    );

    await client.listModels();
    expect(url.toString(), 'https://api.berget.ai/v1/models');
  });

  test('transcribe uploads the wav as multipart with sv', () async {
    late http.BaseRequest sent;
    late String body;
    final client = OpenAiCompatibleClient(
      config: _config,
      client: MockClient((request) async {
        sent = request;
        body = request.body;
        return http.Response(
          jsonEncode({'text': 'Hej på er'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final text = await client.transcribe(
      audio: Uint8List.fromList([1, 2, 3, 4]),
      fileName: 'del-1.wav',
    );

    expect(text, 'Hej på er');
    expect(
      sent.url.toString(),
      'https://api.berget.ai/v1/audio/transcriptions',
    );
    expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    expect(body, contains('KBLab/kb-whisper-large'));
    expect(body, contains('del-1.wav'));
    expect(body, contains('name="language"'));
  });

  test(
    'a rejected key becomes a Swedish message with the provider detail',
    () async {
      final client = OpenAiCompatibleClient(
        config: _config,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Invalid API key'},
            }),
            401,
          );
        }),
      );

      await expectLater(
        client.chat(turns: const [ChatTurn.user('x')]),
        throwsA(
          isA<CloudException>()
              .having((e) => e.message, 'message', contains('API-nyckeln'))
              .having((e) => e.message, 'message', contains('Invalid API key')),
        ),
      );
    },
  );

  test('an empty key never reaches the network', () async {
    var called = false;
    final client = OpenAiCompatibleClient(
      config: const CloudConfig(
        baseUrl: 'https://api.berget.ai/v1',
        apiKey: '  ',
        chatModel: 'm',
        transcribeModel: 'w',
      ),
      client: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.chat(turns: const [ChatTurn.user('x')]),
      throwsA(isA<CloudException>()),
    );
    expect(called, isFalse);
  });

  test('a plain-http base url is refused before any request', () async {
    var called = false;
    final client = OpenAiCompatibleClient(
      config: const CloudConfig(
        baseUrl: 'http://api.berget.ai/v1',
        apiKey: 'sk-test',
        chatModel: 'm',
        transcribeModel: 'w',
      ),
      client: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.listModels(),
      throwsA(
        isA<CloudException>().having(
          (e) => e.message,
          'message',
          contains('https'),
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('listModels returns sorted ids', () async {
    final client = OpenAiCompatibleClient(
      config: _config,
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'openai/whisper-large-v3'},
              {'id': 'KBLab/kb-whisper-large'},
            ],
          }),
          200,
        );
      }),
    );

    expect(await client.listModels(), [
      'KBLab/kb-whisper-large',
      'openai/whisper-large-v3',
    ]);
  });
}
