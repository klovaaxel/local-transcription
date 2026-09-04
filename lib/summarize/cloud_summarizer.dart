import '../cloud/openai_compatible.dart';
import 'brief_pipeline.dart';

/// Writes the brief through an OpenAI-compatible provider — Berget AI by
/// default. Only reachable when the teacher picked cloud in settings; the
/// transcript is what leaves the device here, and nothing else.
class CloudSummarizer extends BriefPipeline {
  CloudSummarizer({
    required this.config,
    OpenAiCompatibleClient? client,
    super.onProgress,
  }) : _client = client ?? OpenAiCompatibleClient(config: config),
       _ownsClient = client == null;

  /// Conservative window so any hosted model fits, including 32k ones.
  /// Longer lectures map/reduce instead of overflowing the request.
  static const chunkChars = 24000;

  final CloudConfig config;
  final OpenAiCompatibleClient _client;
  final bool _ownsClient;

  @override
  int get chunkCharBudget => chunkChars;

  @override
  Future<String> complete(List<ChatTurn> turns) {
    return _client.chat(turns: turns);
  }

  @override
  Future<void> release() async {
    if (_ownsClient) {
      _client.close();
    }
  }
}
