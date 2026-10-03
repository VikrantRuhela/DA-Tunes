import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/search_service.dart';
import '../../../domain/entities/album.dart';
import '../../../domain/entities/artist.dart';
import '../../../domain/entities/playlist.dart';
import '../../../domain/entities/search_result.dart';
import '../../../domain/entities/song.dart';
import '../../../domain/entities/value_objects.dart';
import '../../../shared/providers/backend_providers.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../shared/models/music_models.dart' as shared;
import '../../../shared/widgets/da_empty_state.dart';
import '../../../shared/widgets/da_image.dart';
import '../../../shared/utils/artist_navigation.dart';
import '../../../shared/utils/song_options.dart';
import '../../../shared/utils/metadata_formatter.dart';
import '../../taste_engine/presentation/providers/taste_engine_providers.dart';
import '../../local_library/data/local_library_repository.dart';

class SearchPageState {
  final String query;
  final bool isLoading;
  final SearchResult? result;
  final String? error;

  const SearchPageState({
    required this.query,
    required this.isLoading,
    this.result,
    this.error,
  });

  SearchPageState copyWith({
    String? query,
    bool? isLoading,
    SearchResult? result,
    String? error,
  }) {
    return SearchPageState(
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      result: result ?? this.result,
      error: error ?? this.error,
    );
  }
}

class SearchPageNotifier extends StateNotifier<SearchPageState> {
  final SearchService _searchService;
  final Ref _ref;
  Timer? _debounceTimer;

  SearchPageNotifier(this._searchService, this._ref)
      : super(const SearchPageState(query: '', isLoading: false));

  void onQueryChanged(String query) {
    if (state.query == query) return;

    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      state = SearchPageState(query: query, isLoading: false, result: null);
      return;
    }

    state = state.copyWith(query: query, isLoading: true, error: null);

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final currentQuery = query;
    DALogger.info('SearchPage: Search Started for query "$query"');

    _ref.read(tasteEngineNotifierProvider.notifier).recordSearch(query);

