import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../cloud/openai_compatible.dart';
import '../models/model_catalog.dart';
import 'brief_pipeline.dart';
import 'brief_sections.dart';

export 'brief_pipeline.dart' show BriefProgress;

const briefGenerationOptions = GenerationOptions(
  temperature: 0.2,
  topP: 0.9,
  topK: 20,
  maxTokens: 768,
  repeatPenalty: 1.08,
);

class LocalLlmSummarizer extends BriefPipeline {
  LocalLlmSummarizer({
    required this.modelPath,
    this.spec = ModelCatalog.llmSmall,
    super.onProgress,
    super.specs,
    super.useFewShot,
    super.useKeyLines,
    super.useKeyLineHints,
    super.useRetryPass,
    super.useVerifyPass,
    super.seed,
    super.onMapRaw,
    this.temperature,
    this.repeatPenalty = 1.08,
    this.gpuLayers,
  });

  /// Sampling temperature override for quality A/Bs; null keeps the
  /// pipeline default (0.2).
  final double? temperature;

  /// Raise if the small model falls into a repetition loop on fragmented
  /// whispered transcripts; 1.08 is the tuned default for the 7B.
  final double repeatPenalty;

  /// Explicit GPU layer count, or null for the platform default
  /// ([gpuLayersFor]). The phone auto policy writes this from the measured
  /// decode probe: on Android and iOS the app keeps whichever of CPU and
  /// GPU was actually faster, because a phone GPU can lose to its own CPU.
  final int? gpuLayers;

  /// Selection output cap for this model: the pass writes line numbers
  /// only, so it is tiny — but it never exceeds a quarter of the window.
  int get keyLinesTokens {
    final cap = spec.contextSize ~/ 4;
    return keySelectMaxTokens < cap ? keySelectMaxTokens : cap;
  }

  final String modelPath;
  final LlmModelSpec spec;

  LlamaCppChatRepository? _repo;

  @override
  int get chunkCharBudget => llmChunkCharBudget(
    contextSize: spec.contextSize,
    compactMaxChars: spec.compactMaxChars,
    promptChars: _promptChars,
    // The cleaning pass decodes up to [keyLinesTokens] tokens beside the
    // chunk before the brief call; reserve room for it, or an over-full
    // chunk fails decode against a full KV cache.
    extraReservedTokens: useKeyLines ? keyLinesTokens + 256 : 0,
  );

  /// The fixed prompt around a map chunk: system prompt, few-shot pair and
  /// the part header, as close as it can be known before rendering.
  int get _promptChars =>
      briefSystemPrompt(specs).length + briefFewShotAssistant(specs).length;

  @override
  Future<void> prepare() async {
    // The plugin submits the whole rendered prompt as ONE llama_decode batch,
    // and llama.cpp asserts n_tokens <= n_batch (ggml_abort -> SIGABRT, the
    // whole app dies). Default batchSize is 512 tokens, far under a lecture
    // chunk, so n_batch must be allowed to take the full window. llama.cpp
    // caps n_batch at n_ctx, so contextSize is the largest safe value.
    _repo = LlamaCppChatRepository.withModelPath(
      modelPath,
      contextSize: spec.contextSize,
      batchSize: spec.contextSize,
      nGpuLayers: gpuLayers ?? gpuLayersFor(spec.size),
    );
  }

  @override
  Future<void> release() async {
    _repo?.dispose();
    _repo = null;
  }

  @override
  Future<String> complete(
    List<ChatTurn> turns, {
    bool longOutput = false,
  }) async {
    final repo = _repo;
    if (repo == null) {
      throw StateError('Språkmodellen är inte laddad.');
    }
    final buffer = StringBuffer();
    await for (final chunk in repo.streamChatWithGenerationOptions(
      'model',
      messages: [for (final turn in turns) _message(turn)],
      generationOptions: longOutput
          ? briefGenerationOptions.copyWith(
              maxTokens: keyLinesTokens,
              seed: seed,
            )
          : briefGenerationOptions.copyWith(
              temperature: temperature,
              repeatPenalty: repeatPenalty,
              seed: seed,
            ),
    )) {
      final piece = chunk.message?.content;
      if (piece != null && piece.isNotEmpty) {
        buffer.write(piece);
      }
    }
    return buffer.toString();
  }

  LLMMessage _message(ChatTurn turn) {
    return LLMMessage(role: _role(turn.role), content: turn.content);
  }

  LLMRole _role(ChatRole role) {
    switch (role) {
      case ChatRole.system:
        return LLMRole.system;
      case ChatRole.user:
        return LLMRole.user;
      case ChatRole.assistant:
        return LLMRole.assistant;
    }
  }
}

int gpuLayersFor(LlmModelSize size) {
  if (Platform.isAndroid) {
    // Surprisingly, this is a sensible default; the decode probe measures
    // CPU vs Vulkan per device and rewrites [AppSettings.llmGpuOffload].
    return 0;
  }
  // iOS ships llama.cpp with Metal; everything else is a desktop with
  // GPU offload enabled in the prebuilt bundle.
  return 99;
}
