import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/model_catalog.dart';

class DownloadProgress {
  const DownloadProgress({
    required this.label,
    required this.received,
    required this.total,
  });

  final String label;
  final int received;
  final int total;

  double? get fraction {
    if (total <= 0) {
      return null;
    }
    return received / total;
  }
}

class ModelDownloader {
  Future<Directory> modelsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'lecture_local', 'models'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> pathFor(String fileName) async {
    return p.join((await modelsDir()).path, fileName);
  }

  Future<bool> isPresent(RemoteFile file) async {
    return File(await pathFor(file.fileName)).exists();
  }

  Future<AsrPaths> ensureAsr({
    required AsrModelSize size,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final spec = ModelCatalog.asr(size);
    await _ensure(spec.encoder, onProgress);
    await _ensure(spec.decoder, onProgress);
    await _ensure(spec.tokens, onProgress);
    await _ensure(ModelCatalog.sileroVad, onProgress);
    return AsrPaths(
      encoder: await pathFor(spec.encoder.fileName),
      decoder: await pathFor(spec.decoder.fileName),
      tokens: await pathFor(spec.tokens.fileName),
      vad: await pathFor(ModelCatalog.sileroVad.fileName),
    );
  }

  Future<String> ensureLlm({
    LlmModelSize size = LlmModelSize.small,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final spec = ModelCatalog.llm(size);
    for (final remote in spec.files) {
      await _ensure(remote, onProgress);
    }
    return pathFor(spec.file.fileName);
  }

  Future<bool> asrReady(AsrModelSize size) async {
    final spec = ModelCatalog.asr(size);
    return await isPresent(spec.encoder) &&
        await isPresent(spec.decoder) &&
        await isPresent(spec.tokens) &&
        await isPresent(ModelCatalog.sileroVad);
  }

  Future<bool> llmReady({LlmModelSize size = LlmModelSize.small}) async {
    final spec = ModelCatalog.llm(size);
    for (final remote in spec.files) {
      if (!await isPresent(remote)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _ensure(
    RemoteFile remote,
    void Function(DownloadProgress progress)? onProgress,
  ) async {
    final dest = File(await pathFor(remote.fileName));
    if (await dest.exists() && await dest.length() > 0) {
      return;
    }
    final tmp = File('${dest.path}.part');
    if (await tmp.exists()) {
      await tmp.delete();
    }
    final request = http.Request('GET', Uri.parse(remote.url));
    request.headers['User-Agent'] = 'lecture_local/1.0';
    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Nedladdning misslyckades (${response.statusCode}) för ${remote.fileName}',
        uri: request.url,
      );
    }
    final total = response.contentLength ?? -1;
    var received = 0;
    final sink = tmp.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(
        DownloadProgress(
          label: remote.fileName,
          received: received,
          total: total,
        ),
      );
    }
    await sink.close();
    if (await dest.exists()) {
      await dest.delete();
    }
    await tmp.rename(dest.path);
  }
}

class AsrPaths {
  const AsrPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
  });

  final String encoder;
  final String decoder;
  final String tokens;
  final String vad;
}
