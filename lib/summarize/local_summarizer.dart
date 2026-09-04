import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../cloud/openai_compatible.dart';
import '../models/model_catalog.dart';
import 'brief_pipeline.dart';
import 'newsletter.dart';

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
  });

  final String modelPath;
  final LlmModelSpec spec;

  LlamaCppChatRepository? _repo;

  @override
  int get chunkCharBudget => llmChunkCharBudget(
    contextSize: spec.contextSize,
    compactMaxChars: spec.compactMaxChars,
  );

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
      nGpuLayers: gpuLayersFor(spec.size),
    );
  }

  @override
  Future<void> release() async {
    _repo?.dispose();
    _repo = null;
  }

  @override
  Future<String> complete(List<ChatTurn> turns) async {
    final repo = _repo;
    if (repo == null) {
      throw StateError('Språkmodellen är inte laddad.');
    }
    final buffer = StringBuffer();
    await for (final chunk in repo.streamChatWithGenerationOptions(
      'model',
      messages: [for (final turn in turns) _message(turn)],
      generationOptions: briefGenerationOptions,
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
  if (size == LlmModelSize.large) {
    return 99;
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return 99;
  }
  return 0;
}
