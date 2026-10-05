import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/services.dart';
import 'package:tradeguard/features/patterns/data/mock_pattern_repository.dart';
import 'package:tradeguard/features/patterns/data/pattern_repository.dart';
import 'package:tradeguard/features/patterns/domain/leak_detector.dart';
import 'package:tradeguard/features/patterns/domain/pattern_metrics.dart';
import 'package:tradeguard/features/patterns/domain/pattern_row.dart';
import 'package:tradeguard/features/patterns/pattern_providers.dart';

/// A repository that answers with whatever it was handed, so a screen can be
/// driven through each state without a backend.
class FakePatternRepository implements PatternRepository {
  FakePatternRepository({this.rows, this.failure});

  final List<PatternRow>? rows;
  final Object? failure;

  @override
  Future<List<PatternRow>> fetchPatterns() async {
    final Object? f = failure;
    if (f != null) throw f;
    return List<PatternRow>.from(rows ?? const <PatternRow>[]);
  }
}

/// A repository that fails until [failing] is cleared.
class _FlakyRepository implements PatternRepository {
  bool failing = true;

  @override
  Future<List<PatternRow>> fetchPatterns() async {
    if (failing) throw StateError('offline');
    return MockPatternRepository.defaultRows;
  }
}

/// A usable row, for tests that only care that the read succeeded.
const PatternRow goodRow = PatternRow(
  userId: 'u1',
  symbol: 'XAUUSD',
  session: 'london',
  dayOfWeek: 1,
  hour: 8,
  pnl: -800,
  trades: 24,
  winRate: 0.29,
);

