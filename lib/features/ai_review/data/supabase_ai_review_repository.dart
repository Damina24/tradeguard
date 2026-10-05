import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/ai_review.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/ai_review_draft.dart';
import 'ai_review_repository.dart';

/// Live AI reviews: reads `ai_reviews`, asks the `ai-review` Edge Function for new ones.
///
/// Two independent ownership checks, because either alone is insufficient:
///
///   1. **The Edge Function re-derives the caller from the verified JWT** and filters the `trades`
///      read on `trades.user_id = <caller>`. A `trade_id` belonging to somebody else is a 404,
///      identical to one that does not exist.
///   2. **The stored-review read filters on `auth.currentUser.id`** taken from the live session.
///      Migration 0007 narrows the `ai_reviews` policy to SELECT-only, so RLS on the base table
///      also enforces this per row — a base table, not a view, so no `security_invoker` question
///      arises.
///
/// The service-role key is never involved: this path uses the anon/publishable key, so it is
/// subject to RLS exactly like any other client request. The function's own service-role WRITE is
/// separately authenticated.
class SupabaseAiReviewRepository implements AiReviewRepository {
  SupabaseAiReviewRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  bool get isStubbed => false;

  @override
  Future<AiReview?> fetchReview(String tradeId) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      // No session means no honest way to scope the read. Returning null here would render as
      // "this trade has not been reviewed", which is a different and false statement.
      throw const AiReviewException(AiReviewFailure.unreachable);
    }

    final List<Map<String, dynamic>> rows = await (_client
        .from('ai_reviews')
        .select()
        .eq('trade_id', tradeId)
        .eq('user_id', userId)
        .limit(1));

    if (rows.isEmpty) return null;

    // Validated through the same draft as a fresh response, so a row written by an older prompt
    // (or a hand-edited one) cannot render a score outside 0..100.
    return AiReviewDraft.fromResponse(rows.first, tradeId: tradeId);
  }

  @override
  Future<AiReview> requestReview(String tradeId) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw const AiReviewException(AiReviewFailure.unreachable);
    }

    final dynamic response;
    try {
      // `FunctionsClient.invoke` throws on a non-2xx, so every transport, auth, rate-limit and
      // 5xx case lands in the catch below.
      response = await _service.client.functions.invoke(
        'ai-review',
        // The body carries ONLY the trade id. No user id, no account id, no trade contents — the
        // function reads those from the database under the caller's own identity.
        body: <String, dynamic>{'trade_id': tradeId},
      );
    } on FunctionsHttpException catch (e) {
      // The STATUS is classified; the body is never shown. A function error body can name tables,
      // constraints, or echo model output back, none of which helps a trader and some of which
      // must not be rendered.
      throw AiReviewException(_classify(e.status));
    } catch (_) {
      // Transport failure, or a throw we have no classification for. Still never surfaced raw.
      throw const AiReviewException(AiReviewFailure.unreachable);
    }

    final Object? data = response.data as Object?;
    if (data is! Map<String, dynamic>) {
      throw const AiReviewException(AiReviewFailure.failed);
    }

    final AiReview? review = AiReviewDraft.fromResponse(data, tradeId: tradeId);
    if (review == null) {
      throw const AiReviewException(AiReviewFailure.failed);
    }
    return review;
  }

  /// Maps a function status onto the closed [AiReviewFailure] set.
  ///
  /// Only the STATUS is used — never the body. The mapping exists so the card can distinguish the
  /// one failure a trader can act on ("the model is not configured") from the ones they cannot, and
  /// so a 404 stays "not available for review" rather than becoming a generic error that reads
  /// like a bug.
  static AiReviewFailure _classify(int status) {
    if (status == 404) return AiReviewFailure.tradeUnavailable;
    if (status == 422) return AiReviewFailure.incomplete;
    // 503 is `notConfigured` in the handler: no OPENAI_API_KEY, or no Supabase credentials.
    if (status == 503) return AiReviewFailure.notConfigured;
    if (status == 401 || status == 403) return AiReviewFailure.unreachable;
    return AiReviewFailure.failed;
  }
}
