import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../app/theme/tokens.dart';
import '../../../../../shared/providers/player_providers.dart';
import '../../../../../shared/providers/library_providers.dart';
import '../../../../../shared/providers/theme_providers.dart';
import '../../../../../shared/models/playback_state.dart';
import '../../../../../shared/models/music_models.dart';
import '../../../../../shared/utils/song_options.dart';
import '../../../../../shared/widgets/da_image.dart';
import '../../../../../core/services/device_memory_manager.dart';
import '../../../../../core/services/lyrics_controller.dart';
import '../vinyl_player_widget.dart';
import 'immersive_background.dart';
import 'progress_section.dart';
import 'playback_controls.dart';

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
    final double trackHeight = sliderTheme.trackHeight ?? 4.0;
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

class ImmersivePlayer extends ConsumerWidget {
  const ImmersivePlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(playerStyleProvider);
    final isWindows = Theme.of(context).platform == TargetPlatform.windows ||
                      Theme.of(context).platform == TargetPlatform.macOS ||
                      Theme.of(context).platform == TargetPlatform.linux;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape || screenWidth >= 900;
    final bool useLandscapePlayer = isWindows || isLandscape;

    final colors = context.daColors;

    final isM3 = ref.watch(appThemeModeProvider) == AppThemeMode.material3;

    Widget playerWidget;
    if (isM3) {
      playerWidget = const _Material3Player();
    } else {
      switch (style) {
        case PlayerStyle.vinyl:
          playerWidget = const _VinylStylePlayer();
          break;
        case PlayerStyle.minimal:
          playerWidget = const _MinimalStylePlayer();
          break;
        case PlayerStyle.immersive:
        default:
          playerWidget = useLandscapePlayer ? const _WindowsImmersivePlayer() : const _ImmersiveStylePlayer();
          break;
      }
    }

