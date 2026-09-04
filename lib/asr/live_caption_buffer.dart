import 'transcript_merge.dart';

/// Committed lecture text plus the latest in-progress hypothesis.
class LiveCaptionBuffer {
  String committed = '';
  String partial = '';

  void setPartial(String text) {
    partial = text.trim();
  }

  void commit(String text) {
    final piece = text.trim();
    if (piece.isNotEmpty) {
      committed = mergeOverlappingTranscript(committed, piece);
    }
    partial = '';
  }

  void clear() {
    committed = '';
    partial = '';
  }

  String get display {
    if (partial.isEmpty) {
      return committed;
    }
    if (committed.isEmpty) {
      return partial;
    }
    return mergeOverlappingTranscript(committed, partial);
  }
}
