import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/broker_offers/presentation/broker_offers_screen.dart';
import '../../features/broker_offers/presentation/broker_webview_screen.dart';
import '../../features/chart_analysis/presentation/chart_analysis_screen.dart';
import '../../features/guard/presentation/guard_screen.dart';
import '../../features/journal/presentation/journal_screen.dart';
import '../../features/patterns/presentation/pattern_insights_screen.dart';
import '../../features/paywall/presentation/paywall_screen.dart';
import '../../features/replay/presentation/replay_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/signals/presentation/signals_screen.dart';
import '../../features/tools/presentation/tools_screen.dart';
import '../constants/app_strings.dart';
import '../services/auth_provider.dart';
import '../services/auth_repository.dart';
import '../services/providers.dart';
import '../services/services.dart';
import '../theme/app_colors.dart';
import '../widgets/splash_screen.dart';

/// Small [ChangeNotifier] the router listens to. [routerProvider] pings it whenever the signed-in
/// user changes, which makes go_router re-run its redirect without us navigating by hand.
class RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// The router is a provider (not a top-level final) because the auth guard has to read
/// [authProvider], and because a per-scope router can be disposed with the ProviderScope.
///
/// Hard-paywall model: the app is 100% premium. A signed-in user whose
/// `profiles.is_premium` is false is routed to `/paywall` and stays there —
/// every core route lives inside the shell or behind an explicit paywall
/// redirect, so there is no bottom bar or swipe path into the app until the
/// flag flips. Mock/demo builds bypass the gate (there is no `profiles` row
/// to read offline).
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final RouterRefreshNotifier refresh = RouterRefreshNotifier();
  ref.listen<AppUser?>(
    authProvider,
    (AppUser? previous, AppUser? next) {
      // Refresh the premium flag on every auth change so the redirect below
      // reads the real entitlement, not the notifier's initial `isPro: false`.
      // Sign-out resets to non-pro so a stale `true` can never leak across
      // accounts on a shared device.
      if ((next != null && previous?.id != next.id) || next == null) {
        // ignore: discarded_futures
        ref.read(purchasesProvider.notifier).refresh();
      }
      refresh.refresh();
    },
  );
  ref.listen<PurchaseState>(
    purchasesProvider,
    (PurchaseState? previous, PurchaseState next) {
      if (previous?.isPro != next.isPro ||
          previous?.isLoading != next.isLoading) {
        refresh.refresh();
      }
    },
  );

  final GoRouter router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final AppUser? user = ref.read(authProvider);
      final bool atAuth = state.matchedLocation == '/auth';
      final bool atSplash = state.matchedLocation == '/splash';
      final bool atPaywall = state.matchedLocation == '/paywall';
      // The splash owns its own timed handoff (`SplashScreen.dwell`);
      // never redirect away from it, or it would never be visible.
      if (atSplash) return null;
      if (user == null) return atAuth ? null : '/auth';
      // Demo/mock builds have no `profiles` row — the whole app stays open.
      if (Services.instance.isMock) return atAuth ? '/guard' : null;
      final PurchaseState purchases = ref.read(purchasesProvider);
      // While the flag is (re)reading, hold on the paywall rather than
      // flashing the dashboard to a non-pro user (or bouncing a pro user
      // through the paywall on a slow network).
      if (purchases.isLoading) return atPaywall ? null : '/paywall';
      if (!purchases.isPro) return atPaywall ? null : '/paywall';
      if (atAuth || atPaywall) return '/guard';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) =>
            AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/guard',
                builder: (_, __) => const GuardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/journal',
                builder: (_, __) => const JournalScreen(),
                routes: <RouteBase>[
                  // Patterns + leaks (task 2.4). A child of /journal rather than a
                  // sixth tab: it is a deeper cut of the journal, and a tab would
                  // steal space from the guard home screen.
                  GoRoute(
                    path: 'patterns',
                    builder: (_, __) => const PatternInsightsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/tools',
                builder: (_, __) => const ToolsScreen(),
                // Replay lite (task 2.6). A child of Tools rather than a sixth bottom-nav tab, for
                // the same reason /journal/patterns is a child of Journal: it is a deeper cut of an
                // existing job, and a tab would steal width from the Guard home screen.
                routes: <RouteBase>[
                  GoRoute(
                    path: 'replay',
                    builder: (_, __) => const ReplayScreen(),
                  ),
                  GoRoute(
                    path: 'chart-analysis',
                    builder: (_, __) =>
                        const ChartAnalysisScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/signals',
                builder: (_, __) => const SignalsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen surfaces, deliberately OUTSIDE the shell so none shows
      // the bottom navigation bar. `/paywall` is the hard-paywall gate: a
      // non-pro user lives here with no tab bar and no swipe path into the
      // app. The WebView especially should feel like a dedicated browser,
      // not a tab. Reached from Settings.
      GoRoute(
        path: '/paywall',
        builder: (_, __) => const PaywallScreen(),
      ),
      GoRoute(
        path: '/broker-offers',
        builder: (_, __) => const BrokerOffersScreen(),
      ),
      GoRoute(
        path: '/broker-webview',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> args =
              (state.extra as Map<String, dynamic>?) ?? const <String, dynamic>{};
          final String url = (args['url'] as String?) ??
              (state.uri.queryParameters['url'] ?? '');
          final String title = (args['title'] as String?) ??
              (state.uri.queryParameters['title'] ?? 'Broker');
          return BrokerWebViewScreen(url: url, title: title);
        },
      ),
    ],
  );
  ref.onDispose(() {
    refresh.dispose();
    router.dispose();
  });
  return router;
});

class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (int i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.shield_outlined),
            selectedIcon: const Icon(Icons.shield, color: AppColors.primary),
            label: AppStrings.tabs[0],
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book, color: AppColors.primary),
            label: AppStrings.tabs[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.calculate_outlined),
            selectedIcon: const Icon(Icons.calculate, color: AppColors.primary),
            label: AppStrings.tabs[2],
          ),
          NavigationDestination(
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.bolt, color: AppColors.primary),
            label: AppStrings.tabs[3],
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings, color: AppColors.primary),
            label: AppStrings.tabs[4],
          ),
        ],
      ),
    );
  }
}
