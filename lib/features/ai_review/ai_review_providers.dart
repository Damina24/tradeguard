import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ai_review.dart';
import '../../core/models/trade.dart';
import '../../core/services/providers.dart';
import '../../core/services/services.dart';
import 'data/ai_review_repository.dart';
import 'data/mock_ai_review_repository.dart';

/// Where the AI review for one trade currently stands.
///
/// Five states, and the distinction that matters is between [none] and [failed]:
///
///   * [none]     — no review exists yet. This is the INITIAL state; the card offers to make one.
///   * [loading]  — a request is in flight.
///   * [ready]    — a review is in hand.
///   * [failed]   — the request failed. **Never rendered as [none].** Telling a trader "no review
///                  yet" after the model refused would erase the fact that something went wrong,
///                  and would hide a genuine backend misconfiguration behind an empty card.
///
/// They are separate states rather than a nullable review so a screen cannot accidentally
/// collapse them.
enum AiReviewStatus { none, loading, ready, failed }

/// The review state for one trade. Immutable.
class AiReviewState {
  const AiReviewState({
    this.status = AiReviewStatus.none,
    this.review,
    this.failure,
    this.isStubbed = false,
  });

  /// The initial state: no review has been requested or stored for this trade.
  static const AiReviewState empty = AiReviewState();

  final AiReviewStatus status;
  final AiReview? review;

  /// Set only when [status] is [AiReviewStatus.failed]. Carries the closed-set reason, never a raw
  /// backend message.
  final AiReviewFailure? failure;

  /// Whether the repository backing this state produces reviews offline.
  final bool isStubbed;

  bool get isLoading => status == AiReviewStatus.loading;

  bool get hasReview => review != null;

  /// True while a stored review is on screen and a new one is being fetched, so the card can keep
  /// showing the old text instead of blanking out.
  bool get isRefreshing => status == AiReviewStatus.loading && review != null;

  /// True when the review came from the offline mock rather than the model.
  ///
  /// Carried on the STATE rather than read from a second provider inside the card, so a review and
  /// the badge describing it can never come from two places that disagree.
  bool get isStubbedReview => isStubbed;
}

/// Loads and requests the AI review for one trade.
///
/// Account isolation comes from the repository, not from here: this notifier has no user parameter
/// and no way to be asked for another account's review. The repository reads identity from the
/// session, and the `ai-review` Edge Function independently re-derives it from the verified JWT.
class AiReviewNotifier extends StateNotifier<AiReviewState> {
  AiReviewNotifier(this._repo, this._tradeId)
      : super(AiReviewState(isStubbed: _repo.isStubbed)) {
    _load();
  }

  final AiReviewRepository _repo;
  final String _tradeId;

  Future<void> _load() async {
    try {
      final AiReview? stored = await _repo.fetchReview(_tradeId);
      if (!mounted) return;
      state = stored == null
          ? AiReviewState(isStubbed: _repo.isStubbed)
          : AiReviewState(
              status: AiReviewStatus.ready,
              review: stored,
              isStubbed: _repo.isStubbed,
            );
    } on AiReviewException catch (e) {
      if (!mounted) return;
      state = AiReviewState(
        status: AiReviewStatus.failed,
        failure: e.failure,
        isStubbed: _repo.isStubbed,
      );
    } catch (_) {
      if (!mounted) return;
      state = AiReviewState(
        status: AiReviewStatus.failed,
        failure: AiReviewFailure.unreachable,
        isStubbed: _repo.isStubbed,
      );
    }
  }

  /// Requests a fresh review.
  ///
  /// The existing review is KEPT in state while the request runs, so the card shows the old text
  /// with a progress indicator instead of collapsing to a spinner — and so a failure leaves the
  /// previous review visible rather than destroying the trader's stored feedback.
  Future<void> request() async {
    if (state.isLoading) return;
    state = AiReviewState(
      status: AiReviewStatus.loading,
      review: state.review,
      isStubbed: _repo.isStubbed,
    );

    try {
      final AiReview fresh = await _repo.requestReview(_tradeId);
      if (!mounted) return;
      state = AiReviewState(
        status: AiReviewStatus.ready,
        review: fresh,
        isStubbed: _repo.isStubbed,
      );
    } on AiReviewException catch (e) {
      if (!mounted) return;
      state = AiReviewState(
        status: AiReviewStatus.failed,
        // A failed refresh keeps whatever was already on screen, flagged as failed.
        review: state.review,
        failure: e.failure,
        isStubbed: _repo.isStubbed,
      );
    } catch (_) {
      if (!mounted) return;
      state = AiReviewState(
        status: AiReviewStatus.failed,
        review: state.review,
        failure: AiReviewFailure.unreachable,
        isStubbed: _repo.isStubbed,
      );
    }
  }

  /// Re-reads the stored review.
  Future<void> refresh() async {
    if (state.isLoading) return;
    state = AiReviewState(
      status: AiReviewStatus.loading,
      review: state.review,
      isStubbed: _repo.isStubbed,
    );
    await _load();
  }
}

/// Per-trade review state. Keyed by trade id so navigating between trades does not show one
/// trade's review on another.
final StateNotifierProviderFamily<AiReviewNotifier, AiReviewState, String>
    aiReviewProvider =
    StateNotifierProvider.family<AiReviewNotifier, AiReviewState, String>(
  (Ref ref, String tradeId) {
    final AiReviewRepository repo = Services.instance.aiReviews;

    // Hand the offline mock the journal this screen is showing. Without this the mock would hold a
    // private copy — or none at all — and could review a different trade than the one on screen.
    // A live repository needs nothing: it reads the trade from the database under the caller's
    // own identity.
    if (repo is MockAiReviewRepository) {
      final List<Trade> trades = ref.watch(tradesProvider);
      repo.tradesLookup = (String id) {
        for (final Trade t in trades) {
          if (t.id == id) return t;
        }
        return null;
      };
    }

    return AiReviewNotifier(repo, tradeId);
  },
);
