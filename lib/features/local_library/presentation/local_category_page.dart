import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/extensions/context_extensions.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/models/music_models.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../shared/widgets/da_card.dart';
import '../../../shared/widgets/da_image.dart';
import '../../../shared/utils/song_options.dart';
import '../data/local_library_repository.dart';
import '../../../core/services/playback_controller.dart';
import '../../../shared/animations/motion_system.dart';

enum LocalCategory {
  songs,
  albums,
  artists,
  genres,
  folders,
  recentlyAdded,
  hiRes
}

class LocalCategoryPage extends ConsumerWidget {
  final LocalCategory category;
  final String? filterValue; // e.g. Artist name or Album name when drilling down

  const LocalCategoryPage({
    super.key,
    required this.category,
    this.filterValue,
  });

  String _getTitle() {
    if (filterValue != null) return filterValue!;
    switch (category) {
      case LocalCategory.songs:
        return 'Local Songs';
      case LocalCategory.albums:
        return 'Local Albums';
      case LocalCategory.artists:
        return 'Local Artists';
      case LocalCategory.genres:
        return 'Local Genres';
      case LocalCategory.folders:
        return 'Local Folders';
      case LocalCategory.recentlyAdded:
        return 'Recently Added';
      case LocalCategory.hiRes:
        return 'Hi-Res Audio';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;

    final repoState = ref.watch(localLibraryRepositoryProvider);
    final repoNotifier = ref.read(localLibraryRepositoryProvider.notifier);

    List<Song> songs = [];
    List<Album> albums = [];
    List<Artist> artists = [];
    List<String> folders = [];

    // Filter logic
    if (category == LocalCategory.songs) {
      songs = repoState.songs;
    } else if (category == LocalCategory.albums) {
      if (filterValue != null) {
        songs = repoState.songs.where((s) => s.album == filterValue).toList();
      } else {
        albums = repoNotifier.getAlbums();
      }
    } else if (category == LocalCategory.artists) {
      if (filterValue != null) {
        songs = repoState.songs.where((s) => s.artist == filterValue).toList();
      } else {
        artists = repoNotifier.getArtists();
      }
    } else if (category == LocalCategory.genres) {
      if (filterValue != null) {
        songs = repoState.songs; // fallback
      }
    } else if (category == LocalCategory.folders) {
      if (filterValue != null) {
        songs = repoState.songs.where((s) => s.id.startsWith(filterValue!)).toList();
      } else {
        folders = repoState.folders;
      }
    } else if (category == LocalCategory.recentlyAdded) {
      songs = repoNotifier.getRecentlyAdded();
    } else if (category == LocalCategory.hiRes) {
      songs = repoNotifier.getHiResSongs();
    }

    final hasSubList = (filterValue != null) || 
        category == LocalCategory.songs || 
        category == LocalCategory.recentlyAdded || 
        category == LocalCategory.hiRes;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _getTitle(),
          style: typography.title.copyWith(fontSize: 20.0, fontWeight: FontWeight.bold),
        ),
      ),
      body: hasSubList
          ? _buildSongsList(context, ref, songs, repoState.hiResInfoMap)
          : _buildCategoryGrid(context, ref, albums, artists, folders),
    );
  }

  Widget _buildSongsList(
    BuildContext context, 
    WidgetRef ref, 
    List<Song> songs, 
    Map<String, Map<String, dynamic>> hiResMap,
  ) {
    final colors = context.daColors;
    final typography = context.daTypography;

    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: DATokens.spacingMedium),
            Text(
              'No local tracks found',
              style: typography.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingLarge, vertical: DATokens.spacingSmall),
      physics: const BouncingScrollPhysics(),
      itemCount: songs.length,
      itemBuilder: (context, idx) {
        final song = songs[idx];
        final info = hiResMap[song.id];
        final isLossless = info != null && (info['isLossless'] as bool? ?? false);
        final isHiRes = info != null && (info['isHiRes'] as bool? ?? false);
        final sampleRate = info != null ? (info['sampleRate'] as int? ?? 44100) : 44100;
        final bitDepth = info != null ? (info['bitDepth'] as int? ?? 16) : 16;
        final codec = info != null ? (info['codec'] as String? ?? 'MP3') : 'MP3';

        return Padding(
          padding: const EdgeInsets.only(bottom: DATokens.spacingSmall),
          child: DACard(
            child: ListTile(
              onTap: () {
                ref.read(playbackControllerProvider).setQueue(songs, startIndex: idx, autoPlay: true, queueMode: QueueMode.playlist);
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: DATokens.spacingMedium, vertical: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: DAImage(
                  url: song.artworkUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(
                song.title,
                style: typography.title.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${song.artist} • ${song.album}',
                    style: typography.body.copyWith(color: colors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (isHiRes) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.withOpacity(0.5), width: 0.5),
                          ),
                          child: const Text(
                            'HI-RES',
                            style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ] else if (isLossless) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colors.primary.withOpacity(0.5), width: 0.5),
                          ),
                          child: Text(
                            'LOSSLESS',
                            style: TextStyle(color: colors.primary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '$codec • $bitDepth-bit / ${(sampleRate / 1000).toStringAsFixed(1)} kHz',
                        style: typography.caption.copyWith(color: colors.textSecondary.withOpacity(0.6), fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDuration(song.duration),
                    style: typography.caption.copyWith(color: colors.textSecondary),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert, color: colors.textSecondary),
                    onPressed: () => showSongOptionsMenu(context, ref, song),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryGrid(
    BuildContext context, 
    WidgetRef ref, 
    List<Album> albums, 
    List<Artist> artists, 
    List<String> folders,
  ) {
    final colors = context.daColors;
    final typography = context.daTypography;

    if (category == LocalCategory.albums && albums.isEmpty ||
        category == LocalCategory.artists && artists.isEmpty ||
        category == LocalCategory.folders && folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: DATokens.spacingMedium),
            Text(
              'No items found',
              style: typography.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (category == LocalCategory.albums) {
      return GridView.builder(
        padding: const EdgeInsets.all(DATokens.spacingLarge),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: DATokens.spacingMedium,
          mainAxisSpacing: DATokens.spacingMedium,
          childAspectRatio: 0.78,
        ),
        itemCount: albums.length,
        itemBuilder: (context, idx) {
          final album = albums[idx];
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                DAMotion.createPageRoute(
                  builder: (context) => LocalCategoryPage(
                    category: LocalCategory.albums,
                    filterValue: album.name,
                  ),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: DAImage(
                      url: album.artworkUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: DATokens.spacingSmall),
                Text(
                  album.name,
                  style: typography.title.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  album.artist,
                  style: typography.body.copyWith(color: colors.textSecondary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      );
    } else if (category == LocalCategory.artists) {
      return GridView.builder(
        padding: const EdgeInsets.all(DATokens.spacingLarge),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: DATokens.spacingMedium,
          mainAxisSpacing: DATokens.spacingMedium,
          childAspectRatio: 0.85,
        ),
        itemCount: artists.length,
        itemBuilder: (context, idx) {
          final artist = artists[idx];
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                DAMotion.createPageRoute(
                  builder: (context) => LocalCategoryPage(
                    category: LocalCategory.artists,
                    filterValue: artist.name,
                  ),
                ),
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipOval(
                      child: DAImage(
                        url: artist.artworkUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DATokens.spacingSmall),
                Text(
                  artist.name,
                  style: typography.title.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      );
    } else {
      // Folders
      return ListView.builder(
        padding: const EdgeInsets.all(DATokens.spacingLarge),
        physics: const BouncingScrollPhysics(),
        itemCount: folders.length,
        itemBuilder: (context, idx) {
          final folder = folders[idx];
          return Padding(
            padding: const EdgeInsets.only(bottom: DATokens.spacingSmall),
            child: DACard(
              child: ListTile(
                leading: const Icon(Icons.folder_outlined, color: Colors.white70),
                title: Text(
                  p.basename(folder),
                  style: typography.title.copyWith(fontSize: 14),
                ),
                subtitle: Text(
                  folder,
                  style: typography.body.copyWith(color: colors.textSecondary, fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20.0),
                onTap: () {
                  Navigator.push(
                    context,
                    DAMotion.createPageRoute(
                      builder: (context) => LocalCategoryPage(
                        category: LocalCategory.folders,
                        filterValue: folder,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
