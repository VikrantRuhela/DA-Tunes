import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import placeholder screens
import '../../features/home/presentation/home_page.dart';
import '../../features/library/presentation/library_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/lyrics/presentation/lyrics_page.dart';
import '../../features/queue/presentation/queue_page.dart';
import '../../features/favorites/presentation/favorites_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/album/presentation/album_page.dart';
import '../../features/artist/presentation/artist_page.dart';
import '../../shared/widgets/app_shell.dart';
import '../../features/onboarding/presentation/welcome_page.dart';
import '../../features/onboarding/presentation/guest_onboarding_page.dart';
import '../../shared/providers/backend_providers.dart';
import '../../shared/animations/motion_system.dart';

// Global navigator key
final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// Reactive router configuration provider.
final goRouterProvider = Provider<GoRouter>((ref) {
  final sessionManager = ref.watch(sessionManagerProvider);

  return GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: true,
    refreshListenable: sessionManager,
    redirect: (context, state) {
      final isLoggedIn = sessionManager.isLoggedIn;
      final isGuestMode = sessionManager.isGuestMode;
      final isGuestOnboardingCompleted = sessionManager.isGuestOnboardingCompleted;
      final isGoingToWelcome = state.matchedLocation == '/welcome';
      final isGoingToOnboarding = state.matchedLocation == '/onboarding';

      if (!isLoggedIn && !isGuestMode) {
        return '/welcome';
      }

      if (isGuestMode && !isGuestOnboardingCompleted) {
        if (!isGoingToOnboarding) {
          return '/onboarding';
        }
        return null;
      }

      if (isGoingToWelcome && (isLoggedIn || isGuestMode)) {
        return '/';
      }

      if (isGoingToOnboarding && (isLoggedIn || (isGuestMode && isGuestOnboardingCompleted))) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) => DAMotion.buildPageTransition(
          key: state.pageKey,
          child: const WelcomePage(),
          type: DAPageTransitionType.fade,
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => DAMotion.buildPageTransition(
          key: state.pageKey,
          child: const GuestOnboardingPage(),
          type: DAPageTransitionType.fade,
        ),
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) {
          return AppShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => DAMotion.buildPageTransition(
              key: state.pageKey,
              child: const HomePage(),
              type: DAPageTransitionType.tab,
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) {
              final query = state.uri.queryParameters['q'] ?? '';
              return DAMotion.buildPageTransition(
                key: state.pageKey,
                child: SearchPage(initialQuery: query),
                type: DAPageTransitionType.tab,
              );
            },
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) => DAMotion.buildPageTransition(
              key: state.pageKey,
              child: const LibraryPage(),
              type: DAPageTransitionType.tab,
            ),
          ),
          GoRoute(
            path: '/player',
            pageBuilder: (context, state) => DAMotion.buildPageTransition(
              key: state.pageKey,
              child: const PlayerPage(),
              type: DAPageTransitionType.modal,
            ),
          ),
          GoRoute(
            path: '/lyrics',
            pageBuilder: (context, state) => DAMotion.buildPageTransition(
              key: state.pageKey,
              child: const LyricsPage(),
              type: DAPageTransitionType.modal,
            ),
          ),
          GoRoute(
            path: '/queue',
            pageBuilder: (context, state) => DAMotion.buildPageTransition(
              key: state.pageKey,
              child: const QueuePage(),
              type: DAPageTransitionType.modal,
            ),
          ),
          GoRoute(
            path: '/favorites',
            pageBuilder: (context, state) => DAMotion.buildPageTransition(
              key: state.pageKey,
              child: const FavoritesPage(),
              type: DAPageTransitionType.tab,
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => DAMotion.buildPageTransition(
              key: state.pageKey,
              child: const SettingsPage(),
              type: DAPageTransitionType.tab,
            ),
          ),
          GoRoute(
            path: '/album/:id',
            pageBuilder: (context, state) {
              final albumId = state.pathParameters['id'] ?? '';
              return DAMotion.buildPageTransition(
                key: state.pageKey,
                child: AlbumPage(albumId: albumId),
                type: DAPageTransitionType.hierarchical,
              );
            },
          ),
          GoRoute(
            path: '/artist/:id',
            pageBuilder: (context, state) {
              final artistId = state.pathParameters['id'] ?? '';
              return DAMotion.buildPageTransition(
                key: state.pageKey,
                child: ArtistPage(artistId: artistId),
                type: DAPageTransitionType.hierarchical,
              );
            },
          ),
        ],
      ),
    ],
  );
});
