import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../shared/providers/library_providers.dart';
import '../../../shared/widgets/da_empty_state.dart';
import '../../../shared/widgets/da_image.dart';
import '../../../core/services/playback_controller.dart';

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;

    final libraryManager = ref.watch(libraryManagerProvider);
    final favorites = libraryManager.likedSongs;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Favorites',
          style: typography.title.copyWith(fontSize: 22.0, fontWeight: FontWeight.bold),
        ),
      ),
      body: favorites.isEmpty
          ? const Center(
              child: DAEmptyState(
                icon: Icons.favorite_border_outlined,
                title: 'No Favorites Yet',
                description: 'Songs you mark as favorite will show here.',
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: DATokens.spacingMedium,
                right: DATokens.spacingMedium,
                top: DATokens.spacingSmall,
                bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingSmall,
              ),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final song = favorites[index];

                return Card(
                  color: colors.surfaceCard.withValues(alpha: 0.1),
                  margin: const EdgeInsets.only(bottom: DATokens.spacingSmall),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                    side: BorderSide(color: colors.border.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    onTap: () {
                      ref.read(playbackControllerProvider).setQueue(
                            favorites,
                            startIndex: index,
                            autoPlay: true,
                            queueMode: QueueMode.playlist,
                          );
                    },
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(DATokens.radiusSmall),
                      child: DAImage(
                        url: song.artworkUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: const Icon(Icons.music_note, color: Colors.white24),
                      ),
                    ),
                    title: Text(
                      song.title,
                      style: typography.title.copyWith(
                        fontSize: 14.0,
                        fontWeight: FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      song.artist,
                      style: typography.caption.copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.redAccent),
                      onPressed: () {
                        ref.read(libraryManagerProvider.notifier).toggleLikeSong(song);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
