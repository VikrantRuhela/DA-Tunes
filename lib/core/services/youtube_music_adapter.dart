import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'source_adapter.dart';
import 'youtube_music_account_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_credential_store.dart';
import '../exceptions/playback_exceptions.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/home_feed.dart';
import '../../domain/entities/audio_stream.dart';
import '../../domain/entities/value_objects.dart';
import 'logger_service.dart';
import 'music_content_classifier.dart';

/// Concrete YouTube Music source adapter mapping remote API details to pure Domain entities.
class YouTubeMusicAdapter implements MusicSourceAdapter {
  bool _isInitialized = false;
  late yt.YoutubeExplode _ytClient;
  final Map<String, Song> _songCache = {};

  void cacheSongForTesting(Song song) {
    _songCache[song.id] = song;
  }

  yt.YoutubeExplode get ytClientForTesting => _ytClient;

  static final Map<String, String> videoChannelIdMap = {};
  static final Map<String, String> videoAuthorMap = {};

  // Caches for artist details
  final Map<String, List<Song>> _artistSongs = {};
  final Map<String, List<Album>> _artistAlbums = {};
  final Map<String, List<Album>> _artistSingles = {};
  final Map<String, List<Playlist>> _artistPlaylists = {};
  final Map<String, List<Artist>> _artistRelated = {};

  @override
  List<Song> getArtistSongs(String artistId) => _artistSongs[artistId] ?? const [];

  @override
  List<Album> getArtistAlbums(String artistId) => _artistAlbums[artistId] ?? const [];

  @override
  List<Album> getArtistSingles(String artistId) => _artistSingles[artistId] ?? const [];

  @override
  List<Playlist> getArtistPlaylists(String artistId) => _artistPlaylists[artistId] ?? const [];

  @override
  List<Artist> getArtistRelated(String artistId) => _artistRelated[artistId] ?? const [];

  @override
  String get id => 'youtube_music';

  @override
  String get name => 'YouTube Music';

  void _checkInitialized() {
    if (!_isInitialized) {
      throw const SourceException('YouTube Music Adapter not initialized. Call initialize() first.');
    }
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _ytClient = yt.YoutubeExplode(httpClient: yt.YoutubeHttpClient(InterceptingClient()));
    DALogger.info('YouTubeMusicAdapter: YoutubeExplode client initialized (unauthenticated, clean headers for playback).');
    _isInitialized = true;
  }

  @override
  Future<void> dispose() async {
    if (!_isInitialized) return;
    _ytClient.close();
    _isInitialized = false;
    DALogger.info('YouTubeMusicAdapter: YoutubeExplode client closed.');
  }