    try {
      final results = await _searchService.search(query);

      if (state.query != currentQuery) {
        DALogger.info('SearchPage: Search Cancelled for query "$query"');
        return;
      }

      // Query and merge local search results
      final localSongs = _ref.read(localLibraryRepositoryProvider.notifier).search(query);
      
      final domainLocalSongs = localSongs.map((s) => Song(
        id: s.id,
        title: '[Local] ${s.title}',
        artistId: s.artist,
        albumId: s.album,
        duration: DurationValue(s.duration),
        thumbnail: Artwork(s.artworkUrl),
        artwork: Artwork(s.artworkUrl),
        sourceId: s.source,
      )).toList();

      final Set<String> seenAlbums = {};
      final List<Album> domainLocalAlbums = [];
      final Set<String> seenArtists = {};
      final List<Artist> domainLocalArtists = [];

      for (final song in localSongs) {
        if (song.album.isNotEmpty && !seenAlbums.contains(song.album)) {
          seenAlbums.add(song.album);
          domainLocalAlbums.add(Album(
            id: song.album,
            title: '[Local] ${song.album}',
            artistId: song.artist,
            cover: Artwork(song.artworkUrl),
            year: 2026,
            trackCount: 1,
            duration: DurationValue(song.duration),
          ));
        }
        if (song.artist.isNotEmpty && !seenArtists.contains(song.artist)) {
          seenArtists.add(song.artist);
          domainLocalArtists.add(Artist(
            id: song.artist,
            name: '[Local] ${song.artist}',
            image: Artwork(song.artworkUrl),
            subscriberCount: 0,
            description: 'Local Artist',
            genres: const ['Local'],
          ));
        }
      }

      final mergedSongs = [...domainLocalSongs, ...results.songs];
      final mergedAlbums = [...domainLocalAlbums, ...results.albums];
      final mergedArtists = [...domainLocalArtists, ...results.artists];

      final mergedResult = results.copyWith(
        songs: mergedSongs,
        albums: mergedAlbums,
        artists: mergedArtists,
      );

      final totalCount = mergedResult.songs.length +
          mergedResult.albums.length +
          mergedResult.artists.length +
          mergedResult.playlists.length;

      DALogger.info('SearchPage: Search Finished for query "$query". Results count: $totalCount');
      state = state.copyWith(isLoading: false, result: mergedResult);
    } catch (e, stack) {
      if (state.query != currentQuery) return;
      DALogger.error('SearchPage: Search Failed for query "$query"', e, stack);
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() {
    _debounceTimer?.cancel();
    state = const SearchPageState(query: '', isLoading: false, result: null);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

final searchPageProvider =
    StateNotifierProvider<SearchPageNotifier, SearchPageState>((ref) {
  return SearchPageNotifier(ref.watch(searchServiceProvider), ref);
});

class SearchPage extends ConsumerStatefulWidget {
  final String initialQuery;
  const SearchPage({super.key, this.initialQuery = ''});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(searchPageProvider.notifier).onQueryChanged(widget.initialQuery);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<DAThemeExtension>() ?? DAThemeExtension.dark;
    final state = ref.watch(searchPageProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DATokens.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Input Box
              Container(
                decoration: BoxDecoration(
                  color: theme.surfaceCard,
                  borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                  border: Border.all(color: theme.border, width: 1.0),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  onChanged: (val) => ref.read(searchPageProvider.notifier).onQueryChanged(val),
                  style: theme.typography.body.copyWith(color: theme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, or albums...',
                    hintStyle: theme.typography.body.copyWith(color: theme.textSecondary),
                    prefixIcon: Icon(Icons.search_outlined, color: theme.textSecondary),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_outlined, color: theme.textSecondary),
                            onPressed: () {
                              _controller.clear();
                              ref.read(searchPageProvider.notifier).clear();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: DATokens.spacingMedium,
                      vertical: DATokens.spacingMedium,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DATokens.spacingMedium),

              // Search Body State transitions
              Expanded(
                child: _buildSearchBody(context, state, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBody(BuildContext context, SearchPageState state, DAThemeExtension theme) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_outlined, color: Colors.redAccent, size: DATokens.iconXLarge),
            const SizedBox(height: DATokens.spacingMedium),
            Text(
              'Search Failed',
              style: theme.typography.title.copyWith(color: theme.textPrimary),
            ),
            const SizedBox(height: DATokens.spacingTiny),
            Text(
              state.error!,
              style: theme.typography.body.copyWith(color: theme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (state.query.trim().isEmpty) {
      return const Center(
        child: DAEmptyState(
          icon: Icons.search_outlined,
          title: 'Search',
          description: 'Search for songs, artists, or albums.',
        ),
      );
    }

    final result = state.result;
    if (result == null ||
        (result.songs.isEmpty &&
            result.albums.isEmpty &&
            result.artists.isEmpty &&
            result.playlists.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_outlined, color: theme.textSecondary, size: DATokens.iconXLarge),
            const SizedBox(height: DATokens.spacingMedium),
            Text(
              'No results found.',
              style: theme.typography.title.copyWith(color: theme.textPrimary),
            ),
            const SizedBox(height: DATokens.spacingTiny),
            Text(
              'Try searching with different terms or check spelling.',
              style: theme.typography.body.copyWith(color: theme.textSecondary),
            ),
          ],
        ),
      );
    }

    final cleanQuery = state.query.trim().toLowerCase();
    final isArtistMatch = result.topResult is Artist ||
        (result.artists.isNotEmpty &&
            result.artists.any((a) =>
                a.name.trim().toLowerCase() == cleanQuery ||
                a.name.trim().toLowerCase().contains(cleanQuery) ||
                cleanQuery.contains(a.name.trim().toLowerCase())));

    final List<Widget> sections = [];

    if (result.topResult != null) {
      sections.add(_buildTopResultSection(result.topResult, theme));
      sections.add(const SizedBox(height: DATokens.spacingLarge));
    }

    final Widget songsWidget = result.songs.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Songs', theme),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: result.songs.length,
                itemBuilder: (context, idx) {
                  return _buildSongItem(result.songs, idx, theme);
                },
              ),
              const SizedBox(height: DATokens.spacingLarge),
            ],
          )
        : const SizedBox.shrink();

    final Widget artistsWidget = result.artists.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Artists', theme),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: result.artists.length,
                  itemBuilder: (context, idx) {
                    final artist = result.artists[idx];
                    return _buildArtistItem(artist, theme);
                  },
                ),
              ),
              const SizedBox(height: DATokens.spacingLarge),
            ],
          )
        : const SizedBox.shrink();

    final Widget albumsWidget = result.albums.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Albums', theme),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: result.albums.length,
                  itemBuilder: (context, idx) {
                    final album = result.albums[idx];
                    return _buildAlbumItem(album, theme);
                  },
                ),
              ),
              const SizedBox(height: DATokens.spacingLarge),
            ],
          )
        : const SizedBox.shrink();

    final Widget playlistsWidget = result.playlists.isNotEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Playlists', theme),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: result.playlists.length,
                  itemBuilder: (context, idx) {
                    final playlist = result.playlists[idx];
                    return _buildPlaylistItem(playlist, theme);
                  },
                ),
              ),
            ],
          )
        : const SizedBox.shrink();

    if (isArtistMatch) {
      sections.add(artistsWidget);
      sections.add(songsWidget);
      sections.add(albumsWidget);
      sections.add(playlistsWidget);
    } else {
      sections.add(songsWidget);
      sections.add(albumsWidget);
      sections.add(artistsWidget);
      sections.add(playlistsWidget);
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: DATokens.spacingMedium,
        right: DATokens.spacingMedium,
        top: DATokens.spacingSmall,
        bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingSmall,
      ),
      children: sections,
    );
  }

  Widget _buildSectionHeader(String title, DAThemeExtension theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DATokens.spacingSmall),
      child: Text(
        title,
        style: theme.typography.headline.copyWith(
          fontSize: 18.0,
          color: theme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildTopResultSection(dynamic top, DAThemeExtension theme) {
    if (top is Artist) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Top Result', theme),
          InkWell(
            onTap: () {
              if (top.id.isNotEmpty) {
                context.push('/artist/${top.id}');
              } else {
                navigateToArtistByName(context, ref, top.name);
              }
            },
            borderRadius: BorderRadius.circular(DATokens.radiusLarge),
            child: Container(
              padding: const EdgeInsets.all(DATokens.spacingMedium),
              decoration: BoxDecoration(
                color: theme.surfaceCard,
                borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                border: Border.all(color: theme.border, width: 1.0),
              ),
              child: Row(
                children: [
                  ClipOval(
                    child: DAImage(
                      url: top.image.url,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        width: 80,
                        height: 80,
                        color: theme.surfaceHover,
                        child: Icon(Icons.person_outlined, color: theme.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: DATokens.spacingMedium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          top.name,
                          style: theme.typography.title.copyWith(fontSize: 18.0),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: DATokens.spacingTiny),
                        Text(
                          'Artist • Tap to view profile',
                          style: theme.typography.body.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.textSecondary),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (top is Song) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Top Result', theme),
          InkWell(
            onTap: () {
              debugPrint('Tapped Song ID: ${top.id}, Title: ${top.title}');
              final allSearchSongs = <Song>[top];
              final searchSongs = ref.read(searchPageProvider).result?.songs ?? [];
              for (final s in searchSongs) {
                if (s.id != top.id) {
                  allSearchSongs.add(s);
                }
              }
              final modelSongs = allSearchSongs.map((s) => shared.Song(
                id: s.id,
                title: s.title,
                artist: s.artistId,
                album: s.albumId,
                duration: s.duration.value,
                artworkUrl: s.artwork.url,
                source: s.sourceId,
                lyrics: null,
              )).toList();
              ref.read(playbackControllerProvider).setQueue(modelSongs, startIndex: 0, autoPlay: true);
            },
            borderRadius: BorderRadius.circular(DATokens.radiusLarge),
            child: Container(
              padding: const EdgeInsets.all(DATokens.spacingMedium),
              decoration: BoxDecoration(
                color: theme.surfaceCard,
                borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                border: Border.all(color: theme.border, width: 1.0),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: DAImage(
                      url: top.artwork.url,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        width: 80,
                        height: 80,
                        color: theme.surfaceHover,
                        child: Icon(Icons.music_note_outlined, color: theme.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: DATokens.spacingMedium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          top.title,
                          style: theme.typography.title.copyWith(fontSize: 18.0),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: DATokens.spacingTiny),
                        GestureDetector(
                          onTap: () => navigateToArtistByName(context, ref, top.artistId),
                          child: Text(
                            'Song • ${MetadataFormatter.formatArtist(top.artistId)}',
                            style: theme.typography.body.copyWith(
                              color: theme.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert, color: theme.textSecondary),
                    onPressed: () {
                      final modelSong = shared.Song(
                        id: top.id,
                        title: top.title,
                        artist: top.artistId,
                        album: top.albumId,
                        duration: top.duration.value,
                        artworkUrl: top.artwork.url,
                        source: top.sourceId,
                        lyrics: null,
                      );
                      showSongOptionsMenu(context, ref, modelSong);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSongItem(List<Song> allSongs, int index, DAThemeExtension theme) {
    final song = allSongs[index];
    return ListTile(
      onTap: () {
        debugPrint('Tapped Song ID: ${song.id}, Title: ${song.title}');
        final modelSongs = allSongs.map((s) => shared.Song(
          id: s.id,
          title: s.title,
          artist: s.artistId,
          album: s.albumId,
          duration: s.duration.value,
          artworkUrl: s.artwork.url,
          source: s.sourceId,
          lyrics: null,
        )).toList();
        ref.read(playbackControllerProvider).setQueue(modelSongs, startIndex: index, autoPlay: true);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: DAImage(
          url: song.thumbnail.url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: Container(
            width: 48,
            height: 48,
            color: theme.surfaceHover,
            child: Icon(Icons.music_note_outlined, color: theme.textSecondary),
          ),
        ),
      ),
      title: Text(
        song.title,
        style: theme.typography.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: GestureDetector(
        onTap: () => navigateToArtistByName(context, ref, song.artistId),
        child: Text(
          MetadataFormatter.formatArtist(song.artistId),
          style: theme.typography.body.copyWith(
            color: theme.textSecondary,
            decoration: TextDecoration.underline,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(song.duration.value),
            style: theme.typography.caption,
          ),
          const SizedBox(width: DATokens.spacingSmall),
          IconButton(
            icon: Icon(Icons.more_vert, color: theme.textSecondary),
            onPressed: () {
              final modelSong = shared.Song(
                id: song.id,
                title: song.title,
                artist: song.artistId,
                album: song.albumId,
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
    );
  }

  Widget _buildArtistItem(Artist artist, DAThemeExtension theme) {
    return InkWell(
      onTap: () => context.push('/artist/${artist.id}'),
      borderRadius: BorderRadius.circular(DATokens.radiusLarge),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: DATokens.spacingMedium),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: theme.surfaceHover,
              backgroundImage: NetworkImage(artist.image.url),
              onBackgroundImageError: (ctx, err) {},
            ),
            const SizedBox(height: DATokens.spacingSmall),
            Text(
              artist.name,
              style: theme.typography.caption.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumItem(Album album, DAThemeExtension theme) {
    return InkWell(
      onTap: () => context.push('/album/${album.id}'),
      borderRadius: BorderRadius.circular(DATokens.radiusMedium),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: DATokens.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                album.cover.url,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) => Container(
                  width: 120,
                  height: 120,
                  color: theme.surfaceHover,
                  child: Icon(Icons.album_outlined, color: theme.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: DATokens.spacingSmall),
            Text(
              album.title,
              style: theme.typography.caption.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            GestureDetector(
              onTap: () => navigateToArtistByName(context, ref, album.artistId),
              child: Text(
                album.artistId,
                style: theme.typography.caption.copyWith(
                  color: theme.textSecondary,
                  decoration: TextDecoration.underline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistItem(Playlist playlist, DAThemeExtension theme) {
    return InkWell(
      onTap: () => context.push('/album/${playlist.id}'),
      borderRadius: BorderRadius.circular(DATokens.radiusMedium),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: DATokens.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                playlist.cover.url,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) => Container(
                  width: 120,
                  height: 120,
                  color: theme.surfaceHover,
                  child: Icon(Icons.playlist_play_outlined, color: theme.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: DATokens.spacingSmall),
            Text(
              playlist.title,
              style: theme.typography.caption.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'By ${playlist.owner}',
              style: theme.typography.caption.copyWith(color: theme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
