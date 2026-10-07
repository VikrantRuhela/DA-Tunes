import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../app/theme/tokens.dart';
import '../../../../../shared/providers/player_providers.dart';
import '../../../../../shared/providers/library_providers.dart';
import '../../../../../shared/models/playback_state.dart';
import '../../../../../shared/models/music_models.dart';
import '../../../../../shared/utils/song_options.dart';
import '../../../../../shared/widgets/da_image.dart';
import '../../../../../core/services/device_memory_manager.dart';
import 'immersive_player.dart';
import '../../../../../shared/providers/theme_providers.dart';
import '../../../../../shared/widgets/m3_play_pause_button.dart';
import '../../../../../shared/animations/motion_system.dart';

class _RoundedTrackShape extends SliderTrackShape {
  const _RoundedTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 6.0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final paintActive = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.blue
      ..style = PaintingStyle.fill;
    final paintInactive = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final trackRadius = Radius.circular(sliderTheme.trackHeight! / 2);

    final activeRect = RRect.fromLTRBAndCorners(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
      topLeft: trackRadius,
      bottomLeft: trackRadius,
      topRight: trackRadius,
      bottomRight: trackRadius,
    );
    context.canvas.drawRRect(activeRect, paintActive);

    if (thumbCenter.dx < trackRect.right) {
      final inactiveRect = RRect.fromLTRBAndCorners(
        thumbCenter.dx,
        trackRect.top,
        trackRect.right,
        trackRect.bottom,
        topLeft: trackRadius,
        bottomLeft: trackRadius,
        topRight: trackRadius,
        bottomRight: trackRadius,
      );
      context.canvas.drawRRect(inactiveRect, paintInactive);
    }
  }
}

class ImmersivePlaybackButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;

  const ImmersivePlaybackButton({
    super.key,
    required this.icon,
    required this.size,
    this.onPressed,
  });

  @override
  State<ImmersivePlaybackButton> createState() => _ImmersivePlaybackButtonState();
}

