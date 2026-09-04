import 'dart:io';

import '../cloud/openai_compatible.dart';
import 'transcript_merge.dart';
import 'wav_chunker.dart';

typedef TranscribeProgress = void Function(int completed, int total);

/// Transcribes a finished recording through a Whisper-compatible endpoint —
/// `KBLab/kb-whisper-large` on Berget AI by default.
///
/// This is the only place audio leaves the device, and it is reachable only
/// after the teacher picks cloud transcription in settings. Live captions
/// stay on device; there is no streaming upload.
class CloudTranscriber {
  CloudTranscriber({
    required this.config,
    OpenAiCompatibleClient? client,
    this.onProgress,
    this.language = 'sv',
  }) : _client = client ?? OpenAiCompatibleClient(config: config),
       _ownsClient = client == null;

  final CloudConfig config;
  final TranscribeProgress? onProgress;
  final String language;
  final OpenAiCompatibleClient _client;
  final bool _ownsClient;

  Future<String> transcribeFile(String wavPath) async {
    final file = File(wavPath);
    if (!await file.exists()) {
      throw CloudException('Ingen ljudfil att transkribera.');
    }
    final chunker = await WavChunker.open(file);
    try {
      final total = chunker.count;
      var text = '';
      for (var i = 0; i < total; i++) {
        onProgress?.call(i + 1, total);
        final part = await _client.transcribe(
          audio: await chunker.part(i),
          fileName: 'del-${i + 1}.wav',
          language: language,
        );
        text = i == 0
            ? part.trim()
            : mergeOverlappingTranscript(text, part.trim());
      }
      return text;
    } finally {
      if (_ownsClient) {
        _client.close();
      }
    }
  }
}
