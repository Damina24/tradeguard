import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/constants/app_strings.dart';
import 'package:tradeguard/core/models/ai_review.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/features/ai_review/ai_review_providers.dart';
import 'package:tradeguard/features/ai_review/data/ai_review_repository.dart';
import 'package:tradeguard/features/ai_review/widgets/ai_review_card.dart';
import 'package:tradeguard/features/paywall/data/purchase_repository.dart';

/// A stored review, overridable field by field for the state tests.
AiReview review({
  String id = '',
  String summary = 'XAUUSD closed in profit with the stop respected.',
  String leak = 'The take profit was further away than the entry risk.',
  int score = 72,
  List<String>? suggestions = const <String>[
    'Place the take profit at a distance you would actually hold to.',
    'Journal the reason for entry before you click.',
  ],
  String tradeId = 't1',
}) =>
    AiReview(
      id: id,
      summary: summary,
      leak: leak,
      score: score,
      suggestions: suggestions ?? const <String>[],
      tradeId: tradeId,
    );

/// A repository that returns scripted results, so every UI state is reachable.
///
/// [initial] is what the stored-review read returns; [onRequest] is what a fresh request returns.
/// They are separate because several flows need "no review stored yet, but the request succeeds"
/// (the prompt -> review transition), which a single value cannot express.
class _ScriptedRepository implements AiReviewRepository {
  _ScriptedRepository({
    this.initial,
    this.loadFailure,
    this.requested,
    this.requestFailure,
    this.pendingRequest = false,
    this.stubbed = false,
    this.onRequest,
  });

  /// What `fetchReview` returns. Null means "never reviewed".
  final AiReview? initial;

  /// When set, `fetchReview` throws this instead of returning.
  final AiReviewFailure? loadFailure;

  /// What a successful `requestReview` returns.
  final AiReview? requested;

  /// When set, `requestReview` throws this.
  final AiReviewFailure? requestFailure;

  /// When true, `requestReview` never completes, so the loading state can be observed. A
  /// request that resolves immediately would finish before the first `pump`, and the spinner
  /// would never exist to assert on.
  final bool pendingRequest;

  final bool stubbed;
  final void Function(String tradeId)? onRequest;

  @override
  bool get isStubbed => stubbed;

  @override
  Future<AiReview?> fetchReview(String tradeId) async {
    final AiReviewFailure? f = loadFailure;
    if (f != null) throw AiReviewException(f);
    return initial;
  }

  @override
  Future<AiReview> requestReview(String tradeId) async {
    onRequest?.call(tradeId);
    if (pendingRequest) return Completer<AiReview>().future;
    final AiReviewFailure? f = requestFailure;
    if (f != null) throw AiReviewException(f);
    final AiReview? r = requested ?? initial;
    if (r == null) {
      throw const AiReviewException(AiReviewFailure.failed);
    }
    return r;
  }
}

/// Wraps the card with a fixed repository state.
///
/// [key] forces a fresh Riverpod container. Without it, two `pumpWidget` calls in one test reuse
/// the same provider instance and the second case silently reads the first case's cached state —
/// which is how a loop of assertions can pass the first iteration and fail the rest.
///
/// [scroll] reproduces the real call site. On S5 the card is a child of the detail screen's
/// `ListView`, so it is never asked to fit a phone's viewport height; it is laid out at the device
/// width and scrolls. Without this the harness would measure a card taller than a 640px screen as
/// an overflow — an artefact of the test rig, not a defect in the card.
///
/// [isPro] drives the injected `purchasesProvider`: default true so the request
/// proceeds; pass false to exercise the Pro gate.
Widget _app(
  Widget child, {
  Key? key,
  bool scroll = true,
  AiReview? initial,
  AiReview? requested,
  AiReviewFailure? loadFailure,
  AiReviewFailure? requestFailure,
  bool pendingRequest = false,
  bool stubbed = false,
  bool isPro = true,
  void Function(String tradeId)? onRequest,
}) {
  return ProviderScope(
    key: key,
    overrides: <Override>[
      aiReviewProvider('t1').overrideWith(
        (Ref ref) => AiReviewNotifier(
          _ScriptedRepository(
            initial: initial,
            requested: requested,
            loadFailure: loadFailure,
            requestFailure: requestFailure,
            pendingRequest: pendingRequest,
            stubbed: stubbed,
            onRequest: onRequest,
          ),
          't1',
        ),
      ),
      purchasesProvider.overrideWith(
        (Ref ref) => PurchaseNotifier(_FixedPurchaseRepository(isPro)),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: scroll
            ? SingleChildScrollView(child: child)
            : child,
      ),
    ),
  );
}

