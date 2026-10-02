import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/providers/player_providers.dart';
import '../../../../shared/models/playback_state.dart';
import '../../../../shared/animations/interactive_scale.dart';
import '../../../../shared/utils/song_options.dart';
import '../../../../shared/widgets/da_image.dart';
import '../../../../shared/widgets/m3_play_pause_button.dart';
import '../../../../shared/providers/theme_providers.dart';
import '../../../../core/services/device_memory_manager.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final isAmoled = ref.watch(appThemeModeProvider) == AppThemeMode.amoled;

    final currentSong = ref.watch(currentSongProvider);
    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    final isPlaying = ref.watch(playbackControllerProvider.select((c) => c.status == PlaybackStatus.playing));

    return InteractiveScale(
      hoverScale: 1.01,
      pressScale: 0.98,
      onTap: () {
        ref.read(immersiveModeProvider.notifier).state = true;
      },
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            final controller = ref.read(playbackControllerProvider);
            if (details.primaryVelocity! > 0) {
              controller.previous();
            } else if (details.primaryVelocity! < 0) {
              controller.next();
            }
          }
        },
        child: Container(
          height: 64.0,
          margin: const EdgeInsets.symmetric(
            horizontal: DATokens.spacingMedium,
            vertical: DATokens.spacingSmall,
          ),
          decoration: BoxDecoration(
            color: isAmoled ? Colors.black : colors.surfaceCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(DATokens.radiusLarge),
            border: Border.all(
              color: isAmoled ? Colors.white30 : colors.border.withValues(alpha: 0.2),
              width: 1.0,
            ),
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
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingMedium),
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
                          const SizedBox(width: DATokens.spacingMedium),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSong.title,
                                  style: typography.body.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  currentSong.artist,
                                  style: typography.caption.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: colors.surfaceHover,
                              foregroundColor: colors.textPrimary,
                              fixedSize: const Size(34.0, 34.0),
                              padding: EdgeInsets.zero,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(14.0),
                                  bottomLeft: Radius.circular(14.0),
                                  topRight: Radius.circular(4.0),
                                  bottomRight: Radius.circular(4.0),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.skip_previous_rounded, size: 18.0),
                            onPressed: () => ref.read(playbackControllerProvider).previous(),
                          ),
                          const SizedBox(width: 4.0),
                          M3PlayPauseButton(
                            isPlaying: isPlaying,
                            size: 38.0,
                            iconSize: 22.0,
                            backgroundColor: colors.primary,
                            foregroundColor: colors.primary.contrastingColor,
                            onPressed: () {
                              final controller = ref.read(playbackControllerProvider);
                              if (isPlaying) {
                                controller.pause();
                              } else {
                                controller.resume();
                              }
                            },
                          ),
                          const SizedBox(width: 4.0),
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: colors.surfaceHover,
                              foregroundColor: colors.textPrimary,
                              fixedSize: const Size(34.0, 34.0),
                              padding: EdgeInsets.zero,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topRight: Radius.circular(14.0),
                                  bottomRight: Radius.circular(14.0),
                                  topLeft: Radius.circular(4.0),
                                  bottomLeft: Radius.circular(4.0),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.skip_next_rounded, size: 18.0),
                            onPressed: () => ref.read(playbackControllerProvider).next(),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.more_vert,
                              color: colors.textSecondary,
                              size: 24.0,
                            ),
                            onPressed: () {
                              showSongOptionsMenu(context, ref, currentSong);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const _MiniPlayerProgressBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerProgressBar extends ConsumerWidget {
  const _MiniPlayerProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final currentSong = ref.watch(currentSongProvider);
    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    final position = ref.watch(playbackControllerProvider.select((c) => c.position));
    final duration = currentSong.duration;
    final double progress = (duration.inMilliseconds > 0)
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return SizedBox(
      height: 3.0,
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        backgroundColor: colors.border.withValues(alpha: 0.3),
        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
      ),
    );
  }
}
