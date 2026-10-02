import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/services/device_memory_manager.dart';
import '../../app/theme/tokens.dart';
import '../../shared/providers/player_providers.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/providers/theme_providers.dart';
import '../../shared/animations/motion_system.dart';
import 'custom_title_bar.dart';
import '../../features/player/presentation/widgets/mini_player.dart';
import '../../features/player/presentation/widgets/player_panel.dart';
import '../../features/home/presentation/widgets/navigation_rail.dart';
import '../../features/player/presentation/widgets/immersive/android_sliding_player.dart';
import 'ambient_background.dart';
import '../../features/taste_engine/presentation/taste_playback_observer.dart';
import '../../app/router/router.dart';
import 'navigation_pill/navigation_pill.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const MethodChannel _appLaunchChannel = MethodChannel('com.vikrantruhela.datunes/app_launch');

  @override
  void initState() {
    super.initState();
    _checkLaunchIntent();
  }

  void _checkLaunchIntent() async {
    try {
      final action = await _appLaunchChannel.invokeMethod<String>('getInitialAction');
      if (action == 'open_player') {
        ref.read(immersiveModeProvider.notifier).state = true;
      }
    } catch (_) {}

    _appLaunchChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchIntent' && call.arguments == 'open_player') {
        ref.read(immersiveModeProvider.notifier).state = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final currentSong = ref.watch(currentSongProvider);
    final isImmersive = ref.watch(immersiveModeProvider);
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final showAlbumArt = ref.watch(showAlbumArtBackgroundProvider);
    final isLowRam = !ref.watch(enableExtraEffectsProvider);
    debugPrint(' [AppShell] build - isImmersive: $isImmersive, currentSong: ${currentSong?.title}, showAlbumArt: $showAlbumArt');

    if (isAndroid) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ));
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape || screenWidth >= 900;
    final bool isM3 = ref.watch(appThemeModeProvider) == AppThemeMode.material3;
    final bool isAmoled = ref.watch(appThemeModeProvider) == AppThemeMode.amoled;
    final bool showPlayerPanel = (!isM3 && !isAmoled) && (isLandscape || screenWidth >= 1200);
    final bool showNavRail = isLandscape || screenWidth >= 700;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    final duration = ref.scaledDuration(isImmersive ? DAMotion.large : const Duration(milliseconds: 380));
    final curve = ref.scaledCurve(DAMotion.fastOutSlowIn);

    final containerBorderRadius = (isImmersive || isM3)
        ? BorderRadius.zero
        : (isAndroid && !isLandscape
            ? const BorderRadius.vertical(
                top: Radius.circular(DATokens.radiusXXLarge),
              )
            : BorderRadius.circular(DATokens.radiusXXLarge));

    final containerMargin = (isImmersive || isM3)
        ? EdgeInsets.zero
        : (isAndroid && !isLandscape
            ? const EdgeInsets.only(
                top: DATokens.spacingSmall,
                left: DATokens.spacingSmall,
                right: DATokens.spacingSmall,
                bottom: 0.0,
              )
            : const EdgeInsets.all(DATokens.spacingSmall));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (ref.read(immersiveModeProvider)) {
          ref.read(immersiveModeProvider.notifier).state = false;
          return;
        }

        if (shellNavigatorKey.currentState != null && shellNavigatorKey.currentState!.canPop()) {
          shellNavigatorKey.currentState!.pop();
          return;
        }

        final location = GoRouterState.of(context).matchedLocation;

        if (location != '/') {
          context.go('/');
          return;
        }

        SystemNavigator.pop();
      },
      child: TastePlaybackObserver(
        child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AmbientBackground(
          child: Stack(
            children: [
              SafeArea(
                bottom: !isAndroid || isLandscape,
                child: Column(
                  children: [
                    const CustomTitleBar(),
                    Expanded(
                      child: Row(
                        children: [
                          _DesktopNavRail(visible: showNavRail),
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: isImmersive ? 0.0 : 1.0,
                              duration: duration,
                              curve: curve,
                              child: AnimatedContainer(
                                duration: duration,
                                curve: curve,
                                margin: containerMargin,
                                child: ClipRRect(
                                  borderRadius: containerBorderRadius,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: (showAlbumArt && !isM3)
                                            ? ClipRect(
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(
                                                    sigmaX: isLowRam ? 16.0 : 25.0,
                                                    sigmaY: isLowRam ? 16.0 : 25.0,
                                                  ),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: isImmersive ? Colors.transparent : colors.background.withValues(alpha: 0.50),
                                                      borderRadius: containerBorderRadius,
                                                      border: Border.all(
                                                        color: (isImmersive || isM3) ? Colors.transparent : colors.border.withValues(alpha: 0.4),
                                                        width: (isImmersive || isM3) ? 0.0 : 1.0,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                decoration: BoxDecoration(
                                                  color: isImmersive ? Colors.transparent : colors.background,
                                                  borderRadius: containerBorderRadius,
                                                  border: Border.all(
                                                    color: (isImmersive || isM3) ? Colors.transparent : colors.border.withValues(alpha: 0.4),
                                                    width: (isImmersive || isM3) ? 0.0 : 1.0,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          ignoring: isImmersive,
                                          child: Stack(
                                            children: [
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: ((isLandscape || !isAndroid) && !showPlayerPanel && !isImmersive && ref.watch(currentSongProvider) != null ? 80.0 : 0.0),
                                                ),
                                                child: widget.child,
                                              ),
                                              if ((isLandscape || !isAndroid) && !showPlayerPanel && !isImmersive)
                                                const Align(
                                                  alignment: Alignment.bottomCenter,
                                                  child: MiniPlayer(),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: duration,
                            curve: curve,
                            width: (isAndroid && !isLandscape)
                                ? 0.0
                                : (isImmersive
                                    ? screenWidth
                                    : (showPlayerPanel
                                        ? (screenWidth >= 1200 ? 360.0 : (screenWidth * 0.35).clamp(260.0, 320.0))
                                        : 0.0)),
                            child: ClipRect(
                              child: OverflowBox(
                                minWidth: isImmersive ? screenWidth : 260.0,
                                maxWidth: isImmersive
                                    ? screenWidth
                                    : (screenWidth >= 1200 ? 360.0 : (screenWidth * 0.35).clamp(260.0, 320.0)),
                                alignment: Alignment.centerRight,
                                child: PersistentPlayerPanel(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isAndroid) ...[
                const AndroidSlidingPlayer(),
                AnimatedSlide(
                  offset: (isLandscape || isImmersive) ? const Offset(0, 1.5) : Offset.zero,
                  duration: duration,
                  curve: curve,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _AndroidBottomDock(showPlayerPanel: showPlayerPanel),
                  ),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: (!isAndroid && screenWidth < 700 && !isImmersive)
            ? const _MobileBottomNavBar()
            : null,
      ),
    ),
    );
  }
}

class _DesktopNavRail extends ConsumerWidget {
  final bool visible;

  const _DesktopNavRail({required this.visible});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImmersive = ref.watch(immersiveModeProvider);
    final duration = ref.scaledDuration(isImmersive ? DAMotion.large : const Duration(milliseconds: 380));
    final curve = ref.scaledCurve(DAMotion.fastOutSlowIn);

    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: (visible && !isImmersive) ? 72.0 : 0.0,
      child: ClipRect(
        child: OverflowBox(
          minWidth: 72.0,
          maxWidth: 72.0,
          alignment: Alignment.centerLeft,
          child: AnimatedOpacity(
            opacity: (visible && !isImmersive) ? 1.0 : 0.0,
            duration: duration,
            curve: curve,
            child: NavigationRailWidget(),
          ),
        ),
      ),
    );
  }
}

class _AndroidBottomDock extends ConsumerWidget {
  final bool showPlayerPanel;

  const _AndroidBottomDock({required this.showPlayerPanel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 16.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NavigationPill(),
          ],
        ),
      ),
    );
  }
}

class _MobileBottomNavBar extends ConsumerWidget {
  const _MobileBottomNavBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final location = GoRouterState.of(context).matchedLocation;
    final isM3 = ref.watch(appThemeModeProvider) == AppThemeMode.material3;

    if (isM3) {
      int selectedIndex = 0;
      if (location.startsWith('/search')) selectedIndex = 1;
      else if (location.startsWith('/library')) selectedIndex = 2;
      else if (location.startsWith('/favorites')) selectedIndex = 3;
      else if (location.startsWith('/settings')) selectedIndex = 4;

      return NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0: context.go('/'); break;
            case 1: context.go('/search'); break;
            case 2: context.go('/library'); break;
            case 3: context.go('/favorites'); break;
            case 4: context.go('/settings'); break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search_rounded), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.my_library_music_outlined), selectedIcon: Icon(Icons.my_library_music_rounded), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.favorite_outline_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Favorites'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      );
    }

    return Container(
      height: 64.0,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.65),
        border: Border(
          top: BorderSide(
            color: colors.border.withValues(alpha: 0.4),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MobileNavTab(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            route: '/',
            currentLocation: location,
          ),
          _MobileNavTab(
            icon: Icons.search_outlined,
            selectedIcon: Icons.search,
            route: '/search',
            currentLocation: location,
          ),
          _MobileNavTab(
            icon: Icons.my_library_music_outlined,
            selectedIcon: Icons.my_library_music,
            route: '/library',
            currentLocation: location,
          ),
          _MobileNavTab(
            icon: Icons.favorite_border_outlined,
            selectedIcon: Icons.favorite,
            route: '/favorites',
            currentLocation: location,
          ),
          _MobileNavTab(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            route: '/settings',
            currentLocation: location,
          ),
        ],
      ),
    );
  }
}

class _MobileNavTab extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String route;
  final String currentLocation;

  const _MobileNavTab({
    required this.icon,
    required this.selectedIcon,
    required this.route,
    required this.currentLocation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final isSelected = currentLocation == route;

    return GestureDetector(
      onTap: () => context.go(route),
      child: Icon(
        isSelected ? selectedIcon : icon,
        color: isSelected ? colors.primary : colors.textSecondary,
        size: DATokens.iconMedium,
      ),
    );
  }
}
