import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../shared/providers/player_providers.dart';
import 'player_background.dart';
import 'player_header.dart';
import 'vinyl_player_widget.dart';
import 'song_information.dart';
import 'progress_section.dart';
import 'playback_controls.dart';
import 'lyrics_preview.dart';
import 'immersive/immersive_player.dart';
import '../../../../shared/widgets/da_image.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/animations/motion_system.dart';

class PersistentPlayerPanel extends ConsumerWidget {
  const PersistentPlayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImmersive = ref.watch(immersiveModeProvider);
    final duration = ref.scaledDuration(DAMotion.playerDuration);
    final currentSong = ref.watch(currentSongProvider);

    return PlayerBackground(
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        child: isImmersive
            ? const ImmersivePlayer(key: ValueKey('immersive'))
            : LayoutBuilder(
                key: const ValueKey('standard'),
                builder: (context, constraints) {
                  final height = constraints.maxHeight;
                  final isCompact = height < 500.0;
                  final isMedium = height >= 500.0 && height < 680.0;

                  final spacing = isCompact
                      ? DATokens.spacingSmall
                      : (isMedium ? DATokens.spacingMedium : DATokens.spacingLarge);

                  final artworkSize = isCompact
                      ? 100.0
                      : (isMedium ? 160.0 : 260.0);

                  final artworkContainerHeight = isCompact
                      ? 120.0
                      : (isMedium ? 180.0 : 380.0);

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: DATokens.spacingMedium,
                      vertical: isCompact ? DATokens.spacingSmall : DATokens.spacingLarge,
                    ),
                    child: Column(
                      children: [
                        if (!isCompact) ...[
                          const PlayerHeader(),
                          SizedBox(height: spacing),
                        ],
                        _buildArtworkWidget(context, ref, currentSong, artworkSize, artworkContainerHeight),
                        SizedBox(height: spacing),
                        SongInformation(
                          title: currentSong?.title ?? 'No Track Selected',
                          artist: currentSong?.artist ?? 'Choose a track to play',
                          album: currentSong?.album ?? '',
                        ),
                        SizedBox(height: isCompact ? 4.0 : DATokens.spacingMedium),
                        const ProgressSection(),
                        SizedBox(height: isCompact ? 4.0 : DATokens.spacingMedium),
                        const PlaybackControls(),
                        if (!isCompact) ...[
                          SizedBox(height: spacing),
                          const LyricsPreview(),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildArtworkWidget(BuildContext context, WidgetRef ref, dynamic currentSong, double size, double containerHeight) {
    final style = ref.watch(playerStyleProvider);
    final colors = context.daColors;

    switch (style) {
      case PlayerStyle.minimal:
      case PlayerStyle.immersive:
        return SizedBox(
          height: containerHeight,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 15.0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: DAImage(
                  url: currentSong?.artworkUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );
      case PlayerStyle.vinyl:
      default:
        return SizedBox(
          height: containerHeight,
          child: const VinylPlayerWidget(),
        );
    }
  }
}
