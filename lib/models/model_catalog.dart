enum AsrModelSize { small, medium, large }

enum LlmModelSize { small, medium, large }

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
    url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  );

  static const llmSmall = LlmModelSpec(
    size: LlmModelSize.small,
    label: 'Qwen 3.5 2B (telefon, ~1,3 GB)',
    file: RemoteFile(
      fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
    ),
    contextSize: 4096,
    compactMaxChars: 8000,
  );

  /// The phone default under auto pick: the A/B harness (test/
  /// brief_probe_test.dart, feedback/quality/SCORES.md) showed the middle
  /// tier keeps the Qwen prompt-following the smallest tier lacks, at a size
  /// a phone GPU can still decode. The Qwen2.5 measurement behind that pick
  /// predates this generation — re-run the harness before trusting it for
  /// Qwen3.5-4B.
  static const llmMedium = LlmModelSpec(
    size: LlmModelSize.medium,
    label: 'Qwen 3.5 4B (mobil, ~2,7 GB)',
    file: RemoteFile(
      fileName: 'Qwen3.5-4B-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
    ),
    contextSize: 8192,
    compactMaxChars: 12000,
  );

  /// Desktop default: the SAME 4B weights as [llmMedium], with a window wide
  /// enough for a 45-minute lecture in one chunk (no map/reduce merge, which
  /// is where the 3B used to drop the prov). Same GGUF on purpose — the
  /// teacher downloads 2.7 GB once, and both tiers then differ only in how
  /// much fits per pass.
  ///
  /// Qwen3.5-9B was evaluated here and rejected on measurement, not taste:
  /// Q4_K_M (5.68 GB) cannot get a context on a 6 GB card, and the only
  /// smaller rung that fits (UD-IQ3_XXS, 3.83 GB) hard-crashes inside
  /// prefill on this llama.cpp build for the qwen35 hybrid architecture —
  /// at 16384 and 8192, on Vulkan and CPU. A model that cannot load or
  /// prefill is worse than a smaller model that can, so the large tier
  /// prefers a window over a parameter count. Do not retry the 9B without
  /// a llama.cpp build where IQ3 prefill survives; the size ladder has no
  /// rung that both fits 6 GB and runs.
  static const llmLarge = LlmModelSpec(
    size: LlmModelSize.large,
    label: 'Qwen 3.5 4B, stort fönster (dator, ~2,7 GB)',
    file: RemoteFile(
      fileName: 'Qwen3.5-4B-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
    ),
    contextSize: 16384,
    compactMaxChars: 24000,
  );

  static LlmModelSpec llm(LlmModelSize size) {
    switch (size) {
      case LlmModelSize.small:
        return llmSmall;
      case LlmModelSize.medium:
        return llmMedium;
      case LlmModelSize.large:
        return llmLarge;
    }
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

  /// The best Swedish kb-whisper has, and the desktop default. Same repo
  /// and same three-file layout as [small] and [medium], so it rides the
  /// identical sherpa-onnx path — only the auto pick stays off it on phones,
  /// where ~3x medium's compute per second of audio would crawl.
  static const large = AsrModelSpec(
    size: AsrModelSize.large,
    label: 'KB-Whisper large (svenska, ~1,8 GB)',
    encoder: RemoteFile(
      fileName: 'kb-whisper-large-encoder.int8.onnx',
      url: '$kbWhisperBase/kb-whisper-large-encoder.int8.onnx',
    ),
    decoder: RemoteFile(
      fileName: 'kb-whisper-large-decoder.int8.onnx',
      url: '$kbWhisperBase/kb-whisper-large-decoder.int8.onnx',
    ),
    tokens: RemoteFile(
      fileName: 'kb-whisper-large-tokens.txt',
      url: '$kbWhisperBase/kb-whisper-large-tokens.txt',
    ),
  );

  static AsrModelSpec asr(AsrModelSize size) {
    switch (size) {
      case AsrModelSize.small:
        return small;
      case AsrModelSize.medium:
        return medium;
      case AsrModelSize.large:
        return large;
    }
  }
}
