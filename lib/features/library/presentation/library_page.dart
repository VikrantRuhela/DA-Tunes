import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../shared/providers/library_providers.dart';
import '../../../shared/providers/backend_providers.dart';
import '../../../shared/widgets/da_empty_state.dart';
import '../../../shared/utils/song_options.dart';
import '../../../core/services/download_manager.dart';
import '../../../shared/models/music_models.dart';
import '../../local_library/presentation/local_library_tab.dart';
import '../../../shared/widgets/da_image.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/playback_controller.dart';

final playlistDetailProvider = FutureProvider.family<Playlist, String>((ref, id) async {
  final sourceManager = ref.read(sourceManagerProvider);
  final playlistEntity = await sourceManager.getPlaylist(id);

  final songs = await Future.wait(
    playlistEntity.songIds.map((songId) async {
      final s = await sourceManager.getSong(songId);
      return Song(
        id: s.id,
        title: s.title,
        artist: s.artistId,
        album: s.albumId,
        duration: s.duration.value,
        artworkUrl: s.artwork.url,
        source: s.sourceId,
        lyrics: null,
      );
    }),
  );

  return Playlist(
    id: playlistEntity.id,
    name: playlistEntity.title,
    songs: songs,
  );
});

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String? _selectedPlaylistId;
  int _selectedTab = 0; // 0 = Playlists, 1 = Songs, 2 = Albums, 3 = Artists, 4 = Downloads, 5 = Local Library

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Playlist Name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  ref.read(libraryManagerProvider.notifier).createPlaylist(name);
                  Navigator.pop(context);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    if (_selectedPlaylistId != null) {
      final isRemote = _selectedPlaylistId!.startsWith('PL') || _selectedPlaylistId!.startsWith('VL');
      
      if (!isRemote) {
        final localPlaylists = ref.watch(libraryManagerProvider).playlists;
        final playlistIndex = localPlaylists.indexWhere((p) => p.id == _selectedPlaylistId);
        if (playlistIndex < 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _selectedPlaylistId = null;
            });
          });
          return const SizedBox.shrink();
        }

        final playlist = localPlaylists[playlistIndex];
        return _buildPlaylistDetailsView(
          title: playlist.name,
          songs: playlist.songs,
          isRemote: false,
          colors: colors,
          typography: typography,
        );
      } else {
        // Remote YTM Playlist Detail Loader
        final playlistAsync = ref.watch(playlistDetailProvider(_selectedPlaylistId!));
        return playlistAsync.when(
          loading: () => Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
            body: Center(child: CircularProgressIndicator(color: colors.primary)),
          ),
          error: (err, stack) => Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedPlaylistId = null),
              ),
            ),
            body: Center(
              child: Text(
                'Failed to load playlist: $err',
                style: TextStyle(color: colors.textPrimary),
              ),
            ),
          ),
          data: (playlist) => _buildPlaylistDetailsView(
            title: playlist.name,
            songs: playlist.songs,
            isRemote: true,
            colors: colors,
            typography: typography,
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Library',
          style: typography.title.copyWith(fontSize: 22.0, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedTab == 0)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Create Playlist',
              onPressed: () => _showCreatePlaylistDialog(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingMedium, vertical: DATokens.spacingSmall),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildTabButton('Playlists', 0, colors, typography),
                  const SizedBox(width: DATokens.spacingMedium * 1.5),
                  _buildTabButton('Songs', 1, colors, typography),
                  const SizedBox(width: DATokens.spacingMedium * 1.5),
                  _buildTabButton('Albums', 2, colors, typography),
                  const SizedBox(width: DATokens.spacingMedium * 1.5),
                  _buildTabButton('Artists', 3, colors, typography),
                  const SizedBox(width: DATokens.spacingMedium * 1.5),
                  _buildTabButton('Downloads', 4, colors, typography),
                  const SizedBox(width: DATokens.spacingMedium * 1.5),
                  _buildTabButton('Local Library', 5, colors, typography),
                ],
              ),
            ),
          ),
          const SizedBox(height: DATokens.spacingSmall),
          Expanded(
            child: _buildSelectedTabContent(colors, typography),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedTabContent(dynamic colors, dynamic typography) {
    switch (_selectedTab) {
      case 0:
        final playlistsAsync = ref.watch(unifiedPlaylistsProvider);
        return playlistsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.primary)),
          error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: colors.textPrimary))),
          data: (playlists) {
            DALogger.info('UI Rendering: Rendered ${playlists.length} playlists in library view');
            return _buildPlaylistsTab(playlists, colors, typography);
          },
        );
      case 1:
        final songsAsync = ref.watch(unifiedSongsProvider);
        return songsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.primary)),
          error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: colors.textPrimary))),
          data: (songs) {
            DALogger.info('UI Rendering: Rendered ${songs.length} songs in library view');
            return _buildSongsTab(songs, colors, typography);
          },
        );
      case 2:
        final albumsAsync = ref.watch(unifiedAlbumsProvider);
        return albumsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.primary)),
          error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: colors.textPrimary))),
          data: (albums) {
            DALogger.info('UI Rendering: Rendered ${albums.length} albums in library view');
            return _buildAlbumsTab(albums, colors, typography);
          },
        );
      case 3:
        final artistsAsync = ref.watch(unifiedArtistsProvider);
        return artistsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.primary)),
          error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: colors.textPrimary))),
          data: (artists) {
            DALogger.info('UI Rendering: Rendered ${artists.length} artists in library view');
            return _buildArtistsTab(artists, colors, typography);
          },
        );
      case 4:
        return _buildDownloadsTab(colors, typography);
      case 5:
        return const LocalLibraryTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTabButton(String text, int index, dynamic colors, dynamic typography) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: typography.title.copyWith(
              fontSize: 16.0,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4.0),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2.0,
            width: isSelected ? 40.0 : 0.0,
            color: colors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistDetailsView({
    required String title,
    required List<Song> songs,
    required bool isRemote,
    required dynamic colors,
    required dynamic typography,
  }) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colors.textPrimary,
          onPressed: () {
            setState(() {
              _selectedPlaylistId = null;
            });
          },
        ),
        title: Text(
          title,
          style: typography.title.copyWith(fontSize: 20.0, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: 'Shuffle Playlist',
              onPressed: () {
                ref.read(playbackControllerProvider).shufflePlaylist(songs);
              },
            ),
          if (!isRemote)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete Playlist',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Playlist'),
                    content: Text('Are you sure you want to delete "$title"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: () {
                          ref.read(libraryManagerProvider.notifier).deletePlaylist(_selectedPlaylistId!);
                          Navigator.pop(context);
                          setState(() {
                            _selectedPlaylistId = null;
                          });
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: songs.isEmpty
          ? const Center(
              child: DAEmptyState(
                icon: Icons.playlist_play,
                title: 'Playlist is Empty',
                description: 'Add songs to this playlist using song overflow menus.',
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DATokens.spacingMedium,
                    vertical: DATokens.spacingSmall,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(playbackControllerProvider).setQueue(
                              songs,
                              startIndex: 0,
                              autoPlay: true,
                              queueMode: QueueMode.playlist,
                            );
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: DATokens.spacingSmall),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(playbackControllerProvider).shufflePlaylist(songs);
                          },
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    cacheExtent: 800.0,
                    addRepaintBoundaries: true,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: DATokens.spacingMedium,
                      right: DATokens.spacingMedium,
                      top: DATokens.spacingSmall,
                      bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingSmall,
                    ),
                    itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];

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
                            songs,
                            startIndex: index,
                            autoPlay: true,
                            queueMode: QueueMode.playlist,
                          );
                    },
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
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
                      style: typography.title.copyWith(fontSize: 14.0),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      song.artist,
                      style: typography.caption.copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isRemote)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                            onPressed: () {
                              ref.read(libraryManagerProvider.notifier).removeSongFromPlaylist(_selectedPlaylistId!, song.id);
                            },
                          ),
                        IconButton(
                          icon: Icon(Icons.more_vert, color: colors.textSecondary),
                          onPressed: () {
                            showSongOptionsMenu(context, ref, song);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistsTab(List<Playlist> playlists, dynamic colors, dynamic typography) {
    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DAEmptyState(
              icon: Icons.my_library_music_outlined,
              title: 'No Playlists Found',
              description: 'Create custom playlists or synchronize your account.',
            ),
            const SizedBox(height: DATokens.spacingMedium),
            ElevatedButton.icon(
              onPressed: () => _showCreatePlaylistDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Playlist'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: DATokens.spacingMedium,
        right: DATokens.spacingMedium,
        top: DATokens.spacingSmall,
        bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingSmall,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final pl = playlists[index];
        final isRemote = pl.id.startsWith('PL') || pl.id.startsWith('VL');

        return Card(
          color: colors.surfaceCard.withValues(alpha: 0.1),
          margin: const EdgeInsets.only(bottom: DATokens.spacingSmall),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DATokens.radiusMedium),
            side: BorderSide(color: colors.border.withValues(alpha: 0.1)),
          ),
          child: ListTile(
            onTap: () {
              setState(() {
                _selectedPlaylistId = pl.id;
              });
            },
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceHover,
                borderRadius: BorderRadius.circular(DATokens.radiusSmall),
              ),
              child: Icon(
                isRemote ? Icons.language_outlined : Icons.playlist_play,
                color: colors.primary,
              ),
            ),
            title: Text(
              pl.name,
              style: typography.title.copyWith(fontSize: 14.0, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isRemote ? 'YouTube Music Playlist' : '${pl.songs.length} songs',
              style: typography.caption.copyWith(color: colors.textSecondary),
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _buildSongsTab(List<Song> songs, dynamic colors, dynamic typography) {
    if (songs.isEmpty) {
      return const Center(
        child: DAEmptyState(
          icon: Icons.music_note_outlined,
          title: 'No Songs Found',
          description: 'Your unified songs library is empty.',
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: DATokens.spacingMedium,
        right: DATokens.spacingMedium,
        top: DATokens.spacingSmall,
        bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingSmall,
      ),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];

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
                    songs,
                    startIndex: index,
                    autoPlay: true,
                    queueMode: QueueMode.playlist,
                  );
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
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
              style: typography.title.copyWith(fontSize: 14.0),
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
              icon: Icon(Icons.more_vert, color: colors.textSecondary),
              onPressed: () {
                showSongOptionsMenu(context, ref, song);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumsTab(List<Album> albums, dynamic colors, dynamic typography) {
    if (albums.isEmpty) {
      return const Center(
        child: DAEmptyState(
          icon: Icons.album_outlined,
          title: 'No Albums Found',
          description: 'Your unified albums library is empty.',
        ),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: DATokens.spacingMedium,
        right: DATokens.spacingMedium,
        top: DATokens.spacingMedium,
        bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingMedium,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: DATokens.spacingMedium,
        mainAxisSpacing: DATokens.spacingMedium,
        childAspectRatio: 0.8,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];

        return GestureDetector(
          onTap: () {
            context.push('/album/${album.id}');
          },
          child: Card(
            color: colors.surfaceCard.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DATokens.radiusMedium),
              side: BorderSide(color: colors.border.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8.0)),
                    child: DAImage(
                      url: album.artworkUrl,
                      fit: BoxFit.cover,
                      placeholder: const Icon(Icons.album, size: 48, color: Colors.white24),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(DATokens.spacingSmall),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: typography.title.copyWith(fontSize: 13.0, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        album.artist,
                        style: typography.caption.copyWith(color: colors.textSecondary, fontSize: 11.0),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistsTab(List<Artist> artists, dynamic colors, dynamic typography) {
    if (artists.isEmpty) {
      return const Center(
        child: DAEmptyState(
          icon: Icons.people_outline,
          title: 'No Artists Found',
          description: 'Your unified artists library is empty.',
        ),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: DATokens.spacingMedium,
        right: DATokens.spacingMedium,
        top: DATokens.spacingMedium,
        bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingMedium,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: DATokens.spacingMedium,
        mainAxisSpacing: DATokens.spacingMedium,
        childAspectRatio: 0.8,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];

        return GestureDetector(
          onTap: () {
            context.push('/artist/${artist.id}');
          },
          child: Card(
            color: colors.surfaceCard.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DATokens.radiusMedium),
              side: BorderSide(color: colors.border.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(DATokens.spacingMedium),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: ClipOval(
                      child: DAImage(
                        url: artist.artworkUrl,
                        fit: BoxFit.cover,
                        placeholder: const Icon(Icons.person, size: 48, color: Colors.white24),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: DATokens.spacingSmall, left: DATokens.spacingSmall, right: DATokens.spacingSmall),
                  child: Text(
                    artist.name,
                    style: typography.title.copyWith(fontSize: 13.0, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadsTab(dynamic colors, dynamic typography) {
    final downloadManager = ref.watch(downloadManagerProvider);
    final allTasks = downloadManager.allTasks;
    final activeTasks = allTasks.where((t) => 
      t.status == DownloadStatus.downloading || 
      t.status == DownloadStatus.queued || 
      t.status == DownloadStatus.paused ||
      t.status == DownloadStatus.failed
    ).toList();

    final downloadedSongsAsync = ref.watch(downloadedSongsProvider);

    return downloadedSongsAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: colors.primary)),
      error: (err, stack) => Center(
        child: Text('Error loading downloads: $err', style: TextStyle(color: colors.textPrimary)),
      ),
      data: (downloadedSongs) {
        if (activeTasks.isEmpty && downloadedSongs.isEmpty) {
          return const Center(
            child: DAEmptyState(
              icon: Icons.download_for_offline_outlined,
              title: 'No Offline Music',
              description: 'Download tracks using the options menu to listen offline.',
            ),
          );
        }

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingMedium),
          children: [
            if (activeTasks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DATokens.spacingSmall),
                child: Text(
                  'Downloading (${activeTasks.length})',
                  style: typography.title.copyWith(fontSize: 16.0, fontWeight: FontWeight.bold, color: colors.textPrimary),
                ),
              ),
              ...activeTasks.map((t) => _buildActiveTaskCard(t, colors, typography)),
              const Divider(color: Colors.white10, height: 24.0),
            ],
            if (downloadedSongs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DATokens.spacingSmall),
                child: Text(
                  'Downloaded Tracks',
                  style: typography.title.copyWith(fontSize: 16.0, fontWeight: FontWeight.bold, color: colors.textPrimary),
                ),
              ),
              ...List.generate(downloadedSongs.length, (index) {
                final song = downloadedSongs[index];
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
                            downloadedSongs,
                            startIndex: index,
                            autoPlay: true,
                            queueMode: QueueMode.playlist,
                          );
                    },
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
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
                      style: typography.title.copyWith(fontSize: 14.0),
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
                      icon: Icon(Icons.more_vert, color: colors.textSecondary),
                      onPressed: () {
                        showSongOptionsMenu(context, ref, song);
                      },
                    ),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _buildActiveTaskCard(DownloadTask t, dynamic colors, dynamic typography) {
    String statusText = '';
    switch (t.status) {
      case DownloadStatus.queued:
        statusText = 'Queued...';
        break;
      case DownloadStatus.downloading:
        statusText = '${(t.progress * 100).toStringAsFixed(0)}% downloading...';
        break;
      case DownloadStatus.paused:
        statusText = 'Paused';
        break;
      case DownloadStatus.failed:
        statusText = 'Failed: ${t.error ?? "Unknown error"}';
        break;
      default:
        break;
    }

    return Card(
      color: colors.surfaceCard.withValues(alpha: 0.1),
      margin: const EdgeInsets.only(bottom: DATokens.spacingSmall),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DATokens.radiusMedium),
        side: BorderSide(color: colors.border.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DATokens.spacingSmall),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: typography.title.copyWith(fontSize: 14.0, fontWeight: FontWeight.bold, color: colors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        t.artist,
                        style: typography.caption.copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t.status == DownloadStatus.downloading)
                      IconButton(
                        icon: const Icon(Icons.pause, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          ref.read(downloadManagerProvider.notifier).pauseDownload(t.songId);
                        },
                      )
                    else if (t.status == DownloadStatus.paused)
                      IconButton(
                        icon: const Icon(Icons.play_arrow, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          ref.read(downloadManagerProvider.notifier).resumeDownload(t.songId);
                        },
                      ),
                    const SizedBox(width: DATokens.spacingMedium),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        ref.read(downloadManagerProvider.notifier).cancelDownload(t.songId);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: DATokens.spacingSmall),
            LinearProgressIndicator(
              value: t.progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
            const SizedBox(height: 4.0),
            Text(
              statusText,
              style: typography.caption.copyWith(color: t.status == DownloadStatus.failed ? Colors.redAccent : colors.textSecondary, fontSize: 11.0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