    final currentSong = ref.watch(currentSongProvider);
    final artworkUrl = currentSong?.artworkUrl;
    final isLowRam = !ref.watch(enableExtraEffectsProvider);
    final isVinylOrMinimal = style == PlayerStyle.vinyl || style == PlayerStyle.minimal;
    final isAmoled = ref.watch(appThemeModeProvider) == AppThemeMode.amoled;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
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
              if (!isLowRam || isVinylOrMinimal) ...[
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
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: ClipRect(
                key: ValueKey(useLandscapePlayer),
                child: playerWidget,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VinylStylePlayerExpanded extends StatelessWidget {
  const VinylStylePlayerExpanded({super.key});
  @override
  Widget build(BuildContext context) {
    return const _VinylStylePlayer();
  }
}

class MinimalStylePlayerExpanded extends StatelessWidget {
  const MinimalStylePlayerExpanded({super.key});
  @override
  Widget build(BuildContext context) {
    return const _MinimalStylePlayer();
  }
}

class _WindowsImmersivePlayer extends ConsumerStatefulWidget {
  const _WindowsImmersivePlayer();

  @override
  ConsumerState<_WindowsImmersivePlayer> createState() => _WindowsImmersivePlayerState();
}

class _WindowsImmersivePlayerState extends ConsumerState<_WindowsImmersivePlayer> {
  int _activeTab = 0;

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
    final colors = context.daColors;
    final typography = context.daTypography;
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(playbackControllerProvider.select((c) => c.status == PlaybackStatus.playing));
    final isLiked = currentSong != null && ref.watch(libraryManagerProvider).isSongLiked(currentSong.id);

    final artworkUrl = currentSong?.artworkUrl;
    final codec = _getCodec(currentSong);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final width = constraints.maxWidth;

          final bool isCompactHeight = height < 500.0;
          final bool isMediumHeight = height >= 500.0 && height < 680.0;

          final double topPadding = isCompactHeight ? 24.0 : (isMediumHeight ? 32.0 : 48.0);
          final double bottomPadding = isCompactHeight ? 12.0 : (isMediumHeight ? 18.0 : 24.0);
          final double horizontalPadding = isCompactHeight ? 16.0 : (isMediumHeight ? 32.0 : 48.0);

          final double artworkSize = isCompactHeight ? 110.0 : (isMediumHeight ? 180.0 : 320.0);

          final double titleFontSize = isCompactHeight ? 16.0 : (isMediumHeight ? 22.0 : 28.0);
          final double artistFontSize = isCompactHeight ? 12.0 : (isMediumHeight ? 15.0 : 18.0);

          final double tabPadding = isCompactHeight ? 12.0 : 24.0;

          return Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, topPadding, horizontalPadding, bottomPadding),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Padding(
                          padding: EdgeInsets.only(right: horizontalPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20.0),
                                    onPressed: () => ref.read(immersiveModeProvider.notifier).state = false,
                                  ),
                                  const SizedBox(width: 8.0),
                                  Text(
                                    'NOW PLAYING',
                                    style: typography.caption.copyWith(
                                      color: Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ],
                              ),
                              if (isCompactHeight) const SizedBox(height: 8.0) else const Spacer(flex: 3),
                              Center(
                                child: Container(
                                  width: artworkSize,
                                  height: artworkSize,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16.0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        blurRadius: isCompactHeight ? 12.0 : 24.0,
                                        offset: Offset(0, isCompactHeight ? 4.0 : 8.0),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16.0),
                                    child: DAImage(
                                      url: artworkUrl,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              if (isCompactHeight) const SizedBox(height: 8.0) else const Spacer(flex: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          currentSong?.title ?? 'No Track Selected',
                                          style: typography.title.copyWith(
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4.0),
                                        Text(
                                          currentSong?.artist ?? 'Unknown Artist',
                                          style: typography.body.copyWith(
                                            fontSize: artistFontSize,
                                            color: Colors.white.withOpacity(0.6),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  _PlaybackIconButton(
                                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                                    color: isLiked ? Colors.redAccent : Colors.white70,
                                    size: 24.0,
                                    onPressed: currentSong != null
                                        ? () => ref.read(libraryManagerProvider.notifier).toggleLikeSong(currentSong)
                                        : null,
                                  ),
                                  Builder(
                                    builder: (btnContext) => _PlaybackIconButton(
                                      icon: Icons.more_vert,
                                      color: Colors.white70,
                                      size: 24.0,
                                      onPressed: currentSong != null
                                          ? () => showSongOptionsMenu(btnContext, ref, currentSong)
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isCompactHeight ? 8.0 : 24.0),
                              _WindowsPlayerProgressBar(
                                codec: codec,
                                isCompactHeight: isCompactHeight,
                              ),
                              SizedBox(height: isCompactHeight ? 12.0 : 32.0),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ImmersivePlaybackButton(
                                    icon: Icons.fast_rewind_rounded,
                                    size: isCompactHeight ? 28.0 : 36.0,
                                    onPressed: () => ref.read(playbackControllerProvider).previous(),
                                  ),
                                  SizedBox(width: isCompactHeight ? 16.0 : 32.0),
                                  ImmersivePlaybackButton(
                                    icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: isCompactHeight ? 36.0 : 48.0,
                                    onPressed: () {
                                      if (isPlaying) {
                                        ref.read(playbackControllerProvider).pause();
                                      } else {
                                        ref.read(playbackControllerProvider).resume();
                                      }
                                    },
                                  ),
                                  SizedBox(width: isCompactHeight ? 16.0 : 32.0),
                                  ImmersivePlaybackButton(
                                    icon: Icons.fast_forward_rounded,
                                    size: isCompactHeight ? 28.0 : 36.0,
                                    onPressed: () => ref.read(playbackControllerProvider).next(),
                                  ),
                                ],
                              ),
                              if (isCompactHeight) const SizedBox(height: 8.0) else const Spacer(flex: 1),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(24.0),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24.0),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: DeviceMemoryManager.instance.getRecommendedBlurSigma(12.0),
                                sigmaY: DeviceMemoryManager.instance.getRecommendedBlurSigma(12.0),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(tabPadding),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(16.0),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: _TabButton(
                                              label: 'Lyrics',
                                              isActive: _activeTab == 0,
                                              onTap: () => setState(() => _activeTab = 0),
                                            ),
                                          ),
                                          Expanded(
                                            child: _TabButton(
                                              label: 'Queue',
                                              isActive: _activeTab == 1,
                                              onTap: () => setState(() => _activeTab = 1),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: isCompactHeight ? 12.0 : 24.0),
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        child: _activeTab == 0
                                            ? const _WindowsLyricsTab(key: ValueKey('lyrics'))
                                            : const _WindowsQueueTab(key: ValueKey('queue')),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          decoration: BoxDecoration(
            color: widget.isActive
                ? colors.primary
                : (_isHovered ? Colors.white.withOpacity(0.06) : Colors.transparent),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: typography.body.copyWith(
              color: widget.isActive ? colors.primary.contrastingColor : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;
  final Color? color;

  const _PlaybackIconButton({
    required this.icon,
    this.size = 28.0,
    this.onPressed,
    this.color,
  });

  @override
  State<_PlaybackIconButton> createState() => _PlaybackIconButtonState();
}

class _PlaybackIconButtonState extends State<_PlaybackIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.92 : (_isHovered ? 1.08 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: _isHovered ? Colors.white.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: widget.color ?? (widget.onPressed != null ? Colors.white : Colors.white30),
            ),
          ),
        ),
      ),
    );
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

class _TabLyricLineWidget extends StatelessWidget {
  final String text;
  final bool isActive;
  final int index;
  final int activeIndex;
  final VoidCallback onTap;
  final String? timestampText;
  final dynamic colors;

  const _TabLyricLineWidget({
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
  Widget build(BuildContext context) {
    final cleanText = text.replaceAll(RegExp(r'<.*?>'), '').trim();
    final int distanceFromActive = (index - activeIndex).abs();
    final double targetBlur = isActive ? 0.0 : (distanceFromActive.toDouble() * 1.5).clamp(0.0, 8.0);
    final double targetOpacity = isActive ? 1.0 : (0.45 / distanceFromActive).clamp(0.12, 0.45);

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
                fontSize: isActive ? 22.0 : 18.0,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: Colors.white,
                height: 1.4,
                shadows: isActive
                    ? [
                        Shadow(
                          color: colors.primary.withValues(alpha: 0.5),
                          blurRadius: 10.0,
                        ),
                      ]
                    : null,
              ),
              textAlign: TextAlign.center,
            );

            if (blurValue > 0.05) {
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
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(left: isActive ? 10.0 : 0.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        width: isActive ? 4.0 : 0.0,
                        height: isActive ? 20.0 : 0.0,
                        margin: EdgeInsets.only(right: isActive ? 10.0 : 0.0),
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
                        const SizedBox(width: 12.0),
                        Text(
                          timestampText!,
                          style: TextStyle(
                            fontSize: 11.0,
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

class _WindowsLyricsTab extends ConsumerStatefulWidget {
  const _WindowsLyricsTab({super.key});

  @override
  ConsumerState<_WindowsLyricsTab> createState() => _WindowsLyricsTabState();
}

class _WindowsLyricsTabState extends ConsumerState<_WindowsLyricsTab> {
  final ScrollController _scrollController = ScrollController();
  bool _isUserScrolling = false;
  Timer? _userScrollTimer;
  int _lastActiveIndex = -1;
  String? _lastSongId;
  List<GlobalKey> _lineKeys = [];

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
    final typography = context.daTypography;
    final currentSong = ref.watch(currentSongProvider);
    final lyricsState = ref.watch(lyricsControllerProvider);
    final playbackPosition = ref.watch(playbackControllerProvider).position;

    if (currentSong != null && currentSong.id != _lastSongId) {
      _lastSongId = currentSong.id;
      _lastActiveIndex = -1;
      _isUserScrolling = false;
      _userScrollTimer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }

    if (currentSong == null) {
      return Center(
        child: Text(
          'No Song Playing',
          style: typography.body.copyWith(color: Colors.white30),
        ),
      );
    }

    int activeIndex = -1;
    List<Duration> timestamps = [];
    List<String> lines = [];

    if (lyricsState.syncedLyrics != null && lyricsState.syncedLyrics!.isNotEmpty) {
      timestamps = lyricsState.syncedLyrics!.keys.toList()..sort();
      lines = timestamps.map((t) => lyricsState.syncedLyrics![t]!).toList();
      for (int i = 0; i < timestamps.length; i++) {
        if (timestamps[i] <= playbackPosition) {
          activeIndex = i;
        } else {
          break;
        }
      }
    } else if (lyricsState.plainLyrics.isNotEmpty) {
      lines = lyricsState.plainLyrics.split('\n');
    }

    if (lines.length != _lineKeys.length) {
      _lineKeys = List.generate(lines.length, (index) => GlobalKey());
    }

    if (activeIndex != _lastActiveIndex && activeIndex != -1) {
      _lastActiveIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLine(activeIndex);
      });
    }

    Widget innerContent;
    if (lyricsState.isLoading || lyricsState.songId != currentSong.id) {
      innerContent = const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (lyricsState.isInstrumental) {
      innerContent = Center(
        key: const ValueKey('instrumental'),
        child: Text(
          'Instrumental Track',
          style: typography.title.copyWith(color: Colors.white70),
        ),
      );
    } else if (lines.isEmpty || lines.contains('Lyrics unavailable.')) {
      innerContent = const Center(
        key: ValueKey('unavailable'),
        child: Text(
          'Lyrics Unavailable',
          style: TextStyle(color: Colors.white30, fontSize: 16.0),
        ),
      );
    } else {
      innerContent = Column(
        key: const ValueKey('content'),
        mainAxisSize: MainAxisSize.min,
        children: List.generate(lines.length, (index) {
          final isActive = index == activeIndex;
          return _TabLyricLineWidget(
            key: _lineKeys[index],
            text: lines[index],
            isActive: isActive,
            index: index,
            activeIndex: activeIndex,
            colors: colors,
            timestampText: (_isUserScrolling && timestamps.isNotEmpty)
                ? _formatTimestamp(timestamps[index])
                : null,
            onTap: () {
              if (timestamps.isNotEmpty) {
                ref.read(playbackControllerProvider).seek(timestamps[index]);
                setState(() {
                  _isUserScrolling = false;
                });
              }
            },
          );
        }),
      );
    }

    final height = MediaQuery.of(context).size.height;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: DeviceMemoryManager.instance.getRecommendedBlurSigma(16.0),
          sigmaY: DeviceMemoryManager.instance.getRecommendedBlurSigma(16.0),
        ),
        child: ShaderMask(
          shaderCallback: (rect) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.15, 0.85, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
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
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    vertical: height / 2 - 40.0,
                    horizontal: 16.0,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: ValueKey<String>('${_lastSongId}_${lyricsState.isLoading}'),
                      child: innerContent,
                    ),
                  ),
                ),
              ),
              if (_isUserScrolling && timestamps.isNotEmpty)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton.small(
                    backgroundColor: colors.primary,
                    onPressed: () {
                      setState(() {
                        _isUserScrolling = false;
                      });
                      if (activeIndex != -1) {
                        _scrollToActiveLine(activeIndex);
                      }
                    },
                    child: const Icon(Icons.sync, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowsQueueTab extends ConsumerWidget {
  const _WindowsQueueTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final controller = ref.watch(playbackControllerProvider);
    final queue = controller.currentQueue;
    final currentIndex = controller.currentIndex;

    if (queue.isEmpty) {
      return const Center(
        child: Text(
          'Playback Queue is Empty',
          style: TextStyle(color: Colors.white30, fontSize: 16.0),
        ),
      );
    }

    return ReorderableListView.builder(
      physics: const BouncingScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorder: (oldIdx, newIdx) {
        HapticFeedback.mediumImpact();
        final queueList = List<Song>.from(queue);
        final song = queueList.removeAt(oldIdx);
        if (newIdx > oldIdx) newIdx--;
        queueList.insert(newIdx, song);
        final newCurrentIndex = (currentIndex == oldIdx)
            ? newIdx
            : ((currentIndex > oldIdx && currentIndex <= newIdx)
                ? currentIndex - 1
                : ((currentIndex < oldIdx && currentIndex >= newIdx) ? currentIndex + 1 : currentIndex));
        controller.reorderQueue(queueList, newCurrentIndex);
      },
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        HapticFeedback.mediumImpact();
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final animValue = Curves.easeInOut.transform(animation.value);
            final elevation = 0.0 + (8.0 - 0.0) * animValue;
            final scale = 1.0 + (1.02 - 1.0) * animValue;
            return Transform.scale(
              scale: scale,
              child: Material(
                elevation: elevation,
                color: Colors.transparent,
                shadowColor: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12.0),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final song = queue[index];
        final isPlaying = index == currentIndex;

        return Container(
          key: ValueKey(song.id + '_' + index.toString()),
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          decoration: BoxDecoration(
            color: isPlaying ? colors.primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12.0),
            border: isPlaying ? Border.all(color: colors.primary.withOpacity(0.3)) : null,
          ),
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Icon(
                      Icons.drag_handle,
                      color: Colors.white.withOpacity(0.3),
                      size: 20.0,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: DAImage(
                    url: song.artworkUrl,
                    width: 44.0,
                    height: 44.0,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
            title: Text(
              song.title,
              style: typography.body.copyWith(
                color: isPlaying ? colors.primary : Colors.white,
                fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              song.artist,
              style: typography.caption.copyWith(
                color: isPlaying ? colors.primary.withOpacity(0.7) : Colors.white30,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: isPlaying
                ? Icon(Icons.volume_up, color: colors.primary, size: 20.0)
                : null,
            onTap: () {
              ref.read(playbackControllerProvider).skipToQueueIndex(index);
            },
          ),
        );
      },
    );
  }
}

class _ImmersiveStylePlayer extends ConsumerStatefulWidget {
  const _ImmersiveStylePlayer();

  @override
  ConsumerState<_ImmersiveStylePlayer> createState() => _ImmersiveStylePlayerState();
}

class _ImmersiveStylePlayerState extends ConsumerState<_ImmersiveStylePlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
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
    final colors = context.daColors;
    final typography = context.daTypography;
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(playbackControllerProvider.select((c) => c.status == PlaybackStatus.playing));
    final isLiked = currentSong != null && ref.watch(libraryManagerProvider).isSongLiked(currentSong.id);

    final artworkUrl = currentSong?.artworkUrl;
    final codec = _getCodec(currentSong);

    return ImmersiveBackground(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.58,
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
                    child: DAImage(
                      url: artworkUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(color: colors.surfaceCard),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.gradientStart.withValues(alpha: 0.0),
                            colors.gradientStart.withValues(alpha: 0.35),
                            colors.gradientMiddle.withValues(alpha: 0.75),
                            colors.gradientMiddle,
                          ],
                          stops: const [0.0, 0.45, 0.75, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DATokens.spacingLarge,
                    vertical: DATokens.spacingMedium,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28.0),
                            onPressed: () => ref.read(immersiveModeProvider.notifier).state = false,
                          ),
                        ],
                      ),
                      const Spacer(flex: 4),
                      Center(
                        child: SwipeableArtwork(
                          onSwipeLeft: () => ref.read(playbackControllerProvider).next(),
                          onSwipeRight: () => ref.read(playbackControllerProvider).previous(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentSong?.title ?? 'No Track Selected',
                                style: typography.title.copyWith(
                                  fontSize: 26.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6.0),
                              Text(
                                currentSong?.artist ?? 'Unknown Artist',
                                style: typography.body.copyWith(
                                  fontSize: 16.0,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12.0),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.waves, size: 12.0, color: Colors.white.withValues(alpha: 0.6)),
                                    const SizedBox(width: 4.0),
                                    Text(
                                      codec.toUpperCase(),
                                      style: typography.caption.copyWith(
                                        fontSize: 10.0,
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 36.0),
                      _VinylPlayerControlsSection(
                        codec: codec,
                      ),
                      const SizedBox(height: 24.0),
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
                      const Spacer(flex: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.queue_music, color: Colors.white60, size: 24.0),
                            onPressed: () {
                              ref.read(immersiveModeProvider.notifier).state = false;
                              context.push('/queue');
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white60, size: 24.0),
                            onPressed: () {
                              ref.read(immersiveModeProvider.notifier).state = false;
                              context.push('/lyrics');
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final timerState = ref.watch(sleepTimerNotifierProvider);
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: timerState.isActive
                                    ? GestureDetector(
                                        key: const ValueKey('active_timer_1'),
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
                                        key: const ValueKey('inactive_timer_1'),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VinylStylePlayer extends ConsumerWidget {
  const _VinylStylePlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(currentSongProvider);
    final colors = context.daColors;
    final typography = context.daTypography;

    final Widget rightControlsSide = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingLarge),
          child: SwipeableArtwork(
            onSwipeLeft: () => ref.read(playbackControllerProvider).next(),
            onSwipeRight: () => ref.read(playbackControllerProvider).previous(),
            child: Column(
              children: [
                Text(
                  currentSong?.title ?? 'No Track Selected',
                  style: typography.title.copyWith(fontSize: 22.0, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4.0),
                Text(
                  currentSong?.artist ?? 'Choose a track to play',
                  style: typography.body.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: DATokens.spacingLarge),
        const _ImmersiveActionRow(),
        const SizedBox(height: DATokens.spacingLarge),
        const ProgressSection(),
        const SizedBox(height: DATokens.spacingLarge),
        const PlaybackControls(),
      ],
    );

    return ImmersiveBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DATokens.spacingLarge,
            vertical: DATokens.spacingMedium,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down, color: colors.textPrimary, size: 28.0),
                    onPressed: () => ref.read(immersiveModeProvider.notifier).state = false,
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 850) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 11,
                            child: const VinylPlayerWidget(),
                          ),
                          const SizedBox(width: DATokens.spacingLarge),
                          Expanded(
                            flex: 10,
                            child: SingleChildScrollView(
                              child: rightControlsSide,
                            ),
                          ),
                        ],
                      );
                    } else {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            const SizedBox(height: DATokens.spacingMedium),
                            const VinylPlayerWidget(),
                            const SizedBox(height: DATokens.spacingMedium),
                            rightControlsSide,
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MinimalStylePlayer extends ConsumerStatefulWidget {
  const _MinimalStylePlayer();

  @override
  ConsumerState<_MinimalStylePlayer> createState() => _MinimalStylePlayerState();
}

class _MinimalStylePlayerState extends ConsumerState<_MinimalStylePlayer> {
  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(playbackControllerProvider.select((c) => c.status == PlaybackStatus.playing));

    return ImmersiveBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DATokens.spacingLarge,
            vertical: DATokens.spacingMedium,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down, color: colors.textPrimary, size: 28.0),
                    onPressed: () => ref.read(immersiveModeProvider.notifier).state = false,
                  ),
                  Builder(
                    builder: (btnContext) => IconButton(
                      icon: Icon(Icons.more_vert, color: colors.textPrimary, size: 24.0),
                      tooltip: 'More options',
                      onPressed: currentSong != null
                          ? () => showSongOptionsMenu(btnContext, ref, currentSong)
                          : null,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (currentSong?.artworkUrl != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20.0),
                    child: DAImage(
                      url: currentSong?.artworkUrl,
                      width: 240.0,
                      height: 240.0,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              const SizedBox(height: 40.0),
              SwipeableArtwork(
                onSwipeLeft: () => ref.read(playbackControllerProvider).next(),
                onSwipeRight: () => ref.read(playbackControllerProvider).previous(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentSong?.title ?? 'No Track Selected',
                      style: typography.title.copyWith(fontSize: 20.0, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      currentSong?.artist ?? 'Unknown Artist',
                      style: typography.body.copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40.0),
              const _MinimalPlayerProgressBarSection(),
              const SizedBox(height: 32.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.skip_previous, size: 30.0, color: colors.textPrimary),
                    onPressed: () => ref.read(playbackControllerProvider).previous(),
                  ),
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 64.0,
                      color: colors.primary,
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
                    icon: Icon(Icons.skip_next, size: 30.0, color: colors.textPrimary),
                    onPressed: () => ref.read(playbackControllerProvider).next(),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.queue_music, color: colors.textSecondary, size: 24.0),
                    tooltip: 'Queue',
                    onPressed: () {
                      ref.read(immersiveModeProvider.notifier).state = false;
                      context.push('/queue');
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.chat_bubble_outline, color: colors.textSecondary, size: 24.0),
                    tooltip: 'Lyrics',
                    onPressed: () {
                      ref.read(immersiveModeProvider.notifier).state = false;
                      context.push('/lyrics');
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final timerState = ref.watch(sleepTimerNotifierProvider);
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: timerState.isActive
                            ? GestureDetector(
                                key: const ValueKey('active_timer_2'),
                                onTap: () => showSleepTimerDialog(context, ref),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceCard,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Text(
                                    timerState.formattedRemaining,
                                    style: TextStyle(color: colors.textPrimary, fontSize: 12.0, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              )
                            : IconButton(
                                key: const ValueKey('inactive_timer_2'),
                                icon: Icon(Icons.dark_mode_outlined, color: colors.textSecondary, size: 24.0),
                                tooltip: 'Sleep timer',
                                onPressed: () => showSleepTimerDialog(context, ref),
                              ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImmersiveActionRow extends ConsumerWidget {
  const _ImmersiveActionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final currentSong = ref.watch(currentSongProvider);
    final libraryManager = ref.watch(libraryManagerProvider);
    final isLiked = currentSong != null && libraryManager.isSongLiked(currentSong.id);

    return Container(
      constraints: const BoxConstraints(maxWidth: 480.0),
      padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingLarge),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.queue_music_outlined),
            color: colors.textSecondary,
            iconSize: 24.0,
            tooltip: 'Queue',
            onPressed: () {
              ref.read(immersiveModeProvider.notifier).state = false;
              context.push('/queue');
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            color: colors.textSecondary,
            iconSize: 24.0,
            tooltip: 'Lyrics',
            onPressed: () {
              ref.read(immersiveModeProvider.notifier).state = false;
              context.push('/lyrics');
            },
          ),
          const _AudioVisualizer(),
          IconButton(
            icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border),
            color: isLiked ? Colors.redAccent : colors.textSecondary,
            iconSize: 24.0,
            tooltip: isLiked ? 'Remove from Favorites' : 'Add to Favorites',
            onPressed: currentSong != null
                ? () => ref.read(libraryManagerProvider.notifier).toggleLikeSong(currentSong)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_outlined),
            color: colors.textSecondary,
            iconSize: 24.0,
            tooltip: 'Options',
            onPressed: currentSong != null
                ? () => showSongOptionsMenu(context, ref, currentSong)
                : null,
          ),
        ],
      ),
    );
  }
}

class _AudioVisualizer extends ConsumerStatefulWidget {
  const _AudioVisualizer();

  @override
  ConsumerState<_AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends ConsumerState<_AudioVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final int _barCount = 11;
  late final List<double> _currentHeights;
  late final List<double> _targetHeights;
  final Random _random = Random();
  int _tickCount = 0;

  @override
  void initState() {
    super.initState();
    _currentHeights = List.filled(_barCount, 3.0);
    _targetHeights = List.filled(_barCount, 3.0);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    _controller.repeat();
  }

  void _onTick() {
    final playbackState = ref.read(playbackStateProvider);
    final isPlaying = playbackState.status == PlaybackStatus.playing;

    _tickCount++;

    if (isPlaying && _tickCount % 10 == 0) {
      for (int i = 0; i < _barCount; i++) {
        _targetHeights[i] = 3.0 + _random.nextDouble() * 15.0;
      }
    } else if (!isPlaying) {
      for (int i = 0; i < _barCount; i++) {
        _targetHeights[i] = 3.0;
      }
    }

    setState(() {
      for (int i = 0; i < _barCount; i++) {
        _currentHeights[i] = _currentHeights[i] + (_targetHeights[i] - _currentHeights[i]) * 0.12;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;

    return Container(
      height: 36.0,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (index) {
          return Container(
            width: 3.0,
            height: _currentHeights[index],
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }
}

class SubtleAmbientBlobs extends StatefulWidget {
  final Color primaryColor;
  final Color accentColor;

  const SubtleAmbientBlobs({
    super.key,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  State<SubtleAmbientBlobs> createState() => _SubtleAmbientBlobsState();
}

class _SubtleAmbientBlobsState extends State<SubtleAmbientBlobs> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 35),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 1000),
      tween: ColorTween(end: widget.primaryColor),
      builder: (context, primary, _) {
        return TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 1000),
          tween: ColorTween(end: widget.accentColor),
          builder: (context, accent, _) {
            final pColor = primary ?? widget.primaryColor;
            final aColor = accent ?? widget.accentColor;

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                
                final dx1 = sin(t * 2 * pi) * 50.0;
                final dy1 = cos(t * 2 * pi) * 40.0;
                final dx2 = cos(t * 2 * pi + pi) * 60.0;
                final dy2 = sin(t * 2 * pi + pi) * 45.0;

                final baseWidth1 = isLandscape ? size.width * 0.45 : size.width * 0.75;
                final baseWidth2 = isLandscape ? size.width * 0.50 : size.width * 0.85;

                final w1 = baseWidth1 * (1.0 + sin(t * 2 * pi) * 0.08);
                final h1 = baseWidth1 * (1.0 + cos(t * 2 * pi) * 0.08);
                final w2 = baseWidth2 * (1.0 + cos(t * 2 * pi + pi) * 0.08);
                final h2 = baseWidth2 * (1.0 + sin(t * 2 * pi + pi) * 0.08);

                final left1 = isLandscape ? size.width * 0.05 + dx1 : size.width * -0.15 + dx1;
                final top1 = isLandscape ? size.height * 0.05 + dy1 : size.height * -0.05 + dy1;

                final right2 = isLandscape ? size.width * 0.05 + dx2 : size.width * -0.2 + dx2;
                final bottom2 = isLandscape ? size.height * 0.05 + dy2 : size.height * -0.1 + dy2;

                return Stack(
                  children: [
                    Positioned(
                      left: left1,
                      top: top1,
                      width: w1,
                      height: h1,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              pColor.withValues(alpha: 0.15),
                              pColor.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: right2,
                      bottom: bottom2,
                      width: w2,
                      height: h2,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              aColor.withValues(alpha: 0.12),
                              aColor.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class SwipeableArtwork extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;

  const SwipeableArtwork({
    super.key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  @override
  ConsumerState<SwipeableArtwork> createState() => _SwipeableArtworkState();
}

class _SwipeableArtworkState extends ConsumerState<SwipeableArtwork> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _curveAnimation;
  final ValueNotifier<Offset> _offsetNotifier = ValueNotifier(Offset.zero);
  
  double _animStartX = 0.0;
  double _animEndX = 0.0;
  bool _isAnimating = false;
  String? _lastSongId;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
    );
    _curveAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.addListener(() {
      _offsetNotifier.value = Offset(
        _animStartX + (_animEndX - _animStartX) * _curveAnimation.value,
        0.0,
      );
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isAnimating) return;
    _offsetNotifier.value = Offset(
      _offsetNotifier.value.dx + details.delta.dx,
      0.0,
    );
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isAnimating) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth * 0.22;
    final currentX = _offsetNotifier.value.dx;

    if (currentX.abs() > threshold) {
      _isAnimating = true;
      _animStartX = currentX;
      _animEndX = currentX > 0 ? screenWidth : -screenWidth;
      
      _animController.duration = const Duration(milliseconds: 220);
      _animController.forward(from: 0.0).then((_) {
        if (currentX > 0) {
          widget.onSwipeRight?.call();
        } else {
          widget.onSwipeLeft?.call();
        }
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _isAnimating = false;
          }
        });
      });
    } else {
      _isAnimating = true;
      _animStartX = currentX;
      _animEndX = 0.0;
      
      _animController.duration = const Duration(milliseconds: 250);
      _animController.forward(from: 0.0).then((_) {
        _isAnimating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    if (!isAndroid) {
      return widget.child;
    }

    final currentSong = ref.watch(currentSongProvider);

    if (currentSong != null && currentSong.id != _lastSongId) {
      final prevSongId = _lastSongId;
      _lastSongId = currentSong.id;

      if (prevSongId != null) {
        bool slideFromRight = true;
        if (_offsetNotifier.value.dx != 0.0) {
          slideFromRight = _offsetNotifier.value.dx < 0;
        }

        _animStartX = slideFromRight ? MediaQuery.of(context).size.width : -MediaQuery.of(context).size.width;
        _animEndX = 0.0;
        _isAnimating = true;
        
        _animController.duration = const Duration(milliseconds: 350);
        _animController.forward(from: 0.0).then((_) {
          _isAnimating = false;
        });
      }
    }

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      behavior: HitTestBehavior.opaque,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _offsetNotifier,
        builder: (context, offset, child) {
          return Transform.translate(
            offset: offset,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _WindowsPlayerProgressBar extends ConsumerStatefulWidget {
  final String codec;
  final bool isCompactHeight;

  const _WindowsPlayerProgressBar({
    required this.codec,
    required this.isCompactHeight,
  });

  @override
  ConsumerState<_WindowsPlayerProgressBar> createState() => _WindowsPlayerProgressBarState();
}

class _WindowsPlayerProgressBarState extends ConsumerState<_WindowsPlayerProgressBar> {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4.0,
                  trackShape: const _RoundedTrackShape(),
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: Colors.white.withOpacity(0.15),
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
          ],
        ),
        const SizedBox(height: 8.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(displayPosition),
              style: typography.caption.copyWith(color: Colors.white54, fontSize: 12.0),
            ),
            if (!widget.isCompactHeight)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.waves, size: 12.0, color: Colors.white.withOpacity(0.6)),
                    const SizedBox(width: 4.0),
                    Text(
                      widget.codec.toUpperCase(),
                      style: typography.caption.copyWith(
                        fontSize: 10.0,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              _formatDuration(duration),
              style: typography.caption.copyWith(color: Colors.white54, fontSize: 12.0),
            ),
          ],
        ),
      ],
    );
  }
}

class _VinylPlayerControlsSection extends ConsumerStatefulWidget {
  final String codec;

  const _VinylPlayerControlsSection({
    required this.codec,
  });

  @override
  ConsumerState<_VinylPlayerControlsSection> createState() => _VinylPlayerControlsSectionState();
}

class _VinylPlayerControlsSectionState extends ConsumerState<_VinylPlayerControlsSection> {
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
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.redAccent : Colors.white70,
                size: 22.0,
              ),
              onPressed: () => ref.read(libraryManagerProvider.notifier).toggleLikeSong(currentSong),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4.0,
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
        const SizedBox(height: 6.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(displayPosition),
                style: typography.caption.copyWith(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.0),
              ),
              Text(
                _formatDuration(duration),
                style: typography.caption.copyWith(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.0),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MinimalPlayerProgressBarSection extends ConsumerStatefulWidget {
  const _MinimalPlayerProgressBarSection();

  @override
  ConsumerState<_MinimalPlayerProgressBarSection> createState() => _MinimalPlayerProgressBarSectionState();
}

class _MinimalPlayerProgressBarSectionState extends ConsumerState<_MinimalPlayerProgressBarSection> {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.0,
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.border.withValues(alpha: 0.3),
            thumbColor: colors.primary,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
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
        const SizedBox(height: 8.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(displayPosition), style: typography.caption),
              Text(_formatDuration(duration), style: typography.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _Material3Player extends ConsumerStatefulWidget {
  const _Material3Player();

  @override
  ConsumerState<_Material3Player> createState() => _Material3PlayerState();
}

class _Material3PlayerState extends ConsumerState<_Material3Player> {
  int _activeTab = 0;
  double? _dragValue;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentSong = ref.watch(currentSongProvider);
    final controller = ref.watch(playbackControllerProvider);
    final isPlaying = controller.status == PlaybackStatus.playing;
    final isLiked = currentSong != null && ref.watch(libraryManagerProvider).isSongLiked(currentSong.id);
    final artworkUrl = currentSong?.artworkUrl;

    final position = controller.position;
    final duration = currentSong?.duration ?? Duration.zero;
    final double realProgress = (duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final double activeProgress = _dragValue ?? realProgress;

    final displayPosition = _dragValue != null
        ? Duration(milliseconds: (_dragValue! * duration.inMilliseconds).toInt())
        : position;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final double artworkSize = isWide
                ? (constraints.maxHeight * 0.45).clamp(180.0, 320.0)
                : (constraints.maxWidth * 0.65).clamp(200.0, 340.0);

            Widget playerContent = SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28.0),
                        onPressed: () => ref.read(immersiveModeProvider.notifier).state = false,
                      ),
                      const Spacer(),
                      Text(
                        'PLAYING FROM QUEUE',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                        color: isLiked ? Colors.redAccent : colorScheme.onSurfaceVariant,
                        onPressed: currentSong != null
                            ? () => ref.read(libraryManagerProvider.notifier).toggleLikeSong(currentSong)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24.0),
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: artworkSize + 32.0,
                          height: artworkSize + 32.0,
                          child: CircularProgressIndicator(
                            value: activeProgress,
                            strokeWidth: 6.0,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            color: colorScheme.primary,
                          ),
                        ),
                        Container(
                          width: artworkSize,
                          height: artworkSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 20.0,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: DAImage(
                              url: artworkUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28.0),
                  Text(
                    currentSong?.title ?? 'No Song Selected',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    currentSong?.artist ?? 'Unknown Artist',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20.0),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4.0,
                      activeTrackColor: colorScheme.primary,
                      inactiveTrackColor: colorScheme.surfaceContainerHighest,
                      thumbColor: colorScheme.primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                    ),
                    child: Slider(
                      value: activeProgress,
                      onChanged: (val) {
                        setState(() {
                          _dragValue = val;
                        });
                      },
                      onChangeEnd: (val) {
                        controller.seek(
                          Duration(milliseconds: (val * duration.inMilliseconds).toInt()),
                        );
                        setState(() {
                          _dragValue = null;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(displayPosition), style: theme.textTheme.labelSmall),
                        Text(_formatDuration(duration), style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          ref.watch(shuffleProvider) ? Icons.shuffle_on_outlined : Icons.shuffle_rounded,
                        ),
                        color: ref.watch(shuffleProvider) ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        onPressed: () => controller.toggleShuffle(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, size: 36.0),
                        color: colorScheme.onSurface,
                        onPressed: () => controller.previous(),
                      ),
                      IconButton.filledTonal(
                        iconSize: 42.0,
                        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        onPressed: () {
                          if (isPlaying) {
                            controller.pause();
                          } else {
                            controller.resume();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, size: 36.0),
                        color: colorScheme.onSurface,
                        onPressed: () => controller.next(),
                      ),
                      IconButton(
                        icon: Icon(
                          ref.watch(repeatModeProvider) == RepeatMode.one
                              ? Icons.repeat_one_rounded
                              : (ref.watch(repeatModeProvider) == RepeatMode.all ? Icons.repeat_on_rounded : Icons.repeat_rounded),
                        ),
                        color: ref.watch(repeatModeProvider) != RepeatMode.off ? colorScheme.primary : colorScheme.onSurfaceVariant,
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
                          controller.setRepeatMode(nextMode);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(flex: 1, child: playerContent),
                  Expanded(
                    flex: 1,
                    child: Container(
                      margin: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SegmentedButton<int>(
                                    segments: const [
                                      ButtonSegment(value: 0, label: Text('Lyrics')),
                                      ButtonSegment(value: 1, label: Text('Queue')),
                                    ],
                                    selected: {_activeTab},
                                    onSelectionChanged: (val) {
                                      setState(() {
                                        _activeTab = val.first;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _activeTab == 0
                                ? const _WindowsLyricsTab(key: ValueKey('lyrics'))
                                : const _WindowsQueueTab(key: ValueKey('queue')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return playerContent;
          },
        ),
      ),
    );
  }
}
