/// The plugin reports a failed GGUF load as an English path
/// (`ModelLoadException: Failed to load model from /data/...`). The teacher
/// should see what to do instead.
class ModelLoadFailure implements Exception {
  ModelLoadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [suggestSmaller] is for a manual pick that is still on the 4B file.
/// The auto pick has already stepped down by the time this is the last word.
String modelLoadFailureText({required bool suggestSmaller}) {
  if (suggestSmaller) {
    return 'Språkmodellen kunde inte laddas. Välj den mindre modellen '
        'under Inställningar, eller sammanfatta i molnet.';
  }
  return 'Språkmodellen kunde inte laddas på den här enheten. '
      'Sammanfatta i molnet under Inställningar om underlaget behövs.';
}
