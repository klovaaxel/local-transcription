import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/app_settings.dart';
import '../models/model_catalog.dart';

/// Where the teacher's text or audio goes when they opt into the cloud.
///
/// Any OpenAI-compatible endpoint works; Berget AI is the EU default in
/// [CloudCatalog]. Nothing here is reachable on the local path — the app
/// only builds a [CloudConfig] after the teacher picks cloud in settings.
class CloudConfig {
  const CloudConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.chatModel,
    required this.transcribeModel,
  });

  factory CloudConfig.fromSettings(AppSettings settings) {
    return CloudConfig(
      baseUrl: settings.cloudBaseUrl,
      apiKey: settings.cloudApiKey,
      chatModel: settings.cloudChatModel,
      transcribeModel: settings.cloudTranscribeModel,
    );
  }

  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String transcribeModel;
}

/// One turn of the brief conversation, provider-agnostic.
enum ChatRole { system, user, assistant }

class ChatTurn {
  const ChatTurn(this.role, this.content);

  const ChatTurn.system(this.content) : role = ChatRole.system;
  const ChatTurn.user(this.content) : role = ChatRole.user;
  const ChatTurn.assistant(this.content) : role = ChatRole.assistant;

  final ChatRole role;
  final String content;

  Map<String, String> toJson() => {'role': role.name, 'content': content};
}

/// A failure the teacher can act on: wrong key, wrong model, no network.
class CloudException implements Exception {
  CloudException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal OpenAI-compatible client: chat completions, audio transcriptions,
/// and the model list used by "Testa anslutning".
class OpenAiCompatibleClient {
  OpenAiCompatibleClient({required this.config, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final CloudConfig config;
  final http.Client _client;
  final bool _ownsClient;

  static const chatTimeout = Duration(minutes: 5);
  static const transcribeTimeout = Duration(minutes: 20);
  static const probeTimeout = Duration(seconds: 30);

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Uri _uri(String path) {
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw CloudException(
        'Ingen adress till leverantören. Fyll i API-adress under Inställningar.',
      );
    }
    final parsed = Uri.tryParse('$base/$path');
    if (parsed == null || !parsed.hasScheme || !parsed.isScheme('https')) {
      throw CloudException(
        'API-adressen måste vara en https-adress, till exempel '
        '${CloudCatalog.berget.baseUrl}.',
      );
    }
    return parsed;
  }

  Map<String, String> get _authHeader {
    final key = config.apiKey.trim();
    if (key.isEmpty) {
      throw CloudException(
        'API-nyckel saknas. Lägg in den under Inställningar, eller välj '
        'lokal modell.',
      );
    }
    return {'Authorization': 'Bearer $key'};
  }

  /// One completion. Returns the assistant text.
  Future<String> chat({
    required List<ChatTurn> turns,
    double temperature = 0.2,
    double topP = 0.9,
    int maxTokens = 900,
  }) async {
    final model = config.chatModel.trim();
    if (model.isEmpty) {
      throw CloudException(
        'Ingen språkmodell vald. Fyll i modellnamn under Inställningar.',
      );
    }
    final response = await _send(
      () => _client.post(
        _uri('chat/completions'),
        headers: {..._authHeader, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'messages': [for (final turn in turns) turn.toJson()],
          'temperature': temperature,
          'top_p': topP,
          'max_tokens': maxTokens,
          'stream': false,
        }),
      ),
      timeout: chatTimeout,
    );

    final body = _decode(response);
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw CloudException('Leverantören svarade utan text.');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw CloudException('Leverantören svarade utan text.');
    }
    return content;
  }

  /// Whisper-compatible transcription of one audio part.
  Future<String> transcribe({
    required Uint8List audio,
    required String fileName,
    String language = 'sv',
  }) async {
    final model = config.transcribeModel.trim();
    if (model.isEmpty) {
      throw CloudException(
        'Ingen talmodell vald. Fyll i modellnamn under Inställningar.',
      );
    }
    final request = http.MultipartRequest('POST', _uri('audio/transcriptions'))
      ..headers.addAll(_authHeader)
      ..fields['model'] = model
      ..fields['language'] = language
      ..fields['response_format'] = 'json'
      ..files.add(
        http.MultipartFile.fromBytes('file', audio, filename: fileName),
      );

    final response = await _send(
      () async => http.Response.fromStream(await _client.send(request)),
      timeout: transcribeTimeout,
    );

    final body = _decode(response);
    final text = body['text'];
    if (text is! String) {
      throw CloudException('Leverantören svarade utan transkription.');
    }
    return text;
  }

  /// Model ids the key can reach. Used to check a connection before class.
  Future<List<String>> listModels() async {
    final response = await _send(
      () => _client.get(_uri('models'), headers: _authHeader),
      timeout: probeTimeout,
    );
    final body = _decode(response);
    final data = body['data'];
    if (data is! List) {
      return const [];
    }
    return [
      for (final entry in data)
        if (entry is Map && entry['id'] is String) entry['id'] as String,
    ]..sort();
  }

  Future<http.Response> _send(
    Future<http.Response> Function() call, {
    required Duration timeout,
  }) async {
    final http.Response response;
    try {
      response = await call().timeout(timeout);
    } on CloudException {
      rethrow;
    } catch (e) {
      throw CloudException(
        'Kunde inte nå leverantören. Kontrollera nätverket och API-adressen. '
        '($e)',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw CloudException(_statusMessage(response));
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Falls through to the shared message below.
    }
    throw CloudException('Kunde inte tolka svaret från leverantören.');
  }

  String _statusMessage(http.Response response) {
    final detail = _errorDetail(response);
    final suffix = detail == null ? '' : ' ($detail)';
    switch (response.statusCode) {
      case 401:
      case 403:
        return 'API-nyckeln avvisades av leverantören.$suffix';
      case 404:
        return 'Adressen eller modellnamnet finns inte hos leverantören.'
            '$suffix';
      case 413:
        return 'Ljudfilen var för stor för leverantören.$suffix';
      case 429:
        return 'Leverantören är upptagen just nu. Försök igen om en stund.'
            '$suffix';
      default:
        if (response.statusCode >= 500) {
          return 'Leverantören svarade med ett fel (${response.statusCode}).'
              '$suffix';
        }
        return 'Anropet misslyckades (${response.statusCode}).$suffix';
    }
  }

  String? _errorDetail(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final error = decoded['error'];
        final message = error is Map ? error['message'] : decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {
      // Body was not JSON; the status code alone has to carry the message.
    }
    final body = response.body.trim();
    if (body.isEmpty) {
      return null;
    }
    return body.length > 160 ? '${body.substring(0, 160)}…' : body;
  }
}