  Duration _parseDuration(String durationStr) {
    if (durationStr.isEmpty) return Duration.zero;
    final parts = durationStr.split(':');
    try {
      if (parts.length == 3) {
        return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]),
        );
      } else if (parts.length == 2) {
        return Duration(
          minutes: int.parse(parts[0]),
          seconds: int.parse(parts[1]),
        );
      }
    } catch (_) {
      // Fallback on parsing exceptions
    }
    return Duration.zero;
  }

  @override
  Future<SearchResult> search(String query) async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Searching for "$query"');

    try {
      final songs = <Song>[];
      final albums = <Album>[];
      final artists = <Artist>[];
      final playlists = <Playlist>[];

      try {
        final client = HttpClient();
        const apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
        final url = Uri.parse('https://music.youtube.com/youtubei/v1/search?key=$apiKey');

        final request = await client.postUrl(url);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');

        final gl = await _getGuestRegionCode();
        final payload = {
          'query': query,
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20260304.03.00',
              'hl': 'en',
              'gl': gl,
            }
          },
          'params': 'EgWKAQIIAWoKEAkQChAFEAMQBA%3D%3D'
        };

        request.write(jsonEncode(payload));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        client.close();

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(body);
          final contents = data['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
          if (contents != null) {
            for (final section in contents) {
              if (section.containsKey('musicCardShelfRenderer')) {
                final card = section['musicCardShelfRenderer'];
                final titleRuns = card['title']?['runs'] as List?;
                String cardTitle = '';
                if (titleRuns != null && titleRuns.isNotEmpty) {
                  cardTitle = titleRuns[0]['text'] ?? '';
                }
                final nav = card['title']?['runs']?[0]?['navigationEndpoint'] ?? card['navigationEndpoint'];
                final browseId = nav?['browseEndpoint']?['browseId'] as String? ?? '';
                final videoId = nav?['watchEndpoint']?['videoId'] as String? ?? '';
                final thumbs = card['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
                String cardImg = '';
                if (thumbs != null && thumbs.isNotEmpty) {
                  cardImg = thumbs.last['url'] ?? '';
                }

                if ((browseId.startsWith('UC') || browseId.startsWith('FE') || videoId.isEmpty) && cardTitle.isNotEmpty && browseId.isNotEmpty) {
                  artists.add(Artist(
                    id: browseId,
                    name: cardTitle,
                    image: Artwork(cardImg),
                    subscriberCount: 0,
                    description: '',
                    genres: const [],
                  ));
                }
              }

              final items = section['musicShelfRenderer']?['contents'];
              if (items != null) {
                for (final item in items) {
                  final renderer = item['musicResponsiveListItemRenderer'];
                  if (renderer != null) {
                    final navEndpoint = renderer['navigationEndpoint'];
                    final videoId = renderer['playlistItemData']?['videoId'] ??
                        renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] ??
                        navEndpoint?['watchEndpoint']?['videoId'] ??
                        '';

                    final flexColumns = renderer['flexColumns'] as List?;
                    String title = '';
                    String artistName = '';

                    if (flexColumns != null && flexColumns.isNotEmpty) {
                      final titleRuns = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
                      if (titleRuns != null && titleRuns.isNotEmpty) {
                        title = titleRuns[0]['text'] ?? '';
                      }
                      if (flexColumns.length > 1) {
                        final artistRuns = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
                        if (artistRuns != null && artistRuns.isNotEmpty) {
                          final fullText = artistRuns.map((r) => r['text'] ?? '').join('');
                          final parts = fullText.split(' • ');
                          artistName = parts.first.trim();
                        }
                      }
                    }

                    final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
                    String artworkUrl = videoId.isNotEmpty ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg' : '';
                    if (thumbnails != null && thumbnails.isNotEmpty) {
                      artworkUrl = thumbnails.last['url'] ?? artworkUrl;
                    }

                    final browseId = navEndpoint?['browseEndpoint']?['browseId'] as String? ?? '';
                    final pageType = navEndpoint?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextData']?['pageType'] as String? ?? '';

                    if (videoId.isNotEmpty) {
                      Duration duration = Duration.zero;
                      final fixedColumns = renderer['fixedColumns'] as List?;
                      if (fixedColumns != null && fixedColumns.isNotEmpty) {
                        final durRuns = (fixedColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] ??
                                         fixedColumns[0]['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']) as List?;
                        if (durRuns != null && durRuns.isNotEmpty) {
                          duration = _parseDurationString(durRuns[0]['text'] ?? '');
                        }
                      }
                      if (duration == Duration.zero && flexColumns != null) {
                        duration = _extractDurationFromFlexColumns(flexColumns);
                      }

                      if (title.isNotEmpty) {
                        final song = _mapToSong(
                          id: videoId,
                          rawTitle: title,
                          rawArtist: artistName,
                          duration: duration,
                        );

                        if (MusicContentClassifier.isMusicSong(song)) {
                          _songCache[song.id] = song;
                          songs.add(song);
                        }
                      }
                    } else if (browseId.isNotEmpty || pageType.isNotEmpty) {
                      if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' || browseId.startsWith('UC')) {
                        if (title.isNotEmpty) {
                          artists.add(Artist(
                            id: browseId,
                            name: title,
                            image: Artwork(artworkUrl),
                            subscriberCount: 0,
                            description: '',
                            genres: const [],
                          ));
                        }
                      } else if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || browseId.startsWith('MPRE')) {
                        if (title.isNotEmpty) {
                          albums.add(Album(
                            id: browseId,
                            title: title,
                            artistId: artistName,
                            cover: Artwork(artworkUrl),
                            year: 2026,
                            trackCount: 1,
                            duration: DurationValue(Duration.zero),
                          ));
                        }
                      } else if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST' || browseId.startsWith('VL') || browseId.startsWith('PL')) {
                        if (title.isNotEmpty) {
                          playlists.add(Playlist(
                            id: browseId,
                            title: title,
                            description: 'YouTube Playlist',
                            cover: Artwork(artworkUrl),
                            owner: artistName.isNotEmpty ? artistName : 'YouTube',
                            songIds: const [],
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          ));
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {}

      if (songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty) {
        try {
          final results = await _ytClient.search.searchContent(query).timeout(const Duration(seconds: 8));
          for (final result in results) {
            if (result is yt.SearchVideo) {
              final song = _mapToSong(
                id: result.id.value,
                rawTitle: result.title,
                rawArtist: result.author,
                duration: _parseDuration(result.duration),
                channelId: result.channelId,
              );
              if (MusicContentClassifier.isMusicSong(song)) {
                _songCache[song.id] = song;
                songs.add(song);
              }
            } else if (result is yt.SearchPlaylist) {
              playlists.add(Playlist(
                id: result.id.value,
                title: result.title,
                description: 'YouTube Playlist',
                cover: Artwork(result.thumbnails.isNotEmpty ? result.thumbnails.first.url.toString() : ''),
                owner: 'YouTube',
                songIds: const [],
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ));
            } else if (result is yt.SearchChannel) {
              artists.add(Artist(
                id: result.id.value,
                name: result.name,
                image: Artwork(result.thumbnails.isNotEmpty ? result.thumbnails.first.url.toString() : ''),
                subscriberCount: 0,
                description: result.description,
                genres: const [],
              ));
            }
          }
        } catch (_) {}
      }

      if (artists.isEmpty) {
        try {
          final foundArtists = await searchArtists(query).timeout(const Duration(seconds: 3));
          for (final fa in foundArtists) {
            if (!artists.any((a) => a.id == fa.id)) {
              artists.add(fa);
            }
          }
        } catch (_) {}
      }

      dynamic topResult;
      final cleanQuery = query.trim().toLowerCase();

      Artist? matchedArtist;
      for (final a in artists) {
        final cleanName = a.name.trim().toLowerCase();
        if (cleanName == cleanQuery || cleanName.contains(cleanQuery) || cleanQuery.contains(cleanName)) {
          matchedArtist = a;
          break;
        }
      }

      if (matchedArtist != null) {
        topResult = matchedArtist;
      } else if (songs.isNotEmpty) {
        topResult = songs.first;
      } else if (artists.isNotEmpty) {
        topResult = artists.first;
      }

      final res = SearchResult(
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
        topResult: topResult,
      );

      return res;
    } catch (e, stack) {
      DALogger.error('YouTubeMusicAdapter: Search failed for "$query"', e, stack);
      return SearchResult(
        songs: const [],
        albums: const [],
        artists: const [],
        playlists: const [],
        topResult: null,
      );
    }
  }

  @override
  Future<List<Artist>> searchArtists(String query) async {
    _checkInitialized();
    try {
      final headers = await _getHomeHeaders();
      const apiKey = 'AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI';
      final url = Uri.parse('https://music.youtube.com/youtubei/v1/search?key=$apiKey');
      final gl = await _getGuestRegionCode();
      final payload = {
        'query': query,
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20260707.01.00',
            'hl': 'en',
            'gl': gl,
          }
        },
        'params': 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D'
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));

      final artists = <Artist>[];
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final contents = data['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
        if (contents != null) {
          for (final section in contents) {
            final items = section['musicShelfRenderer']?['contents'];
            if (items != null) {
              for (final item in items) {
                final renderer = item['musicResponsiveListItemRenderer'];
                if (renderer != null) {
                  final flexColumns = renderer['flexColumns'] as List?;
                  String name = '';
                  if (flexColumns != null && flexColumns.isNotEmpty) {
                    final runs = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
                    if (runs != null && runs.isNotEmpty) {
                      name = runs[0]['text'] ?? '';
                    }
                  }
                  final id = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] ?? '';
                  final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
                  String image = '';
                  if (thumbnails != null && thumbnails.isNotEmpty) {
                    image = thumbnails.last['url'] ?? '';
                  }

                  if (name.isNotEmpty && id.isNotEmpty) {
                    artists.add(Artist(
                      id: id,
                      name: name,
                      image: Artwork(image),
                      subscriberCount: 0,
                      description: '',
                      genres: const [],
                    ));
                  }
                }
              }
            }
          }
        }
      }
      return artists;
    } catch (e, stack) {
      DALogger.error('YouTubeMusicAdapter: searchArtists failed for "$query"', e, stack);
      return [];
    }
  }

  Future<Map<String, String>> _getHomeHeaders() async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'x-youtube-client-name': '67',
      'x-youtube-client-version': '1.20260304.03.00',
      'x-origin': 'https://music.youtube.com',
    };
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final isGuest = prefs.getBool('ytm_guest_mode') ?? false;
      if (isGuest) {
        return headers; // Return generic headers without cookies or auth tokens
      }

      String? cookies = prefs.getString('ytm_cookies');
      if (cookies == null || cookies.trim().isEmpty) {
        cookies = await SecureCredentialStore().readCookies();
      }
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
        final cookiesMap = <String, String>{};
        for (final cookie in cookies.split(';')) {
          final parts = cookie.trim().split('=');
          if (parts.length >= 2) {
            cookiesMap[parts[0]] = parts.sublist(1).join('=');
          }
        }
        final sapisid = cookiesMap['SAPISID'] ?? cookiesMap['__Secure-3PAPISID'];
        if (sapisid != null && sapisid.isNotEmpty) {
          final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          const origin = 'https://music.youtube.com';
          final input = '$timestamp $sapisid $origin';
          final sha1Hex = sha1.convert(utf8.encode(input)).toString();
          headers['Authorization'] = 'SAPISIDHASH ${timestamp}_$sha1Hex';
        }
      }
    } catch (_) {}
    return headers;
  }

  Future<String> _getGuestRegionCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final region = prefs.getString('ytm_guest_region') ?? 'United States';
      switch (region) {
        case 'India':
          return 'IN';
        case 'United Kingdom':
          return 'GB';
        case 'Canada':
          return 'CA';
        case 'Australia':
          return 'AU';
        case 'Japan':
          return 'JP';
        case 'South Korea':
          return 'KR';
        default:
          return 'US';
      }
    } catch (_) {
      return 'US';
    }
  }

  Duration _parseDurationString(String text) {
    if (text.isEmpty) return Duration.zero;
    final parts = text.split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: mins, seconds: secs);
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]) ?? 0;
      final mins = int.tryParse(parts[1]) ?? 0;
      final secs = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: hrs, minutes: mins, seconds: secs);
    }
    return Duration.zero;
  }

  Duration _extractDurationFromRuns(List? runs) {
    if (runs == null) return Duration.zero;
    final timeRegex = RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$');
    for (final run in runs) {
      if (run is Map) {
        final text = (run['text'] as String? ?? '').trim();
        if (timeRegex.hasMatch(text)) {
          return _parseDurationString(text);
        }
      }
    }
    return Duration.zero;
  }

  Duration _extractDurationFromFlexColumns(List? flexColumns) {
    if (flexColumns == null) return Duration.zero;
    for (final col in flexColumns) {
      if (col is Map) {
        final renderer = col['musicResponsiveListItemFlexColumnRenderer'];
        final runs = renderer?['text']?['runs'] as List?;
        final dur = _extractDurationFromRuns(runs);
        if (dur > Duration.zero) return dur;
      }
    }
    return Duration.zero;
  }

  @override
  Future<HomeFeed> getHome() async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Fetching Home Feed (songs, albums, playlists)...');

    try {
      final headers = await _getHomeHeaders();
      final gl = await _getGuestRegionCode();
      
      print('[HOME] Sending request');
      final response = await http.post(
        Uri.parse('https://music.youtube.com/youtubei/v1/browse?key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30&prettyPrint=false'),
        headers: headers,
        body: jsonEncode({
          "context": {
            "client": {
              "clientName": "WEB_REMIX",
              "clientVersion": "1.20260304.03.00",
              "hl": "en",
              "gl": gl
            }
          },
          "browseId": "FEmusic_home"
        }),
      ).timeout(const Duration(seconds: 8));

      print('[HOME] Response received');
      print('[HOME] Status Code: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('InnerTube browse returned status ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      print('[HOME] JSON parsed');
      
      final List<Song> songs = [];
      final List<Album> albums = [];
      final List<Playlist> playlists = [];

      void traverse(dynamic node) {
        if (node is Map) {
          if (node.containsKey('musicResponsiveListItemRenderer')) {
            try {
              final renderer = node['musicResponsiveListItemRenderer'];
              final playlistItemData = renderer['playlistItemData'];
              String? videoId = playlistItemData?['videoId'] as String?;
              videoId ??= renderer['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
              videoId ??= renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] as String?;

              if (videoId != null && videoId.isNotEmpty) {
                final flexColumns = renderer['flexColumns'] as List?;
                String title = 'Unknown Title';
                String artist = 'Unknown Artist';
                String albumName = 'Single';
                Duration duration = Duration.zero;

                if (flexColumns != null && flexColumns.isNotEmpty) {
                  final titleNode = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']['text']['runs'];
                  if (titleNode is List && titleNode.isNotEmpty) {
                    title = titleNode[0]['text'] as String? ?? 'Unknown Title';
                  }

                  if (flexColumns.length > 1) {
                    final runs = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List?;
                    if (runs != null && runs.isNotEmpty) {
                      artist = runs[0]['text'] as String? ?? 'Unknown Artist';
                      if (runs.length > 2) {
                        albumName = runs[2]['text'] as String? ?? 'Single';
                      }
                    }
                  }
                  
                  duration = _extractDurationFromFlexColumns(flexColumns);
                }

                String thumbnail = '';
                final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
                if (thumbnails != null && thumbnails.isNotEmpty) {
                  thumbnail = thumbnails.last['url'] as String? ?? '';
                }

                final song = Song(
                  id: videoId,
                  title: title,
                  artistId: artist,
                  albumId: albumName,
                  duration: DurationValue(duration),
                  thumbnail: Artwork(thumbnail),
                  artwork: Artwork(thumbnail),
                  sourceId: id,
                );
                _songCache[song.id] = song;
                songs.add(song);
              } else {
                final browseId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
                if (browseId != null) {
                  String title = 'Unknown';
                  String artist = 'Unknown Artist';
                  final flexColumns = renderer['flexColumns'] as List?;
                  if (flexColumns != null && flexColumns.isNotEmpty) {
                    final runs = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List?;
                    if (runs != null && runs.isNotEmpty) {
                      title = runs[0]['text'] as String? ?? 'Unknown';
                    }
                    if (flexColumns.length > 1) {
                      final runs2 = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List?;
                      if (runs2 != null && runs2.isNotEmpty) {
                        artist = runs2[0]['text'] as String? ?? 'Unknown Artist';
                      }
                    }
                  }
                  String cover = '';
                  final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
                  if (thumbnails != null && thumbnails.isNotEmpty) {
                    cover = thumbnails.last['url'] as String? ?? '';
                  }

                  if (browseId.startsWith('PL') || browseId.startsWith('VL') || browseId.startsWith('RD')) {
                    playlists.add(Playlist(
                      id: browseId,
                      title: title,
                      description: 'YouTube Playlist',
                      cover: Artwork(cover),
                      owner: artist,
                      songIds: const [],
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ));
                  } else if (browseId.startsWith('MPREb_') || browseId.contains('album') || browseId.contains('release')) {
                    albums.add(Album(
                      id: browseId,
                      title: title,
                      artistId: artist,
                      cover: Artwork(cover),
                      year: 2026,
                      trackCount: 10,
                      duration: DurationValue(const Duration(minutes: 40)),
                    ));
                  }
                }
              }
            } catch (_) {}
          } else if (node.containsKey('musicTwoRowItemRenderer')) {
            try {
              final renderer = node['musicTwoRowItemRenderer'];
              final navigationEndpoint = renderer['navigationEndpoint'];
              final String? browseId = navigationEndpoint?['browseEndpoint']?['browseId'];
              final String? videoId = navigationEndpoint?['watchEndpoint']?['videoId'];

              final titleText = renderer['title']?['runs']?[0]?['text'] ?? renderer['title']?['simpleText'];
              final title = titleText as String? ?? 'Unknown';

              String artist = 'Unknown Artist';
              final subtitleRuns = renderer['subtitle']?['runs'] as List?;
              if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
                artist = subtitleRuns[0]['text'] as String? ?? 'Unknown Artist';
              }

              String cover = '';
              final thumbnails = renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
              if (thumbnails != null && thumbnails.isNotEmpty) {
                cover = thumbnails.last['url'] as String? ?? '';
              }

              if (videoId != null && videoId.isNotEmpty) {
                final song = Song(
                  id: videoId,
                  title: title,
                  artistId: artist,
                  albumId: 'Single',
                  duration: DurationValue(Duration.zero),
                  thumbnail: Artwork(cover),
                  artwork: Artwork(cover),
                  sourceId: id,
                );
                _songCache[song.id] = song;
                songs.add(song);
              } else if (browseId != null && browseId.isNotEmpty) {
                if (browseId.startsWith('PL') || browseId.startsWith('VL') || browseId.startsWith('RD')) {
                  playlists.add(Playlist(
                    id: browseId,
                    title: title,
                    description: 'YouTube Playlist',
                    cover: Artwork(cover),
                    owner: artist,
                    songIds: const [],
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ));
                } else if (browseId.startsWith('MPREb_') || browseId.contains('album') || browseId.contains('release')) {
                  albums.add(Album(
                    id: browseId,
                    title: title,
                    artistId: artist,
                    cover: Artwork(cover),
                    year: 2026,
                    trackCount: 10,
                    duration: DurationValue(const Duration(minutes: 40)),
                  ));
                }
              }
            } catch (_) {}
          }
          node.values.forEach(traverse);
        } else if (node is List) {
          node.forEach(traverse);
        }
      }

      traverse(json);

      if (songs.isEmpty) {
        try {
          final songResults = await _ytClient.search.searchContent('trending songs', filter: yt.TypeFilters.video).timeout(const Duration(seconds: 10));
          songs.addAll(songResults.whereType<yt.SearchVideo>().map((v) {
            final song = Song(
              id: v.id.value,
              title: v.title,
              artistId: v.author,
              albumId: 'yt_album_unknown',
              duration: DurationValue(_parseDuration(v.duration)),
              thumbnail: Artwork(v.thumbnails.isNotEmpty ? v.thumbnails.first.url.toString() : ''),
              artwork: Artwork(v.thumbnails.isNotEmpty ? v.thumbnails.last.url.toString() : ''),
              sourceId: id,
            );
            _songCache[song.id] = song;
            return song;
          }).take(6));
        } catch (_) {}
      }

      print('[HOME] Models created');
      return HomeFeed(
        sections: [
          HomeFeedSection(
            title: 'Recommended for You',
            type: 'recommended',
            items: songs.take(10).toList(),
          ),
          HomeFeedSection(
            title: 'Trending Albums',
            type: 'albums',
            items: albums.take(10).toList(),
          ),
          HomeFeedSection(
            title: 'Featured Playlists',
            type: 'playlists',
            items: playlists.take(10).toList(),
          ),
        ],
      );
    } catch (e, stack) {
      DALogger.error('YouTubeMusicAdapter: Failed to load Home Feed, entering fallback search', e, stack);
      try {
        DALogger.info('YouTubeMusicAdapter: Fallback query searchContent("trending songs") started...');
        final songResults = await _ytClient.search.searchContent('trending songs', filter: yt.TypeFilters.video).timeout(const Duration(seconds: 8));
        DALogger.info('YouTubeMusicAdapter: Fallback query finished, fetched ${songResults.length} videos.');
        final songs = songResults.whereType<yt.SearchVideo>().map((v) {
          final song = Song(
            id: v.id.value,
            title: v.title,
            artistId: v.author,
            albumId: 'yt_album_unknown',
            duration: DurationValue(_parseDuration(v.duration)),
            thumbnail: Artwork(v.thumbnails.isNotEmpty ? v.thumbnails.first.url.toString() : ''),
            artwork: Artwork(v.thumbnails.isNotEmpty ? v.thumbnails.last.url.toString() : ''),
            sourceId: id,
          );
          _songCache[song.id] = song;
          return song;
        }).take(6).toList();

        return HomeFeed(
          sections: [
            HomeFeedSection(title: 'Recommended for You', type: 'recommended', items: songs),
            HomeFeedSection(title: 'Trending Albums', type: 'albums', items: const []),
            HomeFeedSection(title: 'Featured Playlists', type: 'playlists', items: const []),
          ],
        );
      } catch (_) {
        throw SourceException('Failed to load Home Feed: $e', e.toString());
      }
    }
  }

  @override
  Future<Album> getAlbum(String id) async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Loading metadata for Album ID: "$id"');

    try {
      final details = await _fetchPlaylistDetails(id);
      
      for (final song in details.songs) {
        _songCache[song.id] = song;
      }

      Duration totalDuration = Duration.zero;
      for (final s in details.songs) {
        totalDuration += s.duration.value;
      }

      int year = DateTime.now().year;
      final regex = RegExp(r'\b(19\d\d|20\d\d)\b');
      final match = regex.firstMatch(details.playlist.description) ?? regex.firstMatch(details.playlist.owner);
      if (match != null) {
        year = int.parse(match.group(0)!);
      }

      return Album(
        id: details.playlist.id,
        title: details.playlist.title,
        artistId: details.playlist.owner,
        cover: details.playlist.cover,
        year: year,
        trackCount: details.songs.length,
        duration: DurationValue(totalDuration),
      );
    } catch (e) {
      DALogger.warning('YouTubeMusicAdapter: InnerTube browse failed for Album ID: "$id". Trying fallback. Error: $e');
      try {
        return await _getAlbumFallback(id);
      } catch (fallbackErr, fallbackStack) {
        DALogger.error('YouTubeMusicAdapter: Fallback failed to retrieve album metadata for ID: "$id"', fallbackErr, fallbackStack);
        throw SourceException('Failed to retrieve album metadata: $fallbackErr', fallbackErr.toString());
      }
    }
  }

  int _parseSubscriberCount(String? text) {
    if (text == null) return 0;
    final cleaned = text.toUpperCase().replaceAll(RegExp(r'[^0-9.KMB]'), '');
    if (cleaned.isEmpty) return 0;

    try {
      double value;
      if (cleaned.endsWith('M')) {
        value = double.parse(cleaned.substring(0, cleaned.length - 1)) * 1000000;
      } else if (cleaned.endsWith('K')) {
        value = double.parse(cleaned.substring(0, cleaned.length - 1)) * 1000;
      } else if (cleaned.endsWith('B')) {
        value = double.parse(cleaned.substring(0, cleaned.length - 1)) * 1000000000;
      } else {
        value = double.parse(cleaned);
      }
      return value.toInt();
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<Artist> getArtist(String id) async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Loading Channel details and shelves for Artist ID: "$id"');

    try {
      final client = HttpClient();
      const apiKey = 'AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI';
      final url = Uri.parse('https://music.youtube.com/youtubei/v1/browse?key=$apiKey');
      
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      
      final payload = {
        'browseId': id,
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20260707.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        }
      };

      request.write(json.encode(payload));
      final responseObj = await request.close();
      final rawBody = await responseObj.transform(utf8.decoder).join();
      final response = json.decode(rawBody) as Map<String, dynamic>;

      if (response['error'] != null) {
        throw SourceException('InnerTube browse error: ${json.encode(response['error'])}');
      }

      String title = 'Unknown Artist';
      String subCountText = '';
      String? coverUrl;
      String description = '';

      if (response['header'] != null) {
        final header = response['header'];
        final headerRenderer = header['musicVisualHeaderRenderer'] ?? header['musicHeaderRenderer'] ?? header['musicImmersiveHeaderRenderer'];
        if (headerRenderer != null) {
          title = headerRenderer['title']?['runs']?[0]?['text'] ?? 'Unknown Artist';
          subCountText = headerRenderer['subscriptionButton']?['subscribeButtonRenderer']?['subscriberCountWithText']?['runs']?[0]?['text'] ?? 
                         headerRenderer['subscriptionButton']?['subscribeButtonRenderer']?['subscriberCountText']?['runs']?[0]?['text'] ??
                         headerRenderer['subtitle']?['runs']?[0]?['text'] ?? '';
          
          final thumbs = headerRenderer['foregroundThumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List? ??
                         headerRenderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
          if (thumbs != null && thumbs.isNotEmpty) {
            coverUrl = thumbs.last['url'] as String?;
          }
        }
      }

      final songs = <Song>[];
      final albums = <Album>[];
      final singles = <Album>[];
      final playlists = <Playlist>[];
      final related = <Artist>[];

      final contents = response['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
      if (contents != null) {
        for (final section in contents) {
          final shelf = section['musicShelfRenderer'];
          final carousel = section['musicCarouselShelfRenderer'];
          final descShelf = section['musicDescriptionShelfRenderer'];

          if (shelf != null) {
            final sectionTitle = shelf['title']?['runs']?[0]?['text'] as String? ?? '';
            if (sectionTitle.toLowerCase() == 'top songs' || sectionTitle.toLowerCase() == 'songs') {
              final items = shelf['contents'] as List?;
              if (items != null) {
                for (final itemContainer in items) {
                  final item = itemContainer['musicResponsiveListItemRenderer'];
                  if (item == null) continue;

                  final trackTitle = item['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text'] as String? ?? 'Unknown Title';
                  final videoId = item['playlistItemData']?['videoId'] as String? ??
                                  item['onTap']?['watchEndpoint']?['videoId'] as String?;
                  if (videoId == null) continue;

                  final artistRuns = item['flexColumns']?[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
                  final trackArtist = artistRuns != null && artistRuns.isNotEmpty 
                      ? artistRuns.map((r) => r['text']).join('') 
                      : title;



                  final cached = _songCache[videoId];
                  if (cached != null && cached.duration.value > Duration.zero) {
                    songs.add(cached);
                    continue;
                  }
                  final durationRuns = item['fixedColumns']?[0]?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs'] as List?;
                  final durationStr = durationRuns != null && durationRuns.isNotEmpty ? durationRuns[0]['text'] as String : '';
                  Duration duration = _parseDurationString(durationStr);
                  if (duration == Duration.zero) {
                    duration = _extractDurationFromFlexColumns(item['flexColumns'] as List?);
                  }

                  final cleanAlbum = _extractAlbumNameFromFlexColumns(item) ?? 'Single';
                  final song = _mapToSong(
                    id: videoId,
                    rawTitle: trackTitle,
                    rawArtist: trackArtist,
                    duration: duration,
                    albumId: cleanAlbum,
                    channelId: id,
                  );
                  songs.add(song);
                  _songCache[song.id] = song;
                }
              }
            }
          } else if (carousel != null) {
            final sectionTitle = carousel['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs']?[0]?['text'] as String? ?? '';
            final items = carousel['contents'] as List?;
            if (items != null) {
              for (final itemContainer in items) {
                final item = itemContainer['musicTwoRowItemRenderer'];
                if (item == null) continue;

                final itemTitle = item['title']?['runs']?[0]?['text'] as String? ?? 'Unknown';
                final browseId = item['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
                if (browseId == null) continue;

                final itemThumbs = item['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
                final thumbUrl = itemThumbs != null && itemThumbs.isNotEmpty ? itemThumbs.last['url'] as String : (coverUrl ?? '');

                final subtitle = item['subtitle']?['runs']?[0]?['text'] as String?;

                int year = DateTime.now().year;
                if (subtitle != null) {
                  final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(subtitle);
                  if (match != null) {
                    year = int.parse(match.group(0)!);
                  }
                }

                if (sectionTitle.toLowerCase() == 'albums') {
                  albums.add(Album(
                    id: browseId,
                    title: itemTitle,
                    artistId: title,
                    cover: Artwork(thumbUrl),
                    year: year,
                    trackCount: 10,
                    duration: DurationValue(const Duration(minutes: 40)),
                  ));
                } else if (sectionTitle.toLowerCase() == 'singles & eps' || sectionTitle.toLowerCase() == 'singles') {
                  singles.add(Album(
                    id: browseId,
                    title: itemTitle,
                    artistId: title,
                    cover: Artwork(thumbUrl),
                    year: year,
                    trackCount: 1,
                    duration: DurationValue(const Duration(minutes: 4)),
                  ));
                } else if (sectionTitle.toLowerCase().contains('playlists')) {
                  playlists.add(Playlist(
                    id: browseId,
                    title: itemTitle,
                    description: 'Playlist by $title',
                    cover: Artwork(thumbUrl),
                    owner: subtitle ?? title,
                    songIds: const [],
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ));
                } else if (sectionTitle.toLowerCase().contains('fans') || sectionTitle.toLowerCase().contains('like')) {
                  related.add(Artist(
                    id: browseId,
                    name: itemTitle,
                    image: Artwork(thumbUrl),
                    subscriberCount: 0,
                    description: 'Similar Artist',
                    genres: const [],
                  ));
                }
              }
            }
          } else if (descShelf != null) {
            final runs = descShelf['description']?['runs'] as List?;
            if (runs != null) {
              description = runs.map((r) => r['text']).join('');
            }
          }
        }
      }

      // Save into adapter local caches
      _artistSongs[id] = songs;
      _artistAlbums[id] = albums;
      _artistSingles[id] = singles;
      _artistPlaylists[id] = playlists;
      _artistRelated[id] = related;

      return Artist(
        id: id,
        name: title,
        image: Artwork(coverUrl ?? ''),
        subscriberCount: _parseSubscriberCount(subCountText),
        description: description.isNotEmpty ? description : 'Official YouTube Channel catalog',
        genres: const [],
      );
    } catch (e, stack) {
      DALogger.error('YouTubeMusicAdapter: Failed to retrieve artist details for ID: "$id"', e, stack);
      try {
        final channel = await _ytClient.channels.get(id).timeout(const Duration(seconds: 10));
        return Artist(
          id: channel.id.value,
          name: channel.title,
          image: Artwork(channel.logoUrl),
          subscriberCount: 0,
          description: 'Official YouTube Channel catalog',
          genres: const [],
        );
      } catch (fallbackErr, fallbackStack) {
        DALogger.error('YouTubeMusicAdapter: Fallback failed to retrieve artist for ID: "$id"', fallbackErr, fallbackStack);
        throw SourceException('Failed to retrieve artist: $fallbackErr', fallbackErr.toString());
      }
    }
  }

  @override
  Future<Playlist> getPlaylist(String id) async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Loading playlist tracks for ID: "$id"');

    try {
      final details = await _fetchPlaylistDetails(id);
      
      for (final song in details.songs) {
        _songCache[song.id] = song;
      }

      return details.playlist;
    } catch (e, st) {
      // ignore: avoid_print
      print('6. Parsed title: N/A (EXCEPTION THROWN BEFORE PLAYLIST CREATION)');
      // ignore: avoid_print
      print('7. Parsed owner: N/A (EXCEPTION THROWN BEFORE PLAYLIST CREATION)');
      // ignore: avoid_print
      print('8. Parsed track count: N/A (EXCEPTION THROWN BEFORE PLAYLIST CREATION)');
      // ignore: avoid_print
      print('9. Any exception and full stack trace:');
      // ignore: avoid_print
      print('   EXCEPTION: $e');
      // ignore: avoid_print
      print('   STACK TRACE:\n$st');
      // ignore: avoid_print
      print('================ PLAYLIST OPENING FLOW LOG END ==================\n');
      rethrow;
    }
  }

  @override
  Future<Song> getSong(String id) async {
    _checkInitialized();
    final cached = _songCache[id];
    if (cached != null && cached.duration.value > Duration.zero) {
      DALogger.info('YouTubeMusicAdapter: Reusing cached video metadata for Song ID: "$id"');
      return cached;
    }

    DALogger.info('YouTubeMusicAdapter: Loading video metadata for Song ID: "$id"');

    try {
      final video = await _ytClient.videos.get(id).timeout(const Duration(seconds: 10));
      final song = _mapToSong(
        id: video.id.value,
        rawTitle: video.title,
        rawArtist: video.author,
        duration: video.duration ?? Duration.zero,
        channelId: video.channelId.value,
      );
      _songCache[id] = song;
      return song;
    } catch (e, stack) {
      DALogger.error('YouTubeMusicAdapter: Failed to retrieve video metadata for ID: "$id"', e, stack);
      throw SourceException('Failed to retrieve song metadata: $e', e.toString());
    }
  }

  @override
  Future<Lyrics> getLyrics(String id) async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Resolving captions for Lyrics ID: "$id"');

    try {
      final manifest = await _ytClient.videos.closedCaptions.getManifest(id).timeout(const Duration(seconds: 10));
      if (manifest.tracks.isNotEmpty) {
        final track = manifest.tracks.first;
        final captions = await _ytClient.videos.closedCaptions.get(track).timeout(const Duration(seconds: 10));
        final lines = captions.captions.map((c) => c.text).join('\n');
        return Lyrics(
          songId: id,
          plainLyrics: lines,
          syncedLyrics: null,
          language: track.language.code,
          provider: 'youtube_captions',
        );
      }
    } catch (_) {
      // Return plain captions description if captions resolution fails
    }

    return Lyrics(
      songId: id,
      plainLyrics: 'Lyrics are unavailable for this song.',
      syncedLyrics: null,
      language: 'en',
      provider: 'musixmatch_fallback',
    );
  }

  @override
  Future<List<Song>> getRelated(String id) async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Loading related tracks for ID: "$id"');

    try {
      final video = await _ytClient.videos.get(id).timeout(const Duration(seconds: 10));
      final related = await _ytClient.videos.getRelatedVideos(video).timeout(const Duration(seconds: 10));
      if (related != null) {
        return related.map((v) {
          final song = Song(
            id: v.id.value,
            title: v.title,
            artistId: v.author,
            albumId: 'yt_album_unknown',
            duration: DurationValue(v.duration ?? Duration.zero),
            thumbnail: Artwork(v.thumbnails.lowResUrl),
            artwork: Artwork(v.thumbnails.highResUrl),
            sourceId: this.id,
          );
          _songCache[song.id] = song;
          return song;
        }).toList();
      }
    } catch (e, stack) {
      DALogger.error('YouTubeMusicAdapter: Failed to retrieve related videos for ID: "$id"', e, stack);
    }
    return const [];
  }

  @override
  Future<List<Song>> getRecommendations(String id) => getRelated(id);

  String _cleanQuery(String artist, String title) {
    final cleanArtist = artist.replaceAll(' - Topic', '').replaceAll('VEVO', '').trim();
    final cleanTitle = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    return '$cleanArtist $cleanTitle'.trim();
  }

  yt.SearchVideo? rankFallbackCandidates({
    required List<yt.SearchVideo> candidates,
    required String originalId,
    required String originalTitle,
    required String originalArtist,
    required String originalAlbum,
    required Duration originalDuration,
  }) {
    if (candidates.isEmpty) return null;

    final scored = <({yt.SearchVideo video, int score, String reasons})>[];

    final normOrigTitle = originalTitle.toLowerCase().replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    final normOrigArtist = originalArtist.toLowerCase().replaceAll(' - topic', '').replaceAll('vevo', '').trim();
    
    final origArtistParts = normOrigArtist.split(RegExp(r'[,&]|\b(feat|ft|and)\b')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final bool origIsRemix = normOrigTitle.contains('remix');

    for (final c in candidates) {
      if (c.id.value == originalId) continue;

      int score = 0;
      final reasons = <String>[];

      // 1. Artist Matching
      final normAuthor = c.author.toLowerCase().replaceAll(' - topic', '').replaceAll('vevo', '').trim();
      final candArtistParts = normAuthor.split(RegExp(r'[,&]|\b(feat|ft|and)\b')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      
      bool exactArtist = false;
      bool partialArtist = false;

      for (final op in origArtistParts) {
        for (final cp in candArtistParts) {
          if (op == cp) {
            exactArtist = true;
            break;
          }
          if (op.contains(cp) || cp.contains(op)) {
            partialArtist = true;
          }
        }
        if (exactArtist) break;
      }

      if (exactArtist) {
        score += 2000;
        reasons.add('Exact artist match (+2000)');
      } else if (partialArtist) {
        score += 1000;
        reasons.add('Partial artist match (+1000)');
      } else if (c.title.toLowerCase().contains(normOrigArtist)) {
        score += 500;
        reasons.add('Artist in title match (+500)');
      } else {
        score -= 5000;
        reasons.add('Different artist penalty (-5000)');
      }

      // Reject completely if no artist overlap is present to prevent wrong artist substitutions
      if (!exactArtist && !partialArtist && !c.title.toLowerCase().contains(normOrigArtist)) {
        continue;
      }

      // 2. Song Title Match
      final cleanCandTitle = c.title.toLowerCase().replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
      final normCandTitle = cleanCandTitle.replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normOrigTitleClean = normOrigTitle.replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]'), '');

      if (normCandTitle == normOrigTitleClean) {
        score += 2000;
        reasons.add('Exact title match (+2000)');
      } else if (normCandTitle.contains(normOrigTitleClean) || normOrigTitleClean.contains(normCandTitle)) {
        score += 1000;
        reasons.add('Partial title match (+1000)');
      } else {
        continue; // Title completely different
      }

      // 3. Remix/Cover/Karaoke/Instrumental penalties
      final bool candIsRemix = cleanCandTitle.contains('remix');
      if (candIsRemix && !origIsRemix) {
        score -= 3000;
        reasons.add('Unofficial Remix penalty (-3000)');
      }
      
      final bool candIsCover = cleanCandTitle.contains('cover') || cleanCandTitle.contains('tribute');
      if (candIsCover && !normOrigTitle.contains('cover')) {
        score -= 3000;
        reasons.add('Cover version penalty (-3000)');
      }

      final bool candIsKaraoke = cleanCandTitle.contains('karaoke') || cleanCandTitle.contains('instrumental');
      if (candIsKaraoke && !normOrigTitle.contains('karaoke') && !normOrigTitle.contains('instrumental')) {
        score -= 3000;
        reasons.add('Karaoke/Instrumental penalty (-3000)');
      }

      final bool candIsLyricsOrFan = cleanCandTitle.contains('lyrics') || cleanCandTitle.contains('lyric video') || cleanCandTitle.contains('fan-made') || cleanCandTitle.contains('unofficial');
      if (candIsLyricsOrFan) {
        score -= 1000;
        reasons.add('Unofficial/Lyrics video penalty (-1000)');
      }

      // 4. Album Match (if available)
      if (originalAlbum != 'yt_album_unknown' && originalAlbum.isNotEmpty) {
        final normAlbum = originalAlbum.toLowerCase().trim();
        final candidateText = '${c.title} ${c.author}'.toLowerCase();
        if (candidateText.contains(normAlbum)) {
          score += 800;
          reasons.add('Album match (+800)');
        }
      }

      // 5. Strict Duration Matching
      final diff = _parseDuration(c.duration).inSeconds - originalDuration.inSeconds;
      if (diff.abs() <= 3) {
        score += 1200;
        reasons.add('Duration matches within ±3s (+1200)');
      } else if (diff.abs() <= 8) {
        score += 600;
        reasons.add('Duration matches within ±8s (+600)');
      } else if (diff.abs() > 30) {
        score -= 1500;
        reasons.add('Duration mismatch >30s penalty (-1500)');
      } else if (diff.abs() > 15) {
        score -= 800;
        reasons.add('Duration mismatch >15s penalty (-800)');
      }

      // 6. Official upload checks
      if (c.author.endsWith(' - Topic')) {
        score += 1500;
        reasons.add('Official YT Music Topic channel (+1500)');
      } else if (c.author.toLowerCase().contains('official') || c.title.toLowerCase().contains('official')) {
        score += 500;
        reasons.add('Official artist/video upload (+500)');
      }

      scored.add((video: c, score: score, reasons: reasons.join(', ')));
    }

    if (scored.isEmpty) return null;

    scored.sort((a, b) => b.score.compareTo(a.score));

    DALogger.info('=== FALLBACK CANDIDATE RANKING FOR "$originalTitle" by "$originalArtist" ===');
    for (final s in scored) {
      DALogger.info('  - Candidate [${s.video.id.value}] "${s.video.title}" by "${s.video.author}": Score = ${s.score} (Reasons: ${s.reasons})');
    }
    DALogger.info('  -> Selected candidate: [${scored.first.video.id.value}] "${scored.first.video.title}" with score ${scored.first.score}');
    DALogger.info('========================================================================');

    if (scored.first.score < 400) {
      DALogger.info('YouTubeMusicAdapter: Selected fallback candidate has low score (${scored.first.score}). Aborting fallback to prevent wrong song playback.');
      return null;
    }

    return scored.first.video;
  }

  static const yt.YoutubeApiClient _visionosClient = yt.YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'gl': 'US',
        'utcOffsetMinutes': 0,
      }
    }
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  @override
  Future<AudioStream> getAudioStream(String id) async {
    _checkInitialized();
    DALogger.info('YouTubeMusicAdapter: Resolving audio stream for ID: "$id"');

    if (id.startsWith('mock_') || id == '1' || id == '2' || id == '3') {
      return AudioStream(
        id: id,
        providerId: this.id,
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        mimeType: 'audio/mp3',
        bitrate: 128000,
        duration: Duration.zero,
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
        headers: const {},
        quality: 'highest',
        codec: 'mp3',
        isLive: false,
        isCached: false,
      );
    }

    // 1. Determine if this is a Topic track (official audio track) and store metadata
    String? fallbackQuery;
    String? originalTitle;
    String? originalArtist;
    String? originalAlbum;
    Duration originalDuration = Duration.zero;

    final cached = _songCache[id];
    if (cached != null) {
      originalTitle = cached.title;
      originalArtist = cached.artistId;
      originalAlbum = cached.albumId;
      originalDuration = cached.duration.value;
      fallbackQuery = _cleanQuery(originalArtist, originalTitle);
    } else {
      try {
        final video = await _ytClient.videos.get(id).timeout(const Duration(seconds: 10));
        originalTitle = video.title;
        originalArtist = video.author;
        originalAlbum = 'yt_album_unknown';
        originalDuration = video.duration ?? Duration.zero;
        fallbackQuery = _cleanQuery(video.author, video.title);
      } catch (_) {}
    }

    // 2. Direct resolution (Always attempt first to play original ID)
    try {
      final manifest = await _ytClient.videos.streamsClient.getManifest(
        id,
        ytClients: [
          _visionosClient,
          yt.YoutubeApiClient.android,
          yt.YoutubeApiClient.androidSdkless,
        ],
      ).timeout(const Duration(milliseconds: 15000));
      
      var audioStreams = manifest.audioOnly.where((s) => s.container.name == 'mp4').toList();
      if (audioStreams.isEmpty) {
        audioStreams = manifest.audioOnly.toList();
      }
      final audioStreamInfo = audioStreams.withHighestBitrate();
      final streamUrl = audioStreamInfo.url.toString();

      // Bypassed synchronous _isStreamPlayable pre-flight check to enable instant stream URL resolution.
      // Any unplayable/forbidden stream URLs will be caught and resolved dynamically by the audio player.

      return AudioStream(
        id: id,
        providerId: this.id,
        streamUrl: streamUrl,
        mimeType: 'audio/${audioStreamInfo.codec.subtype}',
        bitrate: audioStreamInfo.bitrate.bitsPerSecond,
        duration: originalDuration,
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
        headers: const {},
        quality: 'highest',
        codec: audioStreamInfo.codec.subtype,
        isLive: false,
        isCached: false,
      );
    } catch (e) {
      DALogger.info('YouTubeMusicAdapter: Direct stream resolution failed for ID "$id": $e. Attempting search fallback as last resort...');
      
      if (fallbackQuery != null) {
        try {
          DALogger.info('YouTubeMusicAdapter: Searching fallback for: "$fallbackQuery"');
          final searchResults = await _ytClient.search.searchContent(fallbackQuery).timeout(const Duration(seconds: 10));
          final candidates = searchResults.whereType<yt.SearchVideo>().toList();
          final fallbackVideo = rankFallbackCandidates(
            candidates: candidates,
            originalId: id,
            originalTitle: originalTitle ?? '',
            originalArtist: originalArtist ?? '',
            originalAlbum: originalAlbum ?? 'yt_album_unknown',
            originalDuration: originalDuration,
          );

          if (fallbackVideo != null) {
            final fallbackId = fallbackVideo.id.value;
            final manifest = await _ytClient.videos.streamsClient.getManifest(
              fallbackId,
              ytClients: [
                _visionosClient,
                yt.YoutubeApiClient.android,
                yt.YoutubeApiClient.androidSdkless,
              ],
            ).timeout(const Duration(milliseconds: 15000));

            var audioStreams = manifest.audioOnly.where((s) => s.container.name == 'mp4').toList();
            if (audioStreams.isEmpty) {
              audioStreams = manifest.audioOnly.toList();
            }
            final audioStreamInfo = audioStreams.withHighestBitrate();

            DALogger.info('YouTubeMusicAdapter: Resolved fallback stream successfully for ID "$id" via "$fallbackId"');
            return AudioStream(
              id: id, // Must return the original ID
              providerId: this.id,
              streamUrl: audioStreamInfo.url.toString(),
              mimeType: 'audio/${audioStreamInfo.codec.subtype}',
              bitrate: audioStreamInfo.bitrate.bitsPerSecond,
              duration: originalDuration,
              expiresAt: DateTime.now().add(const Duration(hours: 4)),
              headers: const {},
              quality: 'highest',
              codec: audioStreamInfo.codec.subtype,
              isLive: false,
              isCached: false,
            );
          }
        } catch (err, stack) {
          DALogger.error('YouTubeMusicAdapter: Fallback resolution failed for query "$fallbackQuery"', err, stack);
        }
      }
      
      throw SourceException('Failed to resolve audio stream for ID "$id": $e', e.toString());
    }
  }

  Future<bool> _isStreamPlayable(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
      request.headers.set('Range', 'bytes=0-0');
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      final response = await request.close().timeout(const Duration(seconds: 5));
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (e) {
      DALogger.warning('YouTubeMusicAdapter: _isStreamPlayable check failed: $e');
    } finally {
      client.close();
    }
    return false;
  }
  Future<({Playlist playlist, List<Song> songs})> _fetchPlaylistDetails(String id) async {
    final client = HttpClient();
    try {
      String? cookies;
      try {
        final prefs = await SharedPreferences.getInstance();
        cookies = prefs.getString('ytm_cookies');
        if (cookies == null || cookies.trim().isEmpty) {
          cookies = await SecureCredentialStore().readCookies();
        }
      } catch (e) {
        DALogger.warning('YouTubeMusicAdapter: Failed to load cookies (likely running in a test environment without bindings): $e');
      }

      const apiKey = 'AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI';

      print('[ID VERIFICATION LOG]');
      print('1. Original ID from UI: "$id"');
      print('2. Length of original ID: ${id.length}');

      String targetBrowseId = id;
      String transformationNotice = 'None';

      if (id == 'VLLM' || id == 'LM' || id == 'FEmusic_liked_videos') {
        targetBrowseId = 'FEmusic_liked_videos';
        transformationNotice = 'Mapped $id -> FEmusic_liked_videos for authenticated Liked Songs';
      } else if (id.startsWith('PL')) {
        targetBrowseId = 'VL$id';
        transformationNotice = 'Prepended VL prefix ($id -> VL$id)';
      }

      print('3. Transformations applied: $transformationNotice | Final targetBrowseId: "$targetBrowseId" (Length: ${targetBrowseId.length})');

      if (id.startsWith('RD') || id.startsWith('VLRD')) {
        final url = Uri.parse('https://music.youtube.com/youtubei/v1/next?key=$apiKey');
        final request = await client.postUrl(url);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        if (cookies != null && cookies.isNotEmpty) {
          request.headers.set('Cookie', cookies);
          final cookiesMap = <String, String>{};
          for (final cookie in cookies.split(';')) {
            final parts = cookie.trim().split('=');
            if (parts.length >= 2) {
              cookiesMap[parts[0]] = parts.sublist(1).join('=');
            }
          }
          final sapisid = cookiesMap['SAPISID'] ?? cookiesMap['__Secure-3PAPISID'];
          if (sapisid != null && sapisid.isNotEmpty) {
            final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final origin = 'https://music.youtube.com';
            final input = '$timestamp $sapisid $origin';
            final sha1Hex = sha1.convert(utf8.encode(input)).toString();
            request.headers.set('Authorization', 'SAPISIDHASH ${timestamp}_$sha1Hex');
            request.headers.set('X-Origin', origin);
          }
        }

        final payload = {
          'playlistId': id,
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20260707.01.00',
              'hl': 'en',
              'gl': 'US',
            }
          }
        };

        request.write(json.encode(payload));
        final response = await request.close().timeout(const Duration(seconds: 10));
        final rawBody = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
        final body = json.decode(rawBody) as Map<String, dynamic>;

        if (body['error'] != null) {
          throw SourceException('InnerTube next error: ${json.encode(body['error'])}');
        }

        List? panelItems;
        final playlistPanel = body['contents']?['twoColumnWatchNextResults']?['playlist']?['playlistPanelRenderer'] as Map<String, dynamic>?;
        if (playlistPanel != null && playlistPanel['contents'] is List) {
          panelItems = playlistPanel['contents'] as List;
        } else {
          void findPanel(dynamic node) {
            if (panelItems != null) return;
            if (node is Map) {
              if (node.containsKey('playlistPanelRenderer')) {
                final panel = node['playlistPanelRenderer'];
                if (panel is Map && panel['contents'] is List) {
                  panelItems = panel['contents'] as List;
                  return;
                }
              }
              for (final v in node.values) {
                findPanel(v);
              }
            } else if (node is List) {
              for (final item in node) {
                findPanel(item);
              }
            }
          }
          findPanel(body);
        }

        final songs = <Song>[];
        int rawItemCount = panelItems != null ? panelItems!.length : 0;
        int discardedCount = 0;
        String discardReason = '';

        if (panelItems != null) {
          for (final rawItem in panelItems!) {
            final videoRenderer = (rawItem['playlistPanelVideoRenderer'] ?? rawItem['playlistPanelVideoWrapperRenderer']?['primaryRenderer']?['playlistPanelVideoRenderer']) as Map<String, dynamic>?;
            if (videoRenderer == null) {
              discardedCount++;
              discardReason = 'rawItem["playlistPanelVideoRenderer"] was null (keys present: ${rawItem.keys.toList()})';
              continue;
            }

            final videoId = videoRenderer['videoId'] as String? ??
                videoRenderer['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
            if (videoId == null || videoId.isEmpty) {
              discardedCount++;
              discardReason = 'videoId was null or empty in playlistPanelVideoRenderer';
              continue;
            }

            final titleRuns = videoRenderer['title']?['runs'] as List?;
            final trackTitle = titleRuns != null && titleRuns.isNotEmpty ? titleRuns[0]['text'] as String : (videoRenderer['title']?['simpleText'] as String? ?? 'Unknown Track');

            final artistRuns = videoRenderer['longBylineText']?['runs'] ?? videoRenderer['shortBylineText']?['runs'] as List?;
            String trackArtist = artistRuns != null && artistRuns.isNotEmpty ? (artistRuns as List).map((r) => r['text']).join('') : 'YouTube Music';

            final durationRuns = videoRenderer['lengthText']?['runs'] as List?;
            final durationStr = durationRuns != null && durationRuns.isNotEmpty ? durationRuns[0]['text'] as String : (videoRenderer['lengthText']?['simpleText'] as String? ?? '');

            final itemThumbs = videoRenderer['thumbnail']?['thumbnails'] as List?;
            final thumbUrl = itemThumbs != null && itemThumbs.isNotEmpty ? itemThumbs.last['url'] as String : '';

            final cached = _songCache[videoId];
            if (cached != null) {
              songs.add(cached);
              continue;
            }

            final runs = (videoRenderer['longBylineText'] ?? videoRenderer['shortBylineText'])?['runs'] as List?;
            String? rendererChannelId;
            if (runs != null && runs.isNotEmpty) {
              rendererChannelId = runs[0]['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
            }

            final song = _mapToSong(
              id: videoId,
              rawTitle: trackTitle,
              rawArtist: trackArtist,
              duration: _parseDurationString(durationStr),
              albumId: 'Radio Mix',
              channelId: rendererChannelId,
            );
            songs.add(song);
            _songCache[song.id] = song;
          }
        }

        print('================ PARSING STAGE INSTRUMENTATION ================');
        print('1. HTTP status: ${response.statusCode}');
        print('2. Response type: VLRD / Radio Mix WatchNextResponse');
        print('3. Number of raw playlist items found in the response: $rawItemCount');
        print('4. Number of Track objects created: ${songs.length}');
        if (rawItemCount > 0 && songs.isEmpty) {
          print('5. Mapping function discarded items: YES - Reason: $discardReason');
        } else if (rawItemCount == 0) {
          print('6. JSON path searched: body.contents.twoColumnWatchNextResults.playlist.playlistPanelRenderer.contents | Actual top-level keys in response: ${body.keys.toList()}');
        }
        print('================================================================');

        final playlistObj = Playlist(
          id: id,
          title: 'Radio Mix',
          description: 'Automix Playlist',
          cover: Artwork(songs.isNotEmpty ? songs.first.artwork.url : ''),
          owner: 'YouTube Music',
          songIds: songs.map((s) => s.id).toList(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        return (playlist: playlistObj, songs: songs);
      }

      final url = Uri.parse('https://music.youtube.com/youtubei/v1/browse?key=$apiKey');
      
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      if (cookies != null && cookies.isNotEmpty) {
        request.headers.set('Cookie', cookies);
        final cookiesMap = <String, String>{};
        for (final cookie in cookies.split(';')) {
          final parts = cookie.trim().split('=');
          if (parts.length >= 2) {
            cookiesMap[parts[0]] = parts.sublist(1).join('=');
          }
        }
        final sapisid = cookiesMap['SAPISID'] ?? cookiesMap['__Secure-3PAPISID'];
        if (sapisid != null && sapisid.isNotEmpty) {
          final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final origin = 'https://music.youtube.com';
          final input = '$timestamp $sapisid $origin';
          final sha1Hex = sha1.convert(utf8.encode(input)).toString();
          request.headers.set('Authorization', 'SAPISIDHASH ${timestamp}_$sha1Hex');
          request.headers.set('X-Origin', origin);
        }
      }
      
      final payload = {
        'browseId': targetBrowseId,
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20260707.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        }
      };

      final reqBodyStr = json.encode(payload);
      request.write(reqBodyStr);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final rawBody = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      final body = json.decode(rawBody) as Map<String, dynamic>;

      final sentCookie = request.headers.value('Cookie');
      final sentAuth = request.headers.value('Authorization');
      final bool isSignInPage = rawBody.contains('messageRenderer') || rawBody.contains('Sign in');
      final bool isRealPlaylist = rawBody.contains('musicPlaylistShelfRenderer') || rawBody.contains('musicResponsiveListItemRenderer') || rawBody.contains('twoColumnBrowseResultsRenderer') || rawBody.contains('singleColumnBrowseResultsRenderer');

      print('================ AUTHENTICATION VERIFICATION LOG ================');
      print('1. Cookie header sent: ${sentCookie != null ? (sentCookie.length > 20 ? "${sentCookie.substring(0, 20)}... (Length: ${sentCookie.length})" : sentCookie) : "ABSENT"}');
      print('2. Authorization (SAPISIDHASH) header sent: ${sentAuth != null ? (sentAuth.length > 30 ? "${sentAuth.substring(0, 30)}..." : sentAuth) : "ABSENT"}');
      print('3. HTTP status: ${response.statusCode}');
      print('4. Response Content Analysis: ${isSignInPage ? "SIGN-IN REQUIRED / MESSAGE RENDERER" : (isRealPlaylist ? "REAL PLAYLIST RESPONSE" : "OTHER RESPONSE")}');
      print('==================================================================');

      if (body['error'] != null) {
        throw SourceException('InnerTube browse error: ${json.encode(body['error'])}');
      }

      final contents = (body['contents'] as Map<String, dynamic>?) ?? body;
      final browseResults = ((contents['twoColumnBrowseResultsRenderer'] ??
                             contents['singleColumnBrowseResultsRenderer']) as Map<String, dynamic>?) ?? contents;

      String title = '';
      String author = '';
      String description = '';
      String coverUrl = '';

      final microTitle = body['microformat']?['microformatDataRenderer']?['title'] as String?;
      if (microTitle != null && microTitle.trim().isNotEmpty) {
        title = microTitle.trim();
      }

      dynamic headerRenderer;
      for (final raw in [body['header'], browseResults['header']]) {
        if (raw == null) continue;
        dynamic candidate = raw;
        if (candidate is Map && candidate.containsKey('musicEditableHeaderRenderer')) {
          candidate = candidate['musicEditableHeaderRenderer']?['header'];
        }
        if (candidate is Map) {
          headerRenderer = candidate['musicResponsiveHeaderRenderer'] ??
                           candidate['musicDetailHeaderRenderer'] ??
                           candidate['musicAlbumReleaseDetailHeaderRenderer'] ??
                           candidate['musicVisualHeaderRenderer'] ??
                           candidate['musicHeaderRenderer'];
          if (headerRenderer != null) break;
        }
      }

      final tabs = browseResults['tabs'] as List?;
      List? tabContents;
      if (tabs != null && tabs.isNotEmpty) {
        tabContents = tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
        if (headerRenderer == null && tabContents != null && tabContents.isNotEmpty) {
          for (final item in tabContents) {
            dynamic candidate = item;
            if (candidate is Map && candidate.containsKey('musicEditableHeaderRenderer')) {
              candidate = candidate['musicEditableHeaderRenderer']?['header'];
            }
            if (candidate is Map) {
              headerRenderer = candidate['musicResponsiveHeaderRenderer'] ??
                               candidate['musicDetailHeaderRenderer'] ??
                               candidate['musicAlbumReleaseDetailHeaderRenderer'] ??
                               candidate['musicVisualHeaderRenderer'] ??
                               candidate['musicHeaderRenderer'];
              if (headerRenderer != null) break;
            }
          }
        }
      }

      if (headerRenderer != null) {
        final parsedTitle = headerRenderer['title']?['runs']?[0]?['text'] ??
                            headerRenderer['title']?['simpleText'];
        if (parsedTitle != null && parsedTitle.toString().trim().isNotEmpty) {
          title = parsedTitle.toString().trim();
        }

        final subtitleRuns = (headerRenderer['subtitle']?['runs'] ??
                              headerRenderer['byline']?['runs'] ??
                              headerRenderer['straplineTextOne']?['runs']) as List?;
        if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
          author = subtitleRuns.map((r) => r['text']).join('');
        } else if (headerRenderer['subtitle']?['simpleText'] != null) {
          author = headerRenderer['subtitle']['simpleText'] as String;
        } else if (headerRenderer['byline']?['simpleText'] != null) {
          author = headerRenderer['byline']['simpleText'] as String;
        } else if (headerRenderer['straplineTextOne']?['simpleText'] != null) {
          author = headerRenderer['straplineTextOne']['simpleText'] as String;
        }

        final descRenderer = headerRenderer['description']?['musicDescriptionShelfRenderer'] as Map<String, dynamic>?;
        if (descRenderer != null) {
          final runs = descRenderer['description']?['runs'] as List?;
          if (runs != null) {
            description = runs.map((r) => r['text']).join('');
          }
        }

        final thumbList = (headerRenderer['foregroundThumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                           headerRenderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                           headerRenderer['thumbnail']?['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                           headerRenderer['croppedSquareThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                           headerRenderer['thumbnail']?['thumbnails']) as List?;
        if (thumbList != null && thumbList.isNotEmpty) {
          coverUrl = thumbList.last['url'] ?? '';
        }
      }

      List? trackItems;
      String jsonPathSearched = 'contents.twoColumnBrowseResultsRenderer.secondaryContents.sectionListRenderer.contents[0].musicPlaylistShelfRenderer.contents';
      
      final secondaryList = browseResults['secondaryContents']?['sectionListRenderer']?['contents'] as List?;
      if (secondaryList != null && secondaryList.isNotEmpty) {
        for (final sec in secondaryList) {
          final shelf = sec['musicPlaylistShelfRenderer'] ?? sec['musicShelfRenderer'];
          if (shelf != null && shelf['contents'] != null) {
            trackItems = shelf['contents'] as List?;
            if (trackItems != null && trackItems.isNotEmpty) break;
          }
        }
      }

      if ((trackItems == null || trackItems.isEmpty) && tabContents != null && tabContents.isNotEmpty) {
        jsonPathSearched += ' -> contents.twoColumnBrowseResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents[0].musicPlaylistShelfRenderer.contents';
        for (final item in tabContents) {
          final shelf = item['musicPlaylistShelfRenderer'] ?? item['musicShelfRenderer'];
          if (shelf != null && shelf['contents'] != null) {
            trackItems = shelf['contents'] as List?;
            if (trackItems != null && trackItems.isNotEmpty) break;
          }
        }
      }

      if (trackItems == null || trackItems.isEmpty) {
        jsonPathSearched += ' -> recursive findShelf(contents)';
        void findShelf(dynamic node) {
          if (trackItems != null && trackItems!.isNotEmpty) return;
          if (node is Map) {
            if (node.containsKey('musicPlaylistShelfRenderer')) {
              final shelf = node['musicPlaylistShelfRenderer'];
              if (shelf is Map && shelf['contents'] is List) {
                trackItems = shelf['contents'] as List;
                return;
              }
            }
            if (node.containsKey('musicShelfRenderer')) {
              final shelf = node['musicShelfRenderer'];
              if (shelf is Map && shelf['contents'] is List) {
                trackItems = shelf['contents'] as List;
                return;
              }
            }
            for (final v in node.values) {
              findShelf(v);
            }
          } else if (node is List) {
            for (final item in node) {
              findShelf(item);
            }
          }
        }
        findShelf(contents);
      }
      
      final songs = <Song>[];
      final items = trackItems;
      int rawItemCount = items != null ? items.length : 0;
      int discardedCount = 0;
      String discardReason = '';

      if (items != null && items.isNotEmpty) {
        for (final trackItem in items) {
          final item = (trackItem['musicResponsiveListItemRenderer'] ??
                        trackItem['playlistVideoRenderer'] ??
                        trackItem['musicMultiFlexListItemRenderer'] ??
                        trackItem['musicTwoRowItemRenderer'] ??
                        trackItem['playlistPanelVideoRenderer']) as Map<String, dynamic>?;
          if (item == null) {
            discardedCount++;
            discardReason = 'trackItem renderer was null (keys present: ${trackItem.keys.toList()})';
            continue;
          }

          final videoId = item['videoId'] as String? ??
              item['playlistItemData']?['videoId'] as String? ??
              item['onTap']?['watchEndpoint']?['videoId'] as String? ??
              item['navigationEndpoint']?['watchEndpoint']?['videoId'] as String? ??
              item['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] as String? ??
              (item['flexColumns'] as List?)?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;

          if (videoId == null || videoId.isEmpty) {
            discardedCount++;
            discardReason = 'videoId extracted was null or empty';
            continue;
          }

          final titleRuns = (item['title']?['runs'] ??
                             item['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']) as List?;
          final trackTitle = titleRuns != null && titleRuns.isNotEmpty 
              ? titleRuns[0]['text'] as String 
              : (item['title']?['simpleText'] as String? ?? 'Unknown Track');

          final artistRuns = (item['longBylineText']?['runs'] ??
                              item['shortBylineText']?['runs'] ??
                              item['flexColumns']?[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']) as List?;
          String trackArtist = artistRuns != null && artistRuns.isNotEmpty ? artistRuns.map((r) => r['text']).join('') : '';
          if (trackArtist.trim().isEmpty || trackArtist.toLowerCase() == 'unknown artist') {
            if (author.isNotEmpty) {
              final parts = author.split(' • ');
              String resolved = '';
              for (final part in parts) {
                final p = part.trim();
                if (p.isEmpty ||
                    p.toLowerCase() == 'album' ||
                    p.toLowerCase() == 'playlist' ||
                    p.toLowerCase() == 'ep' ||
                    p.toLowerCase() == 'single' ||
                    RegExp(r'^\d+$').hasMatch(p) ||
                    p.contains('songs') ||
                    p.contains('minutes')) {
                  continue;
                }
                resolved = p;
                break;
              }
              trackArtist = resolved.isNotEmpty ? resolved : parts.first.trim();
            } else {
              trackArtist = 'Unknown Artist';
            }
          }

          final durationRuns = (item['lengthText']?['runs'] ??
                                item['fixedColumns']?[0]?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']) as List?;
          final durationStr = durationRuns != null && durationRuns.isNotEmpty 
              ? durationRuns[0]['text'] as String 
              : (item['lengthText']?['simpleText'] as String? ?? '');
          
          Duration duration = _parseDurationString(durationStr);
          if (duration == Duration.zero) {
            duration = _extractDurationFromFlexColumns(item['flexColumns'] as List?);
          }

          final itemThumbs = (item['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                              item['thumbnail']?['thumbnails']) as List?;
          final thumbUrl = itemThumbs != null && itemThumbs.isNotEmpty ? itemThumbs.last['url'] as String : coverUrl;

          final cached = _songCache[videoId];
          if (cached != null && cached.duration.value > Duration.zero) {
            songs.add(cached);
            continue;
          }
          final String cleanAlbum;
          if (id.startsWith('MPREb_') || id.startsWith('OLAK5uy_')) {
            cleanAlbum = title.isNotEmpty ? title : 'Single';
          } else {
            cleanAlbum = _extractAlbumNameFromFlexColumns(item) ?? 'Single';
          }

          final rendererChannelId = _extractChannelIdFromListItem(item);
          final song = _mapToSong(
            id: videoId,
            rawTitle: trackTitle,
            rawArtist: trackArtist,
            duration: duration,
            albumId: cleanAlbum,
            channelId: rendererChannelId,
          );
          songs.add(song);
          _songCache[song.id] = song;
        }
      }

      String cleanOwner = '';
      if (author.isNotEmpty) {
        final parts = author.split(' • ');
        for (final part in parts) {
          final p = part.trim();
          if (p.isEmpty ||
              p.toLowerCase() == 'album' ||
              p.toLowerCase() == 'playlist' ||
              p.toLowerCase() == 'ep' ||
              p.toLowerCase() == 'single' ||
              RegExp(r'^\d+$').hasMatch(p) ||
              p.contains('songs') ||
              p.contains('minutes') ||
              p.contains('likes')) {
            continue;
          }
          cleanOwner = p;
          break;
        }
        if (cleanOwner.isEmpty) {
          cleanOwner = parts.first.trim();
        }
      }

      if (title.trim().isEmpty) {
        if (id == 'VLLM' || id == 'LM' || id == 'FEmusic_liked_videos') {
          title = 'Liked Songs';
        } else if (songs.isNotEmpty && songs.first.albumId.isNotEmpty && songs.first.albumId != 'Single') {
          title = songs.first.albumId;
        } else if (songs.isNotEmpty && songs.first.artistId.isNotEmpty && songs.first.artistId != 'Unknown Artist') {
          title = '${songs.first.artistId} Mix';
        } else {
          title = 'YouTube Music Playlist';
        }
      }

      if (cleanOwner.isEmpty || cleanOwner.toLowerCase() == 'album' || cleanOwner.toLowerCase() == 'playlist') {
        if (songs.isNotEmpty && songs.first.artistId.isNotEmpty && songs.first.artistId != 'Unknown Artist') {
          cleanOwner = songs.first.artistId;
        } else {
          cleanOwner = 'YouTube Music';
        }
      }

      if (coverUrl.isEmpty && songs.isNotEmpty) {
        coverUrl = songs.first.artwork.url;
      }

      print('================ ANDROID / WINDOWS PLAYLIST INSTRUMENTATION ================');
      print('1. HTTP status: ${response.statusCode}');
      print('2. browseId used: "$targetBrowseId" (Original ID: "$id")');
      print('3. Response type: BrowseResponse');
      print('4. Number of raw playlist items found: $rawItemCount');
      print('5. Number of Track objects created: ${songs.length}');
      print('6. Exact JSON path searched: $jsonPathSearched');
      print('7. Actual JSON path containing tracks: ${rawItemCount > 0 ? "shelf.contents (musicResponsiveListItemRenderer)" : "None found"}');
      print('8. Any platform-specific differences: Operating System: ${Platform.operatingSystem} | Version: ${Platform.operatingSystemVersion} | Client User-Agent: ${request.headers.value('User-Agent')} | Cookies present: ${cookies != null && cookies.isNotEmpty}');
      print('=============================================================================');

      final playlistObj = Playlist(
        id: id,
        title: title,
        description: description,
        cover: Artwork(coverUrl),
        owner: cleanOwner,
        songIds: songs.map((s) => s.id).toList(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      return (playlist: playlistObj, songs: songs);
    } finally {
      client.close();
    }
  }


  Future<Album> _getAlbumFallback(String id) async {
    final playlist = await _ytClient.playlists.get(id).timeout(const Duration(seconds: 10));
    final videos = await _ytClient.playlists.getVideos(playlist.id).toList().timeout(const Duration(seconds: 10));

    Duration totalDuration = Duration.zero;
    for (final v in videos) {
      totalDuration += v.duration ?? Duration.zero;
    }

    int year = DateTime.now().year;
    final regex = RegExp(r'\b(19\d\d|20\d\d)\b');
    final match = regex.firstMatch(playlist.description);
    if (match != null) {
      year = int.parse(match.group(0)!);
    }

    final songsList = videos.map((v) {
      // ignore: avoid_print
      print('Original Provider Track (fallback):');
      // ignore: avoid_print
      print('  Title: ${v.title}');
      // ignore: avoid_print
      print('  Track ID: ${v.id.value}');
      // ignore: avoid_print
      print('  Provider ID: youtube_music');
      // ignore: avoid_print
      print('  Source ID: youtube_music');
      // ignore: avoid_print
      print('  Duration: ${v.duration}');
      // ignore: avoid_print
      print('  Artwork: ${v.thumbnails.highResUrl}');

      String trackArtist = v.author;
      if (trackArtist.trim().isEmpty || trackArtist.toLowerCase() == 'unknown artist') {
        trackArtist = playlist.author.isNotEmpty ? playlist.author : 'Unknown Artist';
      }
      return Song(
        id: v.id.value,
        title: v.title,
        artistId: trackArtist,
        albumId: playlist.title.isNotEmpty ? playlist.title : 'Single',
        duration: DurationValue(v.duration ?? Duration.zero),
        thumbnail: Artwork(v.thumbnails.lowResUrl),
        artwork: Artwork(v.thumbnails.highResUrl),
        sourceId: this.id,
      );
    }).toList();

    for (final song in songsList) {
      _songCache[song.id] = song;
    }

    return Album(
      id: playlist.id.value,
      title: playlist.title,
      artistId: playlist.author,
      cover: Artwork(playlist.thumbnails.highResUrl),
      year: year,
      trackCount: playlist.videoCount ?? videos.length,
      duration: DurationValue(totalDuration),
    );
  }

  Future<Playlist> _getPlaylistFallback(String id) async {
    final cleanId = id.startsWith('VLPL') || id.startsWith('VLRD') ? id.substring(2) : (id.startsWith('VL') ? id.substring(2) : id);
    final fallbackYt = yt.YoutubeExplode();
    try {
      final playlist = await fallbackYt.playlists.get(cleanId);
      final videos = await fallbackYt.playlists.getVideos(playlist.id).toList();

      final songsList = videos.map((v) {
        // ignore: avoid_print
        print('Original Provider Track (fallback):');
        // ignore: avoid_print
        print('  Title: ${v.title}');
        // ignore: avoid_print
        print('  Track ID: ${v.id.value}');
        // ignore: avoid_print
        print('  Provider ID: youtube_music');
        // ignore: avoid_print
        print('  Source ID: youtube_music');
        // ignore: avoid_print
        print('  Duration: ${v.duration}');
        // ignore: avoid_print
        print('  Artwork: ${v.thumbnails.highResUrl}');

        final cached = _songCache[v.id.value];
        if (cached != null) {
          return cached;
        }
        String trackArtist = v.author;
        if (trackArtist.trim().isEmpty || trackArtist.toLowerCase() == 'unknown artist') {
          trackArtist = playlist.author.isNotEmpty ? playlist.author : 'Unknown Artist';
        }
        return _mapToSong(
          id: v.id.value,
          rawTitle: v.title,
          rawArtist: trackArtist,
          duration: v.duration ?? Duration.zero,
          albumId: 'Single',
          channelId: v.channelId.value,
        );
      }).toList();

      for (final song in songsList) {
        _songCache[song.id] = song;
      }

      return Playlist(
        id: playlist.id.value,
        title: playlist.title,
        description: playlist.description,
        cover: Artwork(playlist.thumbnails.highResUrl),
        owner: playlist.author,
        songIds: videos.map((v) => v.id.value).toList(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } finally {
      fallbackYt.close();
    }
  }

  ({String title, String artist}) _cleanTitleAndArtist(String rawTitle, String rawArtist) {
    String title = rawTitle;
    String artist = rawArtist;

    if (artist.contains(' • ')) {
      final parts = artist.split(' • ');
      artist = parts.first.trim();
    }

    title = title.replaceAll(RegExp(r'\s*\(?\s*Official\s*(?:Music\s*)?Video\s*\)?', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s*\[?\s*Official\s*(?:Music\s*)?Video\s*\]?', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s*\(?\s*Lyrics?\s*(?:Video)?\s*\)?', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s*\[?\s*Lyrics?\s*(?:Video)?\s*\]?', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s*\(?\s*Audio\s*\)?', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s*\[?\s*Audio\s*\]?', caseSensitive: false), '');
    title = title.trim();

    final splitMatch = RegExp(r'^(.+?)\s*-\s*(.+)$');
    final match = splitMatch.firstMatch(title);
    if (match != null) {
      final part1 = match.group(1)!.trim();
      final part2 = match.group(2)!.trim();
      
      final artistLower = artist.toLowerCase().trim();
      if (part2.toLowerCase().contains(artistLower) || 
          artistLower.contains(part2.toLowerCase()) ||
          artistLower.replaceAll(RegExp(r'\s+'), '').contains(part2.toLowerCase().replaceAll(RegExp(r'\s+'), ''))) {
        title = part1;
        artist = part2;
      } else if (part1.toLowerCase().contains(artistLower) ||
                 artistLower.contains(part1.toLowerCase())) {
        artist = part1;
        title = part2;
      }
    }

    artist = artist.replaceAll(RegExp(r'VEVO$', caseSensitive: false), '');
    artist = artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    artist = artist.trim();

    if (artist.isEmpty) {
      artist = 'Unknown Artist';
    }

    return (title: title, artist: artist);
  }

  String? _extractChannelIdFromListItem(Map<String, dynamic> item) {
    final flexColumns = item['flexColumns'] as List?;
    if (flexColumns == null) return null;
    for (final column in flexColumns) {
      final runs = column['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
      if (runs == null) continue;
      for (final run in runs) {
        final pageType = run['navigationEndpoint']?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'] as String?;
        if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
          final browseId = run['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
          if (browseId != null && browseId.isNotEmpty) {
            return browseId;
          }
        }
      }
    }
    return null;
  }

  Song _mapToSong({
    required String id,
    required String rawTitle,
    required String rawArtist,
    required Duration duration,
    String albumId = 'yt_album_unknown',
    String? channelId,
  }) {
    if (channelId != null) {
      videoChannelIdMap[id] = channelId;
    }
    videoAuthorMap[id] = rawArtist;
    final cleaned = _cleanTitleAndArtist(rawTitle, rawArtist);
    return Song(
      id: id,
      title: cleaned.title,
      artistId: cleaned.artist,
      albumId: albumId,
      duration: DurationValue(duration),
      thumbnail: Artwork('https://i.ytimg.com/vi/$id/mqdefault.jpg'),
      artwork: Artwork('https://i.ytimg.com/vi/$id/hqdefault.jpg'),
      sourceId: this.id,
    );
  }

  String? _extractAlbumNameFromFlexColumns(Map<String, dynamic> item) {
    final flexColumns = item['flexColumns'] as List?;
    if (flexColumns == null) return null;
    for (final column in flexColumns) {
      final runs = column['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List?;
      if (runs == null) continue;
      for (final run in runs) {
        final pageType = run['navigationEndpoint']?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'] as String?;
        if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
          final text = run['text'] as String?;
          if (text != null && text.isNotEmpty) {
            return text;
          }
        }
      }
    }
    return null;
  }
}

class InterceptingClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final urlStr = request.url.toString();
    if (urlStr.contains('youtubei/v1/search') || urlStr.contains('results?search_query=')) {
      final bytes = await response.stream.toBytes();
      var body = utf8.decode(bytes);
      body = body.replaceAll('"viewCountText":{"runs":', '"viewCountText":{"simpleText":"0 views","_runs":');
      final modifiedBytes = utf8.encode(body);
      
      final headers = Map<String, String>.from(response.headers);
      headers.remove('content-encoding');
      headers['content-length'] = modifiedBytes.length.toString();

      return http.StreamedResponse(
        Stream.value(modifiedBytes),
        response.statusCode,
        contentLength: modifiedBytes.length,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
