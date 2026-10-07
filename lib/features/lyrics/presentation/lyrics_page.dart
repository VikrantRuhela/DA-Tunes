import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../core/services/lyrics_controller.dart';
import '../../../shared/widgets/da_empty_state.dart';
import '../../../shared/widgets/da_image.dart';
import '../../../core/services/device_memory_manager.dart';
import '../../../shared/providers/library_providers.dart';
import '../../../shared/providers/theme_providers.dart';
import '../../../shared/animations/motion_system.dart';

final lyricsActiveIndexProvider = Provider<int>((ref) {
  final position = ref.watch(playbackControllerProvider.select((c) => c.position));
  final lyricsState = ref.watch(lyricsControllerProvider);
  if (lyricsState.syncedLyrics == null || lyricsState.syncedLyrics!.isEmpty) {
    return -1;
  }
  final timestamps = lyricsState.syncedLyrics!.keys.toList()..sort();
  int activeIndex = -1;
  for (int i = 0; i < timestamps.length; i++) {
    if (timestamps[i] <= position) {
      activeIndex = i;
    } else {
      break;
    }
  }
  return activeIndex;
});



class LyricLineWidget extends ConsumerWidget {
  final String text;
  final bool isActive;
  final int index;
  final int activeIndex;
  final VoidCallback onTap;
  final String? timestampText;
  final dynamic colors;

  const LyricLineWidget({
    super.key,
    required this.text,
    required this.isActive,
    required this.index,
    required this.activeIndex,
    required this.onTap,
    this.timestampText,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cleanText = text.replaceAll(RegExp(r'<.*?>'), '').trim();
    final int distanceFromActive = (index - activeIndex).abs();
    final isLowRam = !ref.watch(enableExtraEffectsProvider);
    final double targetBlur = (isActive || isLowRam) ? 0.0 : (distanceFromActive.toDouble() * 1.5).clamp(0.0, 8.0);
    final double targetOpacity = isActive ? 1.0 : (0.45 / distanceFromActive).clamp(0.12, 0.45);

    final isM3 = ref.watch(appThemeModeProvider) == AppThemeMode.material3;
    final isLightM3 = isM3 && ref.watch(m3ThemeModeProvider) == M3ThemeMode.light;
    final lyricColor = isLightM3 ? Theme.of(context).colorScheme.primary : Colors.white;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: targetBlur),
      builder: (context, blurValue, child) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(end: targetOpacity),
          builder: (context, opacityValue, child) {
            Widget textContent = Text(
              cleanText,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: isActive ? 25.0 : 20.0,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: lyricColor,
                height: 1.4,
                shadows: isActive
                    ? [
                        Shadow(
                          color: (isLightM3 ? Theme.of(context).colorScheme.primary : colors.primary).withValues(alpha: 0.5),
                          blurRadius: 10.0,
                        ),
                      ]
                    : null,
              ),
              textAlign: TextAlign.center,
            );

            if (!isLowRam && blurValue > 0.05) {
              textContent = ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
                child: Opacity(
                  opacity: opacityValue,
                  child: textContent,
                ),
              );
            } else {
              textContent = Opacity(
                opacity: opacityValue,
                child: textContent,
              );
            }