/// Resizes the test surface so the card and its disclaimer all lay out.
void _useSurface(WidgetTester tester, {Size size = const Size(390, 1800)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// All text the card rendered, lower-cased — for the compliance and leakage assertions.
String _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .join(' ')
    .toLowerCase();

/// Long, hostile content: maximum-length strings in every field.
AiReview hostileReview() => review(
      summary: 'x' * 600,
      leak: 'y' * 600,
      suggestions: List<String>.generate(6, (int i) => 'z' * 240),
    );

void main() {
  group('AI Review card — normal behaviour', () {
    testWidgets('offers a review when none exists', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(_app(const AiReviewCard(tradeId: 't1')));
      await tester.pumpAndSettle();

      expect(find.text('Get AI review'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    });

    testWidgets('renders a stored review', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('closed in profit'), findsOneWidget);
      expect(find.textContaining('take profit was further away'), findsOneWidget);
      expect(find.textContaining('Place the take profit'), findsOneWidget);
      expect(find.text('EXECUTION SCORE'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
      expect(find.text('/100'), findsOneWidget);
      expect(find.text('Get AI review'), findsNothing);
    });

    testWidgets('states the score band in words, not colour alone',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review(score: 85)),
      );
      await tester.pumpAndSettle();

      expect(find.text('STRONG'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('each band has its own label', (WidgetTester tester) async {
      _useSurface(tester);
      for (final (int score, String label) in <(int, String)>[
        (90, 'STRONG'),
        (55, 'MIXED'),
        (10, 'NEEDS WORK'),
      ]) {
        // A fresh container per case, or the second iteration re-reads the first one's cache.
        await tester.pumpWidget(
          _app(
            const AiReviewCard(tradeId: 't1'),
            key: ValueKey<String>('band-$score'),
            initial: review(score: score),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('names the model that wrote the text',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review()),
      );
      await tester.pumpAndSettle();
      expect(find.text('gpt-4o-mini'), findsOneWidget);
    });

    testWidgets('offers a refresh once a review exists',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('says so when there were no suggestions',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          initial: review(suggestions: const <String>[]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No further suggestions for this trade.'), findsOneWidget);
      expect(find.text('SUGGESTIONS'), findsNothing);
    });
  });

  group('AI Review card — compliance and offline labelling', () {
    testWidgets('always shows the risk disclaimer',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(_app(const AiReviewCard(tradeId: 't1')));
      await tester.pumpAndSettle();

      // AGENTS.md: every user-visible risk surface shows AppStrings.riskDisclaimer.
      expect(find.textContaining(AppStrings.riskDisclaimer), findsOneWidget);
    });

    testWidgets('the disclaimer is present on a review, not only on the prompt',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(AppStrings.riskDisclaimer), findsOneWidget);
    });

    testWidgets('labels an offline demo review as such',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review(), stubbed: true),
      );
      await tester.pumpAndSettle();

      // A demo review must never be mistakable for model output.
      expect(find.text('OFFLINE DEMO'), findsOneWidget);
    });

    testWidgets('does not label a live review as offline',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review()),
      );
      await tester.pumpAndSettle();
      expect(find.text('OFFLINE DEMO'), findsNothing);
    });

    testWidgets('promises no profit anywhere', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review()),
      );
      await tester.pumpAndSettle();

      final String rendered = _renderedText(tester);
      expect(rendered, isNot(contains('guaranteed')));
      expect(rendered, isNot(contains('risk-free')));
      expect(rendered, isNot(contains('best signals')));
    });
  });

  group('AI Review card — state transitions', () {
    testWidgets('requesting moves from the prompt to a review',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          // Nothing stored yet, but the request succeeds.
          requested: review(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Get AI review'), findsOneWidget);
      await tester.tap(find.text('Get AI review'));
      await tester.pumpAndSettle();

      expect(find.text('Get AI review'), findsNothing);
      expect(find.textContaining('closed in profit'), findsOneWidget);
    });

    testWidgets('shows a spinner while loading', (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          initial: review(),
          // Held open, so the loading state actually exists to be observed.
          pendingRequest: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      // `pump`, not `pumpAndSettle`: the progress indicator animates forever, so settling would
      // never terminate.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The old review stays on screen behind the spinner rather than blanking out.
      expect(find.textContaining('closed in profit'), findsOneWidget);
    });

    testWidgets('the first request shows a spinner and no review',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          pendingRequest: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get AI review'));
      await tester.pump();

      // Two indicators are correct here: one in the header, one in the body. Asserting on the
      // body copy is what actually proves the loading state, rather than a brittle widget count.
      expect(find.text('Reviewing this trade…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      // And no review is claimed while one has not arrived.
      expect(find.text('EXECUTION SCORE'), findsNothing);
    });

    testWidgets('a failure is not rendered as "no review yet"',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          loadFailure: AiReviewFailure.notConfigured,
        ),
      );
      await tester.pumpAndSettle();

      // The failure copy must be shown, and the inviting prompt must NOT be.
      expect(find.text(AiReviewFailure.notConfigured.message), findsOneWidget);
      expect(find.text('Get AI review'), findsNothing);
    });

    testWidgets('every failure renders its own message',
        (WidgetTester tester) async {
      _useSurface(tester);
      for (final AiReviewFailure failure in AiReviewFailure.values) {
        await tester.pumpWidget(
          _app(
            const AiReviewCard(tradeId: 't1'),
            key: ValueKey<String>('failure-${failure.name}'),
            loadFailure: failure,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(failure.message), findsOneWidget);
      }
    });

    testWidgets('a failed refresh keeps the previous review visible',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          // A stored review plus a REQUEST that fails — the refresh must not destroy it.
          initial: review(),
          requestFailure: AiReviewFailure.failed,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(find.textContaining('closed in profit'), findsOneWidget);
    });

    testWidgets('a failed refresh shows the error AND keeps the review',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          initial: review(),
          requestFailure: AiReviewFailure.failed,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      // Both: the trader is told it failed, AND keeps the review they already had.
      expect(find.text(AiReviewFailure.failed.message), findsOneWidget);
      expect(find.textContaining('closed in profit'), findsOneWidget);
      expect(find.textContaining('take profit was further away'), findsOneWidget);
    });

    testWidgets('a failed refresh does not offer a fresh request',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          initial: review(),
          requestFailure: AiReviewFailure.failed,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('Get AI review'), findsNothing);
    });

    testWidgets('an unscored review shows a dash, not a zero',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), initial: review(score: 500)),
      );
      await tester.pumpAndSettle();

      // A 0 would read as a damning verdict about a trade nobody assessed.
      expect(find.text('NOT SCORED'), findsOneWidget);
      expect(find.text('/100'), findsNothing);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });
  });

  group('AI Review card — security', () {
    testWidgets('never renders a raw backend error',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), loadFailure: AiReviewFailure.failed),
      );
      await tester.pumpAndSettle();

      final String rendered = _renderedText(tester);
      expect(rendered, isNot(contains('ai_reviews')));
      expect(rendered, isNot(contains('service_role')));
      expect(rendered, isNot(contains('openai')));
    });

    testWidgets('carries no account number, login or trade id',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          initial: review(tradeId: 'secret-trade-id'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('secret-trade-id'), findsNothing);
      expect(find.text('acc-1'), findsNothing);
    });

    testWidgets('a foreign trade shows the same copy as a missing one',
        (WidgetTester tester) async {
      _useSurface(tester);
      // The repository refuses both identically (see ai_review_repository_test.dart). The point
      // asserted here is only that the UI surfaces that ONE message, so the endpoint cannot be
      // used to probe whether another trader's trade id exists.
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          requestFailure: AiReviewFailure.tradeUnavailable,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get AI review'));
      await tester.pumpAndSettle();

      expect(find.text(AiReviewFailure.tradeUnavailable.message), findsOneWidget);
    });
  });
