import 'transcript_merge.dart';

/// Committed lecture text plus the latest in-progress hypothesis.
class LiveCaptionBuffer {
  /// The transcript is merged on every commit *and* on every rolling-window
  /// partial, always against the same growing text, so it owns the word index
  /// `LiveTranscript` keeps rather than deriving it again per caption.
  final LiveTranscript _committed = LiveTranscript();

  String partial = '';

  String get committed => _committed.text;

  void setPartial(String text) {
    partial = text.trim();
  }

  void commit(String text) {
    final piece = text.trim();
    if (piece.isNotEmpty) {
      _committed.merge(piece);
    }
    partial = '';
  }

  void clear() {
    _committed.clear();
    partial = '';
  }

  String get display {
    if (partial.isEmpty) {
      return committed;
    }
    if (committed.isEmpty) {
      return partial;
    }
    return _committed.preview(partial);
  }
}
