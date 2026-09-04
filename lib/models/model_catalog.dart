enum AsrModelSize { small, medium }

enum LlmModelSize { small, large }

enum SummarizerKind { local, cloud }

enum TranscriberKind { local, cloud }

/// An OpenAI-compatible inference provider. Berget AI is the EU default;
/// `custom` lets a school point at its own endpoint.
class CloudProvider {
  const CloudProvider({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.chatModel,
    required this.transcribeModel,
    required this.note,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String chatModel;
  final String transcribeModel;
  final String note;
}

class CloudCatalog {
  /// Swedish provider, EU-hosted, OpenAI-compatible. Model ids are editable
  /// because providers rename them; "Testa anslutning" lists what is live.
  static const berget = CloudProvider(
    id: 'berget',
    label: 'Berget AI (Sverige)',
    baseUrl: 'https://api.berget.ai/v1',
    chatModel: 'meta-llama/Llama-3.3-70B-Instruct',
    transcribeModel: 'KBLab/kb-whisper-large',
    note: 'Svensk leverantör, EU-drift. KB-Whisper large för svenska.',
  );

  static const custom = CloudProvider(
    id: 'custom',
    label: 'Egen leverantör',
    baseUrl: '',
    chatModel: '',
    transcribeModel: '',
    note: 'Valfri tjänst med OpenAI-kompatibelt API inom EU.',
  );

  static const all = [berget, custom];

  static CloudProvider byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => berget);
  }
}

class RemoteFile {
  const RemoteFile({required this.fileName, required this.url});

  final String fileName;
  final String url;
}

class LlmModelSpec {
  const LlmModelSpec({
    required this.size,
    required this.label,
    required this.file,
    this.shards = const [],
    required this.contextSize,
    required this.compactMaxChars,
    this.storageLabel,
  });

  final LlmModelSize size;
  final String label;
  final RemoteFile file;
  final List<RemoteFile> shards;
  final int contextSize;
  final int compactMaxChars;
  final String? storageLabel;

  List<RemoteFile> get files => [file, ...shards];

  String get downloadedName => storageLabel ?? file.fileName;
}

class AsrModelSpec {
  const AsrModelSpec({
    required this.size,
    required this.label,
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final AsrModelSize size;
  final String label;
  final RemoteFile encoder;
  final RemoteFile decoder;
  final RemoteFile tokens;
}

class ModelCatalog {
  static const kbWhisperBase =
      'https://huggingface.co/frictional123/sherpa-onnx-kb-whisper-int8/resolve/main';

  static const sileroVad = RemoteFile(
    fileName: 'silero_vad.onnx',
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  );

  static const llmSmall = LlmModelSpec(
    size: LlmModelSize.small,
    label: 'Qwen 1.5B (telefon, ~1,1 GB)',
    file: RemoteFile(
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    ),
    contextSize: 4096,
    compactMaxChars: 8000,
  );

  static const llmLarge = LlmModelSpec(
    size: LlmModelSize.large,
    label: 'Qwen 7B (dator, ~4,7 GB)',
    file: RemoteFile(
      fileName: 'qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf',
    ),
    shards: [
      RemoteFile(
        fileName: 'qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf',
        url:
            'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf',
      ),
    ],
    contextSize: 8192,
    compactMaxChars: 24000,
    storageLabel: 'qwen2.5-7b-instruct-q4_k_m (2 filer)',
  );

  static LlmModelSpec llm(LlmModelSize size) {
    return size == LlmModelSize.large ? llmLarge : llmSmall;
  }

  static const small = AsrModelSpec(
    size: AsrModelSize.small,
    label: 'KB-Whisper small (svenska, ~376 MB)',
    encoder: RemoteFile(
      fileName: 'kb-whisper-small-encoder.int8.onnx',
      url: '$kbWhisperBase/kb-whisper-small-encoder.int8.onnx',
    ),
    decoder: RemoteFile(
      fileName: 'kb-whisper-small-decoder.int8.onnx',
      url: '$kbWhisperBase/kb-whisper-small-decoder.int8.onnx',
    ),
    tokens: RemoteFile(
      fileName: 'kb-whisper-small-tokens.txt',
      url: '$kbWhisperBase/kb-whisper-small-tokens.txt',
    ),
  );

  static const medium = AsrModelSpec(
    size: AsrModelSize.medium,
    label: 'KB-Whisper medium (svenska, ~947 MB)',
    encoder: RemoteFile(
      fileName: 'kb-whisper-medium-encoder.int8.onnx',
      url: '$kbWhisperBase/kb-whisper-medium-encoder.int8.onnx',
    ),
    decoder: RemoteFile(
      fileName: 'kb-whisper-medium-decoder.int8.onnx',
      url: '$kbWhisperBase/kb-whisper-medium-decoder.int8.onnx',
    ),
    tokens: RemoteFile(
      fileName: 'kb-whisper-medium-tokens.txt',
      url: '$kbWhisperBase/kb-whisper-medium-tokens.txt',
    ),
  );

  static AsrModelSpec asr(AsrModelSize size) {
    return size == AsrModelSize.medium ? medium : small;
  }
}