// ---- Visual verification across supported device sizes -------------------------------------
  //
  // Layout assertions, not snapshots: each size is rendered with hostile content and checked for
  // RenderFlex overflow, which is how a clipped paragraph or a runaway row announces itself.
  const Map<String, Size> devices = <String, Size>{
    'narrow phone (320x640)': Size(320, 640),
    'normal phone (390x844)': Size(390, 844),
    'large phone (430x932)': Size(430, 932),
  };

  for (final MapEntry<String, Size> device in devices.entries) {
    group('layout — ${device.key}', () {
      testWidgets('a long review does not overflow', (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(const AiReviewCard(tradeId: 't1'), initial: hostileReview()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('many suggestions do not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const AiReviewCard(tradeId: 't1'),
            initial: review(
              suggestions: List<String>.generate(6, (int i) => 'Suggestion $i'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('an unbroken 600-character word does not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const AiReviewCard(tradeId: 't1'),
            // The worst realistic case for a Text widget: no spaces to break on.
            initial: review(summary: 'W' * 600, leak: 'W' * 600),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the prompt state does not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(_app(const AiReviewCard(tradeId: 't1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the loading state does not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const AiReviewCard(tradeId: 't1'),
            initial: review(),
            pendingRequest: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refresh'));
        // A single `pump`: the indicator animates forever, so `pumpAndSettle` cannot return.
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the failure state does not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const AiReviewCard(tradeId: 't1'),
            loadFailure: AiReviewFailure.unreachable,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('an empty-suggestion review does not overflow',
          (WidgetTester tester) async {
        _useSurface(tester, size: device.value);
        await tester.pumpWidget(
          _app(
            const AiReviewCard(tradeId: 't1'),
            initial: review(suggestions: const <String>[]),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('AI Review card — Pro gate', () {
    testWidgets('a non-Pro trader is shown the paywall instead of a review',
        (WidgetTester tester) async {
      _useSurface(tester);
      // Gate: AI Trade Review requires Pro. With nothing stored and not Pro,
      // tapping "Get AI review" opens the paywall and makes no request.
      await tester.pumpWidget(
        _app(const AiReviewCard(tradeId: 't1'), isPro: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get AI review'));
      await tester.pumpAndSettle();

      // The paywall is presented; the prompt is unchanged (no review began).
      expect(find.text('TradeGuard Pro'), findsOneWidget);
      expect(find.text('Get AI review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-Pro trader cannot Refresh a stored review either',
        (WidgetTester tester) async {
      _useSurface(tester);
      await tester.pumpWidget(
        _app(
          const AiReviewCard(tradeId: 't1'),
          initial: review(),
          isPro: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      // The paywall is shown and the stored review is left untouched.
      expect(find.text('TradeGuard Pro'), findsOneWidget);
      expect(find.textContaining('closed in profit'), findsOneWidget);
    });
  });
}

/// A purchase repository pinned to a fixed Pro status and no offerings, so the
/// AI review Pro gate can be driven both ways.
class _FixedPurchaseRepository implements PurchaseRepository {
  _FixedPurchaseRepository(this._pro);

  final bool _pro;

  @override
  Future<bool> isPro() async => _pro;

  @override
  Stream<bool> watchProStatus() => Stream<bool>.value(_pro);

  @override
  Future<List<Object>> loadPackages() async => const <Object>[];

  @override
  Future<void> purchase(Object package) async {}

  @override
  Future<void> restore() async {}
}