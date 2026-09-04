import 'newsletter.dart';

abstract class Summarizer {
  Future<NewsletterSummary> summarize(String transcript);
}
