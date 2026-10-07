import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/providers/backend_providers.dart';
import '../../../../shared/providers/player_providers.dart';
import '../../../../domain/entities/album.dart';
import '../../../../domain/entities/song.dart';
import '../../../../shared/models/music_models.dart' as shared;
import '../../../../shared/utils/artist_navigation.dart';
import '../../../../shared/utils/song_options.dart';
import '../../../../shared/widgets/da_image.dart';
import '../../../../core/services/playback_controller.dart';

final albumDetailsProvider = FutureProvider.family<({Album album, List<Song> songs}), String>((ref, albumId) async {
  final albumRepo = ref.watch(albumRepositoryProvider);
  final sourceManager = ref.watch(sourceManagerProvider);

  final album = await albumRepo.getAlbumById(albumId);

  List<Song> songs = [];
  try {
    final playlist = await sourceManager.getPlaylist(albumId);
    songs = await Future.wait(
      playlist.songIds.map((id) => sourceManager.getSong(id)),
    );
  } catch (e) {
    songs = [];
  }

  return (album: album, songs: songs);
});

class AlbumPage extends ConsumerWidget {
  final String albumId;

  const AlbumPage({
    super.key,
    required this.albumId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final detailsAsync = ref.watch(albumDetailsProvider(albumId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Album Details',
          style: typography.title.copyWith(fontSize: 20.0),
        ),
      ),
      body: detailsAsync.when(
        data: (data) => _buildContent(context, ref, data.album, data.songs),
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (err, stack) => Center(
          child: Text(
            'Failed to load album details.\n$err',
            style: typography.body.copyWith(color: colors.accent),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Album album, List<Song> songs) {
    final colors = context.daColors;
    final typography = context.daTypography;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 520.0;
              final double artSize = isCompact ? 160.0 : 180.0;

              final actionButtons = songs.isNotEmpty
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: isCompact ? MainAxisAlignment.center : MainAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              final modelSongs = songs.map((s) => shared.Song(
                                id: s.id,
                                title: s.title,
                                artist: s.artistId == 'Unknown Artist' ? album.artistId : s.artistId,
                                album: album.title,
                                duration: s.duration.value,
                                artworkUrl: s.artwork.url,
                                source: s.sourceId,
                                lyrics: null,
                              )).toList();
                              ref.read(playbackControllerProvider).setQueue(modelSongs, autoPlay: true, queueMode: QueueMode.album);
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play Album'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.textPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: DATokens.spacingLarge,
                                vertical: DATokens.spacingMedium,
                              ),
                            ),
                          ),
                          const SizedBox(width: DATokens.spacingSmall),
                          OutlinedButton.icon(
                            onPressed: () {
                              final modelSongs = songs.map((s) => shared.Song(
                                id: s.id,
                                title: s.title,
                                artist: s.artistId == 'Unknown Artist' ? album.artistId : s.artistId,
                                album: album.title,
                                duration: s.duration.value,
                                artworkUrl: s.artwork.url,
                                source: s.sourceId,
                                lyrics: null,
                              )).toList();
                              ref.read(playbackControllerProvider).shufflePlaylist(modelSongs);
                            },
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Shuffle'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textPrimary,
                              side: BorderSide(color: colors.border),
                              padding: const EdgeInsets.symmetric(
                                horizontal: DATokens.spacingLarge,
                                vertical: DATokens.spacingMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink();

              if (isCompact) {
                return Padding(
                  padding: const EdgeInsets.all(DATokens.spacingLarge),
                  child: Column(
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12.0),
                          child: DAImage(
                            url: album.cover.url,
                            width: artSize,
                            height: artSize,
                            fit: BoxFit.cover,
                            placeholder: Container(
                              width: artSize,
                              height: artSize,
                              color: colors.surfaceHover,
                              child: Icon(Icons.music_note, size: 64.0, color: colors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: DATokens.spacingMedium),
                      Text(
                        album.title,
                        style: typography.title.copyWith(fontSize: 22.0),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: DATokens.spacingSmall),
                      GestureDetector(
                        onTap: () => navigateToArtistByName(context, ref, album.artistId),
                        child: Text(
                          album.artistId,
                          style: typography.body.copyWith(
                            color: colors.primary,
                            fontSize: 16.0,
                            decoration: TextDecoration.underline,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: DATokens.spacingTiny),
                      Text(
                        'Album • ${album.year} • ${album.trackCount} Songs',
                        style: typography.body.copyWith(color: colors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: DATokens.spacingMedium),
                      actionButtons,
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(DATokens.spacingLarge),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12.0),
                      child: DAImage(
                        url: album.cover.url,
                        width: artSize,
                        height: artSize,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          width: artSize,
                          height: artSize,
                          color: colors.surfaceHover,
                          child: Icon(Icons.music_note, size: 64.0, color: colors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: DATokens.spacingLarge),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.title,
                            style: typography.title.copyWith(fontSize: 28.0),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: DATokens.spacingSmall),
                          GestureDetector(
                            onTap: () => navigateToArtistByName(context, ref, album.artistId),
                            child: Text(
                              album.artistId,
                              style: typography.body.copyWith(
                                color: colors.primary,
                                fontSize: 18.0,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(height: DATokens.spacingTiny),
                          Text(
                            'Album • ${album.year} • ${album.trackCount} Songs',
                            style: typography.body.copyWith(color: colors.textSecondary),
                          ),
                          const SizedBox(height: DATokens.spacingLarge),
                          actionButtons,
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingLarge),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = songs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: DATokens.spacingSmall),
                  child: ListTile(
                    onTap: () {
                      final modelSongs = songs.map((s) => shared.Song(
                        id: s.id,
                        title: s.title,
                        artist: s.artistId == 'Unknown Artist' ? album.artistId : s.artistId,
                        album: album.title,
                        duration: s.duration.value,
                        artworkUrl: s.artwork.url,
                        source: s.sourceId,
                        lyrics: null,
                      )).toList();
                      ref.read(playbackControllerProvider).setQueue(modelSongs, startIndex: index, autoPlay: true, queueMode: QueueMode.album);
                    },
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: DAImage(
                        url: song.artwork.url,
                        width: 48.0,
                        height: 48.0,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          width: 48.0,
                          height: 48.0,
                          color: colors.surfaceHover,
                          child: Icon(Icons.music_note, color: colors.textSecondary),
                        ),
                      ),
                    ),
                    title: Text(
                      song.title,
                      style: typography.body.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      song.artistId == 'Unknown Artist' ? album.artistId : song.artistId,
                      style: typography.body.copyWith(color: colors.textSecondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatDuration(song.duration.value),
                          style: typography.body.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(width: DATokens.spacingSmall),
                        IconButton(
                          icon: Icon(Icons.more_vert, color: colors.textSecondary),
                          onPressed: () {
                            final modelSong = shared.Song(
                              id: song.id,
                              title: song.title,
                              artist: song.artistId == 'Unknown Artist' ? album.artistId : song.artistId,
                              album: album.title,
                              duration: song.duration.value,
                              artworkUrl: song.artwork.url,
                              source: song.sourceId,
                              lyrics: null,
                            );
                            showSongOptionsMenu(context, ref, modelSong);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: songs.length,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString();
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
