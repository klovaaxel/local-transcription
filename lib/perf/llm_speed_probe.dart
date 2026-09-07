import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../summarize/local_summarizer.dart';
import '../models/model_catalog.dart';

/// A short, fixed decode that measures the device's real generation speed
/// — GPU, unified memory and all — right after a brief model was
/// downloaded. The tier gate uses this instead of guessing from CPU score:
/// the launch benchmark (DeviceBench) runs before any model is on the
/// device and cannot see the GPU at all.
abstract final class LlmSpeedProbe {
  static const _options = GenerationOptions(
    temperature: 0.2,
    topP: 0.9,
    topK: 20,
    maxTokens: 64,
    repeatPenalty: 1.08,
  );

  /// Generated tokens per second for a small fixed completion, with the
  /// given layer offload. The plugin streams one chunk per token; the final
  /// chunk carries the authoritative count when the backend reports one.
  static Future<double> tokPerSec({
    required String modelPath,
    required LlmModelSpec spec,
    int? nGpuLayers,
  }) async {
    final repo = LlamaCppChatRepository.withModelPath(
      modelPath,
      contextSize: spec.contextSize,
      batchSize: spec.contextSize,
      nGpuLayers: nGpuLayers ?? gpuLayersFor(spec.size),
    );
    try {
      final sw = Stopwatch()..start();
      Duration? firstChunkAt;
      var tokens = 0;
      await for (final chunk in repo.streamChatWithGenerationOptions(
        'model',
        messages: [
          LLMMessage(role: LLMRole.system, content: 'Svara kort på svenska.'),
          LLMMessage(
            role: LLMRole.user,
            content: 'Skriv en mening om vad man gör i skolan.',
          ),
        ],
        generationOptions: _options,
      )) {
        final eval = chunk.evalCount;
        if (chunk.done == true && eval != null) {
          tokens = eval;
        } else {
          tokens++;
        }
        // Decode speed is measured from the first token: model load and
        // prompt prefill would otherwise drag the number down, and drag it
        // down differently per device — the number must compare devices.
        firstChunkAt ??= sw.elapsed;
      }
      sw.stop();
      if (tokens < 8) {
        throw StateError('Modellen genererade för få tokens att mäta.');
      }
      final decodeTokens = tokens - 1;
      final decodeMs =
          sw.elapsedMilliseconds - firstChunkAt!.inMilliseconds;
      if (decodeMs <= 0 || decodeTokens < 8) {
        // Too few tokens to separate decode from load; fall back to the
        // whole-request rate, which still gives a usable gate.
        return tokens / sw.elapsedMilliseconds * 1000;
      }
      return decodeTokens / decodeMs * 1000;
    } finally {
      repo.dispose();
    }
  }

  /// Should the local LLM run on the GPU at all? On phones the answer is
  /// measured, not assumed: the probe runs the short decode twice, GPU
  /// offload and CPU, and keeps the winner. Android's Vulkan stack is
  /// uneven and a small model can genuinely lose to its own CPU; ancient
  /// iPhones can lose to Metal. One-time cost, per tier+app version when
  /// the caller stocks it in settings.
  ///
  /// Returns true for GPU, false for CPU, null when both measurements
  /// failed (default stays [gpuLayersFor]).
  static Future<bool?> measureGpuPreference({
    required String modelPath,
    required LlmModelSpec spec,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // Desktop: the prebuilt enables GPU in the bundle and the windows /
      // linux / macOS probe numbers are established. Keep them.
      return true;
    }
    final gpu = await tokPerSec(
      modelPath: modelPath,
      spec: spec,
      nGpuLayers: 99,
    ).catchError((_) => 0.0);
    final cpu = await tokPerSec(
      modelPath: modelPath,
      spec: spec,
      nGpuLayers: 0,
    ).catchError((_) => 0.0);
    if (gpu <= 0 && cpu <= 0) {
      return null;
    }
    if (gpu <= 0) {
      return false;
    }
    if (cpu <= 0) {
      return true;
    }
    return gpu >= cpu;
  }
}
