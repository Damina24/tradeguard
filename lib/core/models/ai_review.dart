class AiReview {
  const AiReview({
    required this.id,
    required this.summary,
    required this.leak,
    required this.score,
    required this.suggestions,
    this.model = 'gpt-4o-mini',
  });

  final String id;
  final String summary;
  final String leak;
  final int score;
  final List<String> suggestions;
  final String model;

  factory AiReview.fromJson(Map<String, dynamic> json) => AiReview(
        id: json['id'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        leak: json['leak'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        suggestions: (json['suggestions'] as List<dynamic>?)
                ?.map((dynamic e) => e.toString())
                .toList() ??
            const <String>[],
        model: json['model'] as String? ?? 'gpt-4o-mini',
      );
}