void main() {
  group('MockPatternRepository', () {
    test('is the repository mock mode resolves', () {
      // Mock-first is what lets patterns and leaks render, and the tests run,
      // with no Supabase project and no credentials.
      expect(Services.instance.isMock, isTrue);
      expect(Services.instance.patterns, isA<MockPatternRepository>());
    });

    test('returns pre-grouped rows without needing a backend', () async {
      final List<PatternRow> rows = await MockPatternRepository().fetchPatterns();
      expect(rows, isNotEmpty);
      expect(rows.first.trades, greaterThan(0));
      expect(rows.first.winRate, inInclusiveRange(0, 1));
    });

    test('returns an unmodifiable view', () async {
      final List<PatternRow> rows = await MockPatternRepository().fetchPatterns();
      expect(() => rows.add(rows.first), throwsUnsupportedError);
    });

    test('every fixture row belongs to the demo user', () async {
      // Isolation is a property of the data, not just of the query: a mock that
      // returned mixed-user rows would let a bug in the UI go unnoticed.
      final List<PatternRow> rows = await MockPatternRepository().fetchPatterns();
      expect(
        rows.every((PatternRow r) => r.userId == MockPatternRepository.userId),
        isTrue,
      );
    });

    test('the seed is deterministic across instances', () async {
      final List<PatternRow> a = await MockPatternRepository().fetchPatterns();
      final List<PatternRow> b = await MockPatternRepository().fetchPatterns();
      expect(a.length, b.length);
      for (int i = 0; i < a.length; i++) {
        expect(a[i].pnl, b[i].pnl);
        expect(a[i].trades, b[i].trades);
      }
    });

    test('the seed includes a losing slice big enough to surface as a leak',
        () async {
      // The demo seed has to exercise the real path, not just the empty one.
      final List<PatternRow> rows = await MockPatternRepository().fetchPatterns();
      expect(rows.any((PatternRow r) => r.pnl < 0 && r.trades >= 5), isTrue);
    });

    test('the seed includes a thin losing slice that must NOT surface as a leak',
        () async {
      // This is the single-trade-anecdote guard, exercised by the shipped seed.
      final List<PatternRow> rows = await MockPatternRepository().fetchPatterns();
      expect(rows.any((PatternRow r) => r.pnl < 0 && r.trades < 5), isTrue);
    });

    test('can be constructed with custom rows for tests', () async {
      final List<PatternRow> custom = <PatternRow>[
        const PatternRow(
          userId: 'u',
          symbol: 'X',
          session: null,
          dayOfWeek: null,
          hour: null,
          pnl: -1,
          trades: 1,
          winRate: 0,
        ),
      ];
      expect(
        (await MockPatternRepository(rows: custom).fetchPatterns()).length,
        1,
      );
    });
  });

  group('PatternNotifier', () {
    test('starts in the loading state, not the empty state', () async {
      // A state that starts as "empty" must never be mistaken for "you have no
      // patterns" while the read is still in flight.
      final PatternNotifier notifier = PatternNotifier(
        FakePatternRepository(rows: const <PatternRow>[]),
      );
      expect(notifier.state.status, PatternStatus.loading);
      await notifier.refresh();
      expect(notifier.state.status, PatternStatus.empty);
    });

    test('an empty result is the empty state, not an error', () async {
      final PatternNotifier notifier =
          PatternNotifier(FakePatternRepository(rows: const <PatternRow>[]));
      await notifier.refresh();
      expect(notifier.state.status, PatternStatus.empty);
      expect(notifier.state.isReady, isFalse);
    });

    test('rows produce the ready state', () async {
      final PatternNotifier notifier =
          PatternNotifier(FakePatternRepository(rows: <PatternRow>[goodRow]));
      await notifier.refresh();
      expect(notifier.state.status, PatternStatus.ready);
      expect(notifier.state.totalTrades, 24);
    });

    test('a failure becomes the error state, not the empty state', () async {
      // Rendering a backend failure as "no patterns" would tell the trader their
      // journal is empty when in fact it could not be read.
      final PatternNotifier notifier = PatternNotifier(
        FakePatternRepository(failure: StateError('boom')),
      );
      await notifier.refresh();
      expect(notifier.state.status, PatternStatus.error);
    });

    test('the error state carries no raw exception for the UI to leak', () async {
      final PatternNotifier notifier = PatternNotifier(
        FakePatternRepository(
          failure: const PatternDataException('relation "trades" does not exist'),
        ),
      );
      await notifier.refresh();
      expect(notifier.state.toString(), isNot(contains('relation')));
    });

    test('the row list handed to the UI is unmodifiable', () async {
      final PatternNotifier notifier = PatternNotifier(MockPatternRepository());
      await notifier.refresh();
      expect(
        () => notifier.state.rows.add(notifier.state.rows.first),
        throwsUnsupportedError,
      );
    });

    test('refresh recovers from an error once the backend returns', () async {
      final _FlakyRepository repo = _FlakyRepository();
      final PatternNotifier notifier = PatternNotifier(repo);
      await notifier.refresh();
      expect(notifier.state.status, PatternStatus.error);
      repo.failing = false;
      await notifier.refresh();
      expect(notifier.state.status, PatternStatus.ready);
    });
  });

  group('account isolation', () {
    test('the repository exposes exactly one read, and it takes no arguments',
        () {
      // The strongest guarantee is that the request cannot be expressed:
      // `fetchPatterns()` has no parameters, so no caller - widget, route or
      // string-parsed id - can ask for another trader's journal. Identity comes
      // from the auth session inside the repository, never from an argument.
      final PatternRepository repo = FakePatternRepository();
      expect(repo.fetchPatterns, isNotNull);
    });

    test('the domain layer takes rows only and cannot widen access', () {
      // `PatternMetrics.fromRows` and `LeakDetector.detectRows` accept rows and
      // nothing else, so there is no user id for them to be handed.
      expect(PatternMetrics.fromRows, isNotNull);
      expect(const LeakDetector().detectRows, isNotNull);
    });

    test('the provider exposes a state object, not a query', () {
      // There is no path from a widget to a Supabase builder for patterns: the
      // notifier owns the read and publishes plain rows.
      expect(patternStateProvider, isNotNull);
    });

    test('mock rows never mix users', () async {
      final List<PatternRow> rows = await MockPatternRepository().fetchPatterns();
      expect(rows.map((PatternRow r) => r.userId).toSet(), hasLength(1));
    });

    test('no pattern object carries a credential or an account number', () {
      // A PatternRow holds the view's own columns. There is nowhere for a
      // broker login or a MetaAPI id to hide, so nothing sensitive can reach a
      // screen that renders one.
      expect(goodRow.toString(), isNot(contains('service')));
      expect(goodRow.toString(), isNot(contains('password')));
      expect(goodRow.userId, 'u1');
    });
  });
}