class _ImmersivePlaybackButtonState extends State<ImmersivePlaybackButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onPressed != null;

    return MouseRegion(
      onEnter: (_) {
        if (isInteractive) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (isInteractive) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (isInteractive) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (isInteractive) setState(() => _isPressed = false);
        },
        onTapCancel: () {
          if (isInteractive) setState(() => _isPressed = false);
        },
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.90 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 100),
          child: AnimatedOpacity(
            opacity: isInteractive ? (_isHovered ? 1.0 : 0.8) : 0.35,
            duration: const Duration(milliseconds: 150),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Icon(
                widget.icon,
                size: widget.size,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AndroidSlidingPlayer extends ConsumerStatefulWidget {
  const AndroidSlidingPlayer({super.key});

  @override
  ConsumerState<AndroidSlidingPlayer> createState() => _AndroidSlidingPlayerState();
}



class _AndroidSlidingPlayerState extends ConsumerState<AndroidSlidingPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DAMotion.playerDuration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: DAMotion.enterCurve,
      reverseCurve: DAMotion.exitCurve,
    )..addListener(_onAnimationTick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(immersiveModeProvider)) {
        _controller.value = 1.0;
      }
    });
  }

  void _onAnimationTick() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString();
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getCodec(Song? song) {
    if (song == null) return 'AAC';
    if (song.source == 'youtube' || song.source == 'youtube_music') {
      return 'OPUS';
    }
    final path = song.id.toLowerCase();
    if (path.endsWith('.mp3')) return 'MP3';
    if (path.endsWith('.flac')) return 'FLAC';
    if (path.endsWith('.m4a') || path.endsWith('.mp4')) return 'M4A';
    if (path.endsWith('.wav')) return 'WAV';
    return 'AAC';
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongProvider);
    if (currentSong == null) {
      _controller.value = 0.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(immersiveModeProvider.notifier).state = false;
      });
      return const SizedBox.shrink();
    }
    final bool isYoutubeUpload = currentSong.source == 'youtube' ||
        currentSong.source == 'youtube_music' ||
        (currentSong.artworkUrl?.contains('ytimg.com') ?? false) ||
        (currentSong.artworkUrl?.contains('googleusercontent.com') ?? false);

    final isImmersive = ref.watch(immersiveModeProvider);
    if (isImmersive && _controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    } else if (!isImmersive && _controller.status == AnimationStatus.completed) {
      _controller.reverse();
    }

    ref.listen<bool>(immersiveModeProvider, (previous, next) {
      if (next) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });

    final colors = context.daColors;
    final typography = context.daTypography;
    final playbackState = ref.watch(playbackStateProvider);
    final style = ref.watch(playerStyleProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final isM3 = themeMode == AppThemeMode.material3;
    final isAmoled = themeMode == AppThemeMode.amoled;

    final isPlaying = playbackState.status == PlaybackStatus.playing;
    final isLiked = ref.watch(libraryManagerProvider).isSongLiked(currentSong.id);

    final codec = _getCodec(currentSong);
    final artworkUrl = currentSong.artworkUrl;
    final isLowRam = !ref.watch(enableExtraEffectsProvider);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape || screenWidth >= 900;

    final t = _animation.value;
    if (t == 0.0 && !isImmersive) {
      return _buildMiniPlayerLayout(context, currentSong, colors, typography, isPlaying);
    }

    final double screenHeight = MediaQuery.of(context).size.height;
    final double controlsTopRatio = screenHeight < 720.0
        ? 0.45
        : (screenHeight < 800.0 ? 0.48 : 0.52);
    final double expandedArtHeight = screenHeight * controlsTopRatio;

    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double bottom = (1.0 - t) * (82.0 + bottomPadding);
    final double height = 74.0 + t * (screenHeight - 74.0 - bottom);
    final double left = (1.0 - t) * 16.0;
    final double right = (1.0 - t) * 16.0;
    final double radius = (1.0 - t) * DATokens.radiusLarge;

    final double miniOpacity = (1.0 - t * 5.0).clamp(0.0, 1.0);
    final double fullOpacity = ((t - 0.2) / 0.8).clamp(0.0, 1.0);

    final double artWidth = 40.0 + t * (screenWidth - 40.0);
    final double artHeight = 40.0 + t * (expandedArtHeight - 40.0);
    final double artLeft = 16.0 * (1.0 - t);
    final double artTop = 12.0 * (1.0 - t);
    final double artRadius = 8.0 * (1.0 - t);

    return Positioned(
      left: left,
      right: right,
      bottom: bottom,
      height: height,
      child: PopScope(
        canPop: !isImmersive,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && isImmersive) {
            _controller.animateTo(0.0, duration: DAMotion.playerDuration, curve: DAMotion.exitCurve).then((_) {
              ref.read(immersiveModeProvider.notifier).state = false;
            });
          }
        },
        child: AnimatedSlide(
          offset: isLandscape ? const Offset(0, 1.5) : Offset.zero,
          duration: DAMotion.playerDuration,
          curve: isImmersive ? DAMotion.enterCurve : DAMotion.exitCurve,
          child: GestureDetector(
              onVerticalDragUpdate: (details) {
                final delta = details.primaryDelta ?? 0.0;
                _controller.value -= delta / screenHeight;
              },
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0.0;
                final shouldClose = velocity > 300 || (velocity >= -300 && _controller.value < 0.6);
                if (shouldClose) {
                  _controller.animateTo(0.0, duration: DAMotion.playerDuration, curve: DAMotion.exitCurve).then((_) {
                    ref.read(immersiveModeProvider.notifier).state = false;
                  });
                } else {
                  _controller.animateTo(1.0, duration: DAMotion.playerDuration, curve: DAMotion.enterCurve).then((_) {
                    ref.read(immersiveModeProvider.notifier).state = true;
                  });
                }
              },
            child: Container(
              decoration: BoxDecoration(
                color: colors.background.withOpacity(0.6 + t * 0.4),
                borderRadius: BorderRadius.circular(radius),
                border: t < 1.0
                    ? Border.all(
                        color: colors.border.withOpacity(0.2 * (1.0 - t)),
                        width: 1.0,
                      )
                    : null,
                boxShadow: t < 1.0
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2 * (1.0 - t)),
                          blurRadius: 10.0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: DeviceMemoryManager.instance.getRecommendedBlurSigma(16.0),
                    sigmaY: DeviceMemoryManager.instance.getRecommendedBlurSigma(16.0),
                  ),
                  child: Stack(
                    children: [
                      if (t > 0.01)
                        Positioned.fill(
                          child: Opacity(
                            opacity: t,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Container(
                                    color: isAmoled ? Colors.black : colors.background,
                                  ),
                                ),
                                if (!isAmoled) ...[
                                  Positioned.fill(
                                    child: SubtleAmbientBlobs(
                                      primaryColor: colors.primary,
                                      accentColor: colors.accent,
                                    ),
                                  ),
                                  if (artworkUrl != null && artworkUrl.isNotEmpty) ...[
                                    if (!isLowRam || (style == PlayerStyle.vinyl || style == PlayerStyle.minimal)) ...[
                                      Positioned.fill(
                                        child: Opacity(
                                          opacity: 0.40,
                                          child: DAImage(
                                            url: artworkUrl,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(
                                            sigmaX: isLowRam ? 32.0 : 40.0,
                                            sigmaY: isLowRam ? 32.0 : 40.0,
                                          ),
                                          child: Container(color: Colors.transparent),
                                        ),
                                      ),
                                    ] else ...[
                                      Positioned.fill(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                colors.gradientStart.withValues(alpha: 0.8),
                                                colors.gradientMiddle,
                                                colors.gradientEnd,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: ShaderMask(
                                          shaderCallback: (rect) {
                                            return LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.black.withValues(alpha: 0.35),
                                                Colors.transparent,
                                              ],
                                              stops: const [0.0, 0.7],
                                            ).createShader(rect);
                                          },
                                          blendMode: BlendMode.dstIn,
                                          child: DAImage(
                                            url: artworkUrl,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (isM3) ...[
                        if (fullOpacity > 0.0)
                          Positioned.fill(
                            child: Opacity(
                              opacity: fullOpacity,
                              child: const Material3Player(),
                            ),
                          ),
                      ] else if (style == PlayerStyle.immersive) ...[
                        Positioned(
                          left: artLeft,
                          top: artTop,
                          width: artWidth,
                          height: artHeight,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(artRadius),
                            child: ShaderMask(
                              shaderCallback: (rect) {
                                return const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white,
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                  stops: [0.0, 0.88, 1.0],
                                ).createShader(rect);
                              },
                              blendMode: BlendMode.dstIn,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Transform.scale(
                                      scale: isYoutubeUpload ? (1.0 + t * 0.35) : 1.0,
                                      child: DAImage(
                                        url: artworkUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(color: colors.surfaceCard),
                                      ),
                                    ),
                                  ),
                                  if (t > 0.01)
                                    Positioned.fill(
                                      child: Opacity(
                                        opacity: fullOpacity,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                colors.background.withValues(alpha: 0.0),
                                                colors.background.withValues(alpha: 0.15),
                                                colors.background.withValues(alpha: 0.55),
                                                colors.background,
                                              ],
                                              stops: const [0.0, 0.45, 0.75, 1.0],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (fullOpacity > 0.0) ...[
                          Positioned(
                            top: expandedArtHeight,
                            left: 0,
                            right: 0,
                            bottom: MediaQuery.of(context).padding.bottom + 8.0,
                            child: Opacity(
                              opacity: fullOpacity,
                              child: _buildImmersiveExpandedLayout(context, currentSong, colors, typography, isLiked, isPlaying, codec),
                            ),
                          ),
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 8.0,
                            right: 16.0,
                            child: Opacity(
                              opacity: fullOpacity,
                              child: IconButton(
                                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28.0),
                                onPressed: () => ref.read(immersiveModeProvider.notifier).state = false,
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        if (fullOpacity > 0.0)
                          Positioned.fill(
                            child: Opacity(
                              opacity: fullOpacity,
                              child: style == PlayerStyle.vinyl
                                  ? const VinylStylePlayerExpanded()
                                  : const MinimalStylePlayerExpanded(),
                            ),
                          ),
                      ],
                      if (miniOpacity > 0.0)
                        Opacity(
                          opacity: miniOpacity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                const SizedBox(width: 52.0),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentSong.title,
                                        style: typography.body.copyWith(fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        currentSong.artist,
                                        style: typography.caption.copyWith(color: colors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isPlaying ? Icons.pause : Icons.play_arrow,
                                          color: colors.textPrimary,
                                          size: 28.0,
                                        ),
                                        onPressed: () {
                                          if (isPlaying) {
                                            ref.read(playbackControllerProvider).pause();
                                          } else {
                                            ref.read(playbackControllerProvider).resume();
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.skip_next,
                                          color: colors.textPrimary,
                                          size: 24.0,
                                        ),
                                        onPressed: () => ref.read(playbackControllerProvider).next(),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.more_vert,
                                          color: colors.textSecondary,
                                          size: 24.0,
                                        ),
                                        onPressed: () => showSongOptionsMenu(context, ref, currentSong),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (t == 0.0)
                        const _SlidingPlayerMiniProgressBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ),
  );
}

  Widget _buildImmersiveExpandedLayout(
    BuildContext context,
    Song currentSong,
    dynamic colors,
    dynamic typography,
    bool isLiked,
    bool isPlaying,
    String codec,
  ) {

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DATokens.spacingLarge,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          SwipeableArtwork(
            onSwipeLeft: () => ref.read(playbackControllerProvider).next(),
            onSwipeRight: () => ref.read(playbackControllerProvider).previous(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentSong.title,
                  style: typography.title.copyWith(
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        currentSong.artist,
                        style: typography.body.copyWith(
                          fontSize: 15.0,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (currentSong.album.isNotEmpty) ...[
                      Text(
                        ' • ',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      Flexible(
                        child: Text(
                          currentSong.album,
                          style: typography.body.copyWith(
                            fontSize: 15.0,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    Text(
                      ' • ',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    Text(
                      codec.toUpperCase(),
                      style: typography.caption.copyWith(
                        fontSize: 11.0,
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const _SlidingPlayerProgressBar(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ImmersivePlaybackButton(
                icon: Icons.fast_rewind_rounded,
                size: 36.0,
                onPressed: () => ref.read(playbackControllerProvider).previous(),
              ),
              const SizedBox(width: 24.0),
              ImmersivePlaybackButton(
                icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 48.0,
                onPressed: () {
                  if (isPlaying) {
                    ref.read(playbackControllerProvider).pause();
                  } else {
                    ref.read(playbackControllerProvider).resume();
                  }
                },
              ),
              const SizedBox(width: 24.0),
              ImmersivePlaybackButton(
                icon: Icons.fast_forward_rounded,
                size: 36.0,
                onPressed: () => ref.read(playbackControllerProvider).next(),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.queue_music, color: Colors.white60, size: 24.0),
                onPressed: () => PlayerPanelController.toggleQueue(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.white60, size: 24.0),
                onPressed: () => PlayerPanelController.toggleLyrics(context, ref),
              ),
              Builder(
                builder: (context) {
                  final timerState = ref.watch(sleepTimerNotifierProvider);
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: timerState.isActive
                        ? GestureDetector(
                            key: const ValueKey('active_timer'),
                            onTap: () => showSleepTimerDialog(context, ref),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              child: Text(
                                timerState.formattedRemaining,
                                style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        : IconButton(
                            key: const ValueKey('inactive_timer'),
                            icon: const Icon(Icons.dark_mode_outlined, color: Colors.white60, size: 24.0),
                            onPressed: () => showSleepTimerDialog(context, ref),
                          ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayerLayout(
    BuildContext context,
    Song currentSong,
    dynamic colors,
    dynamic typography,
    bool isPlaying,
  ) {

    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape || screenWidth >= 900;
    final isM3 = ref.watch(appThemeModeProvider) == AppThemeMode.material3;
    return Positioned(
      left: 16.0,
      right: 16.0,
      bottom: 82.0 + bottomPadding,
      height: 74.0,
      child: AnimatedSlide(
        offset: isLandscape ? const Offset(0, 2.5) : Offset.zero,
        duration: const Duration(milliseconds: 380),
        curve: Curves.fastOutSlowIn,
        child: GestureDetector(
        onTap: () {
          ref.read(immersiveModeProvider.notifier).state = true;
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
            ref.read(immersiveModeProvider.notifier).state = true;
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DATokens.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DATokens.radiusLarge),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: DeviceMemoryManager.instance.getRecommendedBlurSigma(16.0),
                sigmaY: DeviceMemoryManager.instance.getRecommendedBlurSigma(16.0),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceCard.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.2),
                    width: 1.0,
                  ),
                ),
                child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Container(
                          width: 40.0,
                          height: 40.0,
                          decoration: BoxDecoration(
                            color: colors.surfaceHover,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: DAImage(
                            url: currentSong.artworkUrl,
                            fit: BoxFit.cover,
                            placeholder: Icon(Icons.music_note, color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentSong.title,
                                style: typography.body.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                currentSong.artist,
                                style: typography.caption.copyWith(color: colors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: colors.textPrimary,
                                  size: 28.0,
                                ),
                                onPressed: () {
                                  if (isPlaying) {
                                    ref.read(playbackControllerProvider).pause();
                                  } else {
                                    ref.read(playbackControllerProvider).resume();
                                  }
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.skip_next,
                                  color: colors.textPrimary,
                                  size: 24.0,
                                ),
                                onPressed: () => ref.read(playbackControllerProvider).next(),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: colors.textSecondary,
                                  size: 24.0,
                                ),
                                onPressed: () => showSongOptionsMenu(context, ref, currentSong),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _SlidingPlayerMiniProgressBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}

class _SlidingPlayerProgressBar extends ConsumerStatefulWidget {
  const _SlidingPlayerProgressBar();

  @override
  ConsumerState<_SlidingPlayerProgressBar> createState() => _SlidingPlayerProgressBarState();
}

class _SlidingPlayerProgressBarState extends ConsumerState<_SlidingPlayerProgressBar> {
  double? _dragValue;

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString();
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final currentSong = ref.watch(currentSongProvider);
    if (currentSong == null) return const SizedBox.shrink();

    final position = ref.watch(playbackControllerProvider.select((c) => c.position));
    final duration = currentSong.duration;
    final double progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final displayPosition = _dragValue != null
        ? Duration(milliseconds: (_dragValue! * duration.inMilliseconds).toInt())
        : position;

    final isLiked = ref.watch(libraryManagerProvider).isSongLiked(currentSong.id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                ref.watch(repeatModeProvider) == RepeatMode.one
                    ? Icons.repeat_one_rounded
                    : (ref.watch(repeatModeProvider) == RepeatMode.all ? Icons.repeat_on_rounded : Icons.repeat_rounded),
                color: ref.watch(repeatModeProvider) != RepeatMode.off ? colors.primary : Colors.white70,
                size: 22.0,
              ),
              onPressed: () {
                final currentMode = ref.read(repeatModeProvider);
                RepeatMode nextMode;
                if (currentMode == RepeatMode.off) {
                  nextMode = RepeatMode.all;
                } else if (currentMode == RepeatMode.all) {
                  nextMode = RepeatMode.one;
                } else {
                  nextMode = RepeatMode.off;
                }
                ref.read(playbackControllerProvider).setRepeatMode(nextMode);
              },
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6.0,
                  trackShape: const _RoundedTrackShape(),
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  thumbColor: colors.primary,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0.0),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 0.0),
                ),
                child: Slider(
                  value: _dragValue ?? progress,
                  onChanged: (val) {
                    setState(() {
                      _dragValue = val;
                    });
                  },
                  onChangeEnd: (val) {
                    ref.read(playbackControllerProvider).seek(
                          Duration(milliseconds: (val * duration.inMilliseconds).toInt()),
                        );
                    setState(() {
                      _dragValue = null;
                    });
                  },
                ),
              ),
            ),
            Builder(
              builder: (btnContext) => IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white70, size: 22.0),
                onPressed: () => showSongOptionsMenu(btnContext, ref, currentSong),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(displayPosition),
                style: typography.caption.copyWith(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.0),
              ),
              Text(
                _formatDuration(duration),
                style: typography.caption.copyWith(color: Colors.white.withValues(alpha: 0.5), fontSize: 11.0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlidingPlayerMiniProgressBar extends ConsumerWidget {
  const _SlidingPlayerMiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final currentSong = ref.watch(currentSongProvider);
    if (currentSong == null) return const SizedBox.shrink();

    final position = ref.watch(playbackControllerProvider.select((c) => c.position));
    final duration = currentSong.duration;
    final double progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 3.0,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: colors.border.withValues(alpha: 0.3),
        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
      ),
    );
  }
}