            return GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(left: isActive ? 12.0 : 0.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        width: isActive ? 4.0 : 0.0,
                        height: isActive ? 24.0 : 0.0,
                        margin: EdgeInsets.only(right: isActive ? 12.0 : 0.0),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(2.0),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.6),
                              blurRadius: 8.0,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: textContent,
                      ),
                      if (timestampText != null) ...[
                        const SizedBox(width: 16.0),
                        Text(
                          timestampText!,
                          style: TextStyle(
                            fontSize: 12.0,
                            color: Colors.white.withValues(alpha: isActive ? 0.6 : 0.2),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class LyricsPage extends ConsumerStatefulWidget {
  const LyricsPage({super.key});

  @override
  ConsumerState<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends ConsumerState<LyricsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activePlayerPanelProvider.notifier).state = PlayerPanelType.lyrics;
      }
    });
  }

  @override
  void dispose() {
    if (ref.read(activePlayerPanelProvider) == PlayerPanelType.lyrics) {
      ref.read(activePlayerPanelProvider.notifier).state = PlayerPanelType.none;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    final currentSong = ref.watch(currentSongProvider);
    final lyricsState = ref.watch(lyricsControllerProvider);

    if (currentSong == null) {
      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            if (ref.read(activePlayerPanelProvider) == PlayerPanelType.lyrics) {
              ref.read(activePlayerPanelProvider.notifier).state = PlayerPanelType.none;
              if (ref.read(restoreImmersiveOnCloseProvider)) {
                ref.read(immersiveModeProvider.notifier).state = true;
                ref.read(restoreImmersiveOnCloseProvider.notifier).state = false;
              }
            }
          }
        },
        child: Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              color: colors.textPrimary,
              onPressed: () => context.pop(),
            ),
          ),
          body: const Center(
            child: DAEmptyState(
              icon: Icons.music_note_outlined,
              title: 'No Song Playing',
              description: 'Start playing a song to view lyrics.',
            ),
          ),
        ),
      );
    }

    List<Duration> timestamps = [];
    List<String> lines = [];

    if (lyricsState.syncedLyrics != null && lyricsState.syncedLyrics!.isNotEmpty) {
      timestamps = lyricsState.syncedLyrics!.keys.toList()..sort();
      lines = timestamps.map((t) => lyricsState.syncedLyrics![t]!).toList();
    } else if (lyricsState.plainLyrics.isNotEmpty) {
      lines = lyricsState.plainLyrics.split('\n');
    }

    final artworkUrl = currentSong.artworkUrl ?? '';

    final themeMode = ref.watch(appThemeModeProvider);
    final isAmoled = themeMode == AppThemeMode.amoled;
    final isM3 = themeMode == AppThemeMode.material3;
    final m3Mode = ref.watch(m3ThemeModeProvider);
    final isLightM3 = isM3 && m3Mode == M3ThemeMode.light;
    final isDarkM3 = isM3 && m3Mode == M3ThemeMode.dark;
    final colorScheme = Theme.of(context).colorScheme;

    Widget backgroundWidget;
    if (isAmoled) {
      backgroundWidget = Container(color: Colors.black);
    } else if (isLightM3) {
      backgroundWidget = Stack(
        children: [
          Positioned.fill(
            child: DAImage(
              url: artworkUrl,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 45.0, sigmaY: 45.0),
              child: Container(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      );
    } else if (isDarkM3) {
      backgroundWidget = Stack(
        children: [
          Positioned.fill(
            child: DAImage(
              url: artworkUrl,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 45.0, sigmaY: 45.0),
              child: Container(
                color: colorScheme.surface.withValues(alpha: 0.82),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: colorScheme.primaryContainer.withValues(alpha: 0.25),
            ),
          ),
        ],
      );
    } else {
      backgroundWidget = Stack(
        children: [
          Positioned.fill(
            child: DAImage(
              url: artworkUrl,
              fit: BoxFit.cover,
              placeholder: Container(color: colors.surface),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: DeviceMemoryManager.instance.getRecommendedBlurSigma(45.0),
                sigmaY: DeviceMemoryManager.instance.getRecommendedBlurSigma(45.0),
              ),
              child: Container(
                color: Colors.black.withValues(alpha: 0.44),
              ),
            ),
          ),
        ],
      );
    }

    final Color headerTextColor = isLightM3 ? colorScheme.onSurface : Colors.white;
    final Color headerSubtextColor = isLightM3 ? colorScheme.onSurfaceVariant : Colors.white.withValues(alpha: 0.7);
    final Color backIconColor = isLightM3 ? colorScheme.onSurface : Colors.white;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          if (ref.read(activePlayerPanelProvider) == PlayerPanelType.lyrics) {
            ref.read(activePlayerPanelProvider.notifier).state = PlayerPanelType.none;
            if (ref.read(restoreImmersiveOnCloseProvider)) {
              ref.read(immersiveModeProvider.notifier).state = true;
              ref.read(restoreImmersiveOnCloseProvider.notifier).state = false;
            }
          }
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: backgroundWidget),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down, size: 32.0),
                            color: backIconColor,
                            onPressed: () => context.pop(),
                          ),
                          const SizedBox(width: DATokens.spacingSmall),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(DATokens.radiusSmall),
                            child: DAImage(
                              url: artworkUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              placeholder: Icon(Icons.music_note, color: backIconColor),
                            ),
                          ),
                          const SizedBox(width: DATokens.spacingMedium),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSong.title,
                                  style: typography.body.copyWith(
                                    color: headerTextColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  currentSong.artist,
                                  style: typography.caption.copyWith(
                                    color: headerSubtextColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: isLightM3 ? colorScheme.outlineVariant : Colors.white10, height: 1.0),
                    const SizedBox(height: 16.0),
                    Expanded(
                      child: _LyricsGlassContainer(
                        lines: lines,
                        timestamps: timestamps,
                        songId: currentSong.id,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsGlassContainer extends ConsumerStatefulWidget {
  final List<String> lines;
  final List<Duration> timestamps;
  final String songId;

  const _LyricsGlassContainer({
    super.key,
    required this.lines,
    required this.timestamps,
    required this.songId,
  });

  @override
  ConsumerState<_LyricsGlassContainer> createState() => _LyricsGlassContainerState();
}

class _LyricsGlassContainerState extends ConsumerState<_LyricsGlassContainer> {
  final ScrollController _scrollController = ScrollController();
  bool _isUserScrolling = false;
  Timer? _userScrollTimer;
  int _lastActiveIndex = -1;
  List<GlobalKey> _lineKeys = [];

  @override
  void initState() {
    super.initState();
    _lineKeys = List.generate(widget.lines.length, (index) => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant _LyricsGlassContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.songId != oldWidget.songId) {
      _lastActiveIndex = -1;
      _isUserScrolling = false;
      _userScrollTimer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
    if (widget.lines.length != _lineKeys.length) {
      _lineKeys = List.generate(widget.lines.length, (index) => GlobalKey());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _userScrollTimer?.cancel();
    super.dispose();
  }

  void _scrollToActiveLine(int index) {
    if (_isUserScrolling || index < 0 || index >= _lineKeys.length) return;

    final key = _lineKeys[index];
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _formatTimestamp(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final activeIndex = ref.watch(lyricsActiveIndexProvider);

    if (activeIndex != _lastActiveIndex && activeIndex != -1) {
      _lastActiveIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLine(activeIndex);
      });
    }

    final lyricsState = ref.watch(lyricsControllerProvider);
    Widget innerContent;

    if (lyricsState.isLoading) {
      innerContent = const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (lyricsState.isInstrumental) {
      innerContent = Center(
        key: const ValueKey('instrumental'),
        child: Text(
          'Instrumental Track',
          style: context.daTypography.title.copyWith(color: Colors.white),
        ),
      );
    } else if (widget.lines.isEmpty || widget.lines.contains('Lyrics unavailable.')) {
      innerContent = Center(
        key: const ValueKey('unavailable'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lyrics_outlined, color: Colors.white24, size: 48.0),
            const SizedBox(height: DATokens.spacingMedium),
            Text(
              'Lyrics Unavailable',
              style: context.daTypography.body.copyWith(color: Colors.white54),
            ),
          ],
        ),
      );
    } else {
      final height = MediaQuery.of(context).size.height;
      innerContent = ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.15, 0.85, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              if (notification.dragDetails != null) {
                setState(() {
                  _isUserScrolling = true;
                });
                _userScrollTimer?.cancel();
              }
            } else if (notification is ScrollEndNotification) {
              _userScrollTimer?.cancel();
              _userScrollTimer = Timer(const Duration(seconds: 4), () {
                if (mounted) {
                  setState(() {
                    _isUserScrolling = false;
                  });
                  if (activeIndex != -1) {
                    _scrollToActiveLine(activeIndex);
                  }
                }
              });
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              vertical: height / 2 - 40.0,
              horizontal: 24.0,
            ),
            itemCount: widget.lines.length,
            itemBuilder: (context, index) {
              final isActive = index == activeIndex;
              return LyricLineWidget(
                key: _lineKeys[index],
                text: widget.lines[index],
                isActive: isActive,
                index: index,
                activeIndex: activeIndex,
                colors: colors,
                timestampText: (_isUserScrolling && widget.timestamps.isNotEmpty)
                    ? _formatTimestamp(widget.timestamps[index])
                    : null,
                onTap: () {
                  if (widget.timestamps.isNotEmpty) {
                    ref.read(playbackControllerProvider).seek(widget.timestamps[index]);
                    setState(() {
                      _isUserScrolling = false;
                    });
                  }
                },
              );
            },
          ),
        ),
      );
    }

    final themeMode = ref.watch(appThemeModeProvider);
    final isAmoled = themeMode == AppThemeMode.amoled;
    final isM3 = themeMode == AppThemeMode.material3;
    final m3Mode = ref.watch(m3ThemeModeProvider);
    final isLightM3 = isM3 && m3Mode == M3ThemeMode.light;
    final isDarkM3 = isM3 && m3Mode == M3ThemeMode.dark;
    final colorScheme = Theme.of(context).colorScheme;

    BoxDecoration containerDecoration;
    if (isAmoled) {
      containerDecoration = BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: Colors.white30,
          width: 1.0,
        ),
      );
    } else if (isLightM3) {
      containerDecoration = BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.0,
        ),
      );
    } else if (isDarkM3) {
      containerDecoration = BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1.0,
        ),
      );
    } else {
      containerDecoration = BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      );
    }

    Widget contentBody = AnimatedSwitcher(
      duration: ref.scaledDuration(DAMotion.standard),
      switchInCurve: ref.scaledCurve(DAMotion.enterCurve),
      switchOutCurve: ref.scaledCurve(DAMotion.exitCurve),
      child: KeyedSubtree(
        key: ValueKey<String>('${widget.songId}_${lyricsState.isLoading}'),
        child: innerContent,
      ),
    );

    return Stack(
      children: [
        Container(
          decoration: containerDecoration,
          clipBehavior: Clip.antiAlias,
          child: isAmoled
              ? contentBody
              : BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: DeviceMemoryManager.instance.getRecommendedBlurSigma(20.0),
                    sigmaY: DeviceMemoryManager.instance.getRecommendedBlurSigma(20.0),
                  ),
                  child: contentBody,
                ),
        ),
        if (_isUserScrolling && widget.timestamps.isNotEmpty)
          Positioned(
            bottom: 30,
            right: 30,
            child: FloatingActionButton.extended(
              backgroundColor: isM3 ? colorScheme.primary : colors.primary,
              onPressed: () {
                setState(() {
                  _isUserScrolling = false;
                });
                if (activeIndex != -1) {
                  _scrollToActiveLine(activeIndex);
                }
              },
              icon: Icon(Icons.sync, color: isM3 ? colorScheme.onPrimary : Colors.white),
              label: Text(
                'Sync View',
                style: TextStyle(color: isM3 ? colorScheme.onPrimary : Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
