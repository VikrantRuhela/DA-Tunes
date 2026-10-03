// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 DA Tunes Contributors
// Licensed under GPL-3.0.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../../shared/models/music_models.dart';
import 'session_manager.dart';
import 'logger_service.dart';

class AuthenticatedClient extends http.BaseClient {
  final String cookies;
  final http.Client _inner = http.Client();

  AuthenticatedClient(this.cookies);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Cookie'] = cookies;
    request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    request.headers['x-youtube-client-name'] = '67';
    request.headers['x-youtube-client-version'] = '1.20260304.03.00';
    request.headers['x-origin'] = 'https://music.youtube.com';
    request.headers['Content-Type'] = 'application/json';

    try {
      final Map<String, String> cookiesMap = {};
      for (final part in cookies.split(';')) {
        final idx = part.indexOf('=');
        if (idx == -1) continue;
        final key = part.substring(0, idx).trim();
        final val = part.substring(idx + 1).trim();
        cookiesMap[key] = val;
      }
      final sapisid = cookiesMap['SAPISID'] ?? cookiesMap['__Secure-3PAPISID'];
      if (sapisid != null) {
        final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        const origin = 'https://music.youtube.com';
        final input = '$timestamp $sapisid $origin';
        
        final bytes = utf8.encode(input);
        final digest = sha1.convert(bytes);
        final sha1Hex = digest.toString();
        
        request.headers['Authorization'] = 'SAPISIDHASH ${timestamp}_$sha1Hex';
      }
    } catch (_) {}

    print('DIAGNOSTIC REQUEST HEADERS: ${request.headers}');
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class YouTubeMusicAccountService {
  final SessionManager _sessionManager;

  bool get isLoggedIn => _sessionManager.isLoggedIn;
  String? get cookies => _sessionManager.cookies;
  AuthenticatedClient? get client => _sessionManager.client;

  static const String apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30";

  YouTubeMusicAccountService(this._sessionManager);

  Future<void> initialize() async {
    await _sessionManager.restoreSession();
  }

  Future<bool> login(String cookieHeader) async {
    return await _sessionManager.validateAndSaveSession(cookieHeader);
  }

  Future<void> logout() async {
    await _sessionManager.logout();
  }

  Future<Map<String, dynamic>?> _postBrowse(String browseId) async {
    if (!isLoggedIn || client == null) return null;

    try {
      final response = await client!.post(
        Uri.parse('https://music.youtube.com/youtubei/v1/browse?key=$apiKey&prettyPrint=false'),
        body: jsonEncode({
          "context": {
            "client": {
              "clientName": "WEB_REMIX",
              "clientVersion": "1.20260304.03.00",
              "hl": "en",
              "gl": "US"
            }
          },
          "browseId": browseId
        }),
      ).timeout(const Duration(seconds: 10));

      final bodyPreview = response.body.substring(0, response.body.length > 100 ? 100 : response.body.length);
      DALogger.info('YTM API Sync Request: browseId=$browseId, status=${response.statusCode}, size=${response.body.length} bytes, body_preview="$bodyPreview"');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      DALogger.error('YouTubeMusicAccountService: Failed browse post request for $browseId', e);
    }
    return null;
  }

  Future<List<Song>> fetchLikedSongs() async {
    final data = await _postBrowse("FEmusic_liked_videos");
    if (data == null) return const [];
    return _parseSongsFromInnerTube(data);
  }

  Future<List<Playlist>> fetchLibraryPlaylists() async {
    final corpusData = await _postBrowse("FEmusic_library_corpus_playlists");
    final likedData = await _postBrowse("FEmusic_liked_playlists");

    final List<Playlist> playlists = [];
    if (corpusData != null) {
      playlists.addAll(_parsePlaylistsFromInnerTube(corpusData));
    }
    if (likedData != null) {
      playlists.addAll(_parsePlaylistsFromInnerTube(likedData));
    }

    final Set<String> seenIds = {};
    final deduped = playlists.where((p) => seenIds.add(p.id)).toList();
    DALogger.info('YTM API Sync: Library Playlists merged. Created/Saved corpus + Liked. Total Count: ${deduped.length}');
    return deduped;
  }

  Future<List<Artist>> fetchLibraryArtists() async {
    final trackArtistsData = await _postBrowse("FEmusic_library_corpus_track_artists");
    final artistsData = await _postBrowse("FEmusic_library_corpus_artists");

    final List<Artist> artists = [];
    if (trackArtistsData != null) {
      artists.addAll(_parseArtistsFromInnerTube(trackArtistsData));
    }
    if (artistsData != null) {
      artists.addAll(_parseArtistsFromInnerTube(artistsData));
    }

    final Set<String> seenIds = {};
    final deduped = artists.where((a) => seenIds.add(a.id)).toList();
    DALogger.info('YTM API Sync: Library Artists merged. Total Count: ${deduped.length}');
    return deduped;
  }

  Future<List<Album>> fetchLibraryAlbums() async {
    final corpusData = await _postBrowse("FEmusic_library_corpus_albums");
    final likedData = await _postBrowse("FEmusic_liked_albums");

    final List<Album> albums = [];
    if (corpusData != null) {
      albums.addAll(_parseAlbumsFromInnerTube(corpusData));
    }
    if (likedData != null) {
      albums.addAll(_parseAlbumsFromInnerTube(likedData));
    }

    final Set<String> seenIds = {};
    final deduped = albums.where((a) => seenIds.add(a.id)).toList();
    DALogger.info('YTM API Sync: Library Albums merged. Total Count: ${deduped.length}');
    return deduped;
  }

  Future<List<Song>> fetchHistory() async {
    final data = await _postBrowse("FEmusic_history");
    if (data == null) return const [];
    return _parseSongsFromInnerTube(data);
  }

  Future<List<Song>> fetchPersonalizedRecommendations() async {
    final data = await _postBrowse("FEmusic_home");
    if (data == null) return const [];
    return _parseSongsFromInnerTube(data);
  }

  List<Song> _parseSongsFromInnerTube(Map<String, dynamic> json) {
    final List<Song> songs = [];

    void findSongs(dynamic node) {
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
              String album = 'Single';
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
                      album = runs[2]['text'] as String? ?? 'Single';
                    }
                  }
                }
              }

              String thumbnail = '';
              final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
              if (thumbnails != null && thumbnails.isNotEmpty) {
                thumbnail = thumbnails.last['url'] as String? ?? '';
              }

              duration = _extractDurationFromFlexColumns(flexColumns);

              songs.add(Song(
                id: videoId,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                artworkUrl: thumbnail,
                source: 'youtube_music',
                lyrics: null,
              ));
            }
          } catch (_) {}
        } else if (node.containsKey('musicTwoRowItemRenderer')) {
          try {
            final renderer = node['musicTwoRowItemRenderer'];
            final videoId = renderer['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
            if (videoId != null && videoId.isNotEmpty) {
              final titleText = renderer['title']?['runs']?[0]?['text'] ??
                                renderer['title']?['simpleText'];
              final title = titleText as String? ?? 'Unknown Title';
              
              String artist = 'Unknown Artist';
              final subtitleRuns = renderer['subtitle']?['runs'] as List?;
              if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
                artist = subtitleRuns[0]['text'] as String? ?? 'Unknown Artist';
              }
              final duration = _extractDurationFromRuns(subtitleRuns);

              String thumbnail = '';
              final thumbnails = renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
              if (thumbnails != null && thumbnails.isNotEmpty) {
                thumbnail = thumbnails.last['url'] as String? ?? '';
              }

              songs.add(Song(
                id: videoId,
                title: title,
                artist: artist,
                album: 'Single',
                duration: duration,
                artworkUrl: thumbnail,
                source: 'youtube_music',
                lyrics: null,
              ));
            }
          } catch (_) {}
        }
        node.values.forEach(findSongs);
      } else if (node is List) {
        node.forEach(findSongs);
      }
    }

    findSongs(json);
    return songs;
  }

  List<Playlist> _parsePlaylistsFromInnerTube(Map<String, dynamic> json) {
    final List<Playlist> playlists = [];

    void findPlaylists(dynamic node) {
      if (node is Map) {
        if (node.containsKey('playlistRenderer') || node.containsKey('musicTwoRowItemRenderer')) {
          try {
            final renderer = node['playlistRenderer'] ?? node['musicTwoRowItemRenderer'];
            final String? playlistId = renderer['playlistId'] ?? 
                renderer['navigationEndpoint']?['browseEndpoint']?['browseId'];
            
            if (playlistId != null && playlistId.isNotEmpty && (playlistId.startsWith('PL') || playlistId.startsWith('VL') || playlistId.startsWith('RD'))) {
              final titleText = renderer['title']?['runs']?[0]?['text'] ??
                  renderer['title']?['simpleText'] ?? 'Library Playlist';

              playlists.add(Playlist(
                id: playlistId,
                name: titleText,
                songs: const [],
              ));
            }
          } catch (_) {}
        } else if (node.containsKey('musicResponsiveListItemRenderer')) {
          try {
            final renderer = node['musicResponsiveListItemRenderer'];
            final browseId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
            if (browseId != null && (browseId.startsWith('PL') || browseId.startsWith('VL') || browseId.startsWith('RD'))) {
              String titleText = 'Library Playlist';
              final flexColumns = renderer['flexColumns'] as List?;
              if (flexColumns != null && flexColumns.isNotEmpty) {
                final runs = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List?;
                if (runs != null && runs.isNotEmpty) {
                  titleText = runs[0]['text'] as String? ?? 'Library Playlist';
                }
              }
              playlists.add(Playlist(
                id: browseId,
                name: titleText,
                songs: const [],
              ));
            }
          } catch (_) {}
        }
        node.values.forEach(findPlaylists);
      } else if (node is List) {
        node.forEach(findPlaylists);
      }
    }

    findPlaylists(json);
    return playlists;
  }

  List<Artist> _parseArtistsFromInnerTube(Map<String, dynamic> json) {
    final List<Artist> artists = [];

    void findArtists(dynamic node) {
      if (node is Map) {
        if (node.containsKey('artistRenderer') || node.containsKey('musicTwoRowItemRenderer')) {
          try {
            final renderer = node['artistRenderer'] ?? node['musicTwoRowItemRenderer'];
            final String? artistId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'];
            
            if (artistId != null && artistId.isNotEmpty && (artistId.startsWith('UC') || artistId.contains('FEmusic_library_corpus_artist'))) {
              final titleText = renderer['title']?['runs']?[0]?['text'] ??
                  renderer['title']?['simpleText'] ?? 'Library Artist';

              String cover = '';
              final thumbnails = (renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                  renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']) as List?;
              if (thumbnails != null && thumbnails.isNotEmpty) {
                cover = thumbnails.last['url'] as String? ?? '';
              }

              artists.add(Artist(
                id: artistId,
                name: titleText,
                artworkUrl: cover,
              ));
            }
          } catch (_) {}
        } else if (node.containsKey('musicResponsiveListItemRenderer')) {
          try {
            final renderer = node['musicResponsiveListItemRenderer'];
            final browseId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
            if (browseId != null && (browseId.startsWith('UC') || browseId.contains('FEmusic_library_corpus_artist'))) {
              String name = 'Library Artist';
              final flexColumns = renderer['flexColumns'] as List?;
              if (flexColumns != null && flexColumns.isNotEmpty) {
                final runs = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List?;
                if (runs != null && runs.isNotEmpty) {
                  name = runs[0]['text'] as String? ?? 'Library Artist';
                }
              }
              String cover = '';
              final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
              if (thumbnails != null && thumbnails.isNotEmpty) {
                cover = thumbnails.last['url'] as String? ?? '';
              }
              artists.add(Artist(
                id: browseId,
                name: name,
                artworkUrl: cover,
              ));
            }
          } catch (_) {}
        }
        node.values.forEach(findArtists);
      } else if (node is List) {
        node.forEach(findArtists);
      }
    }

    findArtists(json);
    return artists;
  }

  List<Album> _parseAlbumsFromInnerTube(Map<String, dynamic> json) {
    final List<Album> albums = [];

    void findAlbums(dynamic node) {
      if (node is Map) {
        if (node.containsKey('albumRenderer') || node.containsKey('musicTwoRowItemRenderer')) {
          try {
            final renderer = node['albumRenderer'] ?? node['musicTwoRowItemRenderer'];
            final String? albumId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] ??
                renderer['title']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId'];
            
            if (albumId != null && albumId.isNotEmpty && (albumId.startsWith('MPREb_') || albumId.contains('album') || albumId.contains('release') || albumId.contains('FEmusic_library_corpus_album'))) {
              final titleText = renderer['title']?['runs']?[0]?['text'] ??
                  renderer['title']?['simpleText'] ?? 'Library Album';

              String artist = 'Unknown Artist';
              final subtitleRuns = renderer['subtitle']?['runs'] as List?;
              if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
                artist = subtitleRuns[0]['text'] as String? ?? 'Unknown Artist';
              }

              String cover = '';
              final thumbnails = (renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                  renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']) as List?;
              if (thumbnails != null && thumbnails.isNotEmpty) {
                cover = thumbnails.last['url'] as String? ?? '';
              }

              albums.add(Album(
                id: albumId,
                name: titleText,
                artist: artist,
                artworkUrl: cover,
                songs: const [],
              ));
            }
          } catch (_) {}
        } else if (node.containsKey('musicResponsiveListItemRenderer')) {
          try {
            final renderer = node['musicResponsiveListItemRenderer'];
            final browseId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
            if (browseId != null && (browseId.startsWith('MPREb_') || browseId.contains('album') || browseId.contains('release') || browseId.contains('FEmusic_library_corpus_album'))) {
              String titleText = 'Library Album';
              String artist = 'Unknown Artist';
              
              final flexColumns = renderer['flexColumns'] as List?;
              if (flexColumns != null && flexColumns.isNotEmpty) {
                final runs = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List?;
                if (runs != null && runs.isNotEmpty) {
                  titleText = runs[0]['text'] as String? ?? 'Library Album';
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

              albums.add(Album(
                id: browseId,
                name: titleText,
                artist: artist,
                artworkUrl: cover,
                songs: const [],
              ));
            }
          } catch (_) {}
        }
        node.values.forEach(findAlbums);
      } else if (node is List) {
        node.forEach(findAlbums);
      }
    }

    findAlbums(json);
    return albums;
  }

  Duration _parseDurationString(String durationStr) {
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
    } catch (_) {}
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

  Future<Map<String, List<dynamic>>> fetchPersonalizedHomeSections() async {
    final Map<String, List<dynamic>> sections = {
      'songs': <Song>[],
      'albums': <Album>[],
      'playlists': <Playlist>[],
    };

    final data = await _postBrowse("FEmusic_home");
    if (data == null) return sections;

    int shelfCount = 0;
    int recommendationsShelvesCount = 0;

    void processContainer(Map container, String shelfTitle) {
      final items = container['contents'] ?? container['items'];
      if (items is! List) return;

      shelfCount++;
      final titleLower = shelfTitle.toLowerCase();
      final isRecShelf = titleLower.contains('recommend') || titleLower.contains('mix') || titleLower.contains('similar') || titleLower.contains('for you') || titleLower.contains('quick pick') || titleLower.contains('listen again');
      if (isRecShelf) {
        recommendationsShelvesCount++;
      }

      for (final item in items) {
        if (item is! Map) continue;

        if (item.containsKey('musicResponsiveListItemRenderer')) {
          final songsList = _parseSongsFromInnerTube({'contents': [item]});
          if (songsList.isNotEmpty) {
            sections['songs']!.addAll(songsList);
          }
        }
        else {
          final renderer = item['musicTwoRowItemRenderer'] ?? 
                           item['musicMultiRowListItemRenderer'] ?? 
                           item['playlistRenderer'] ?? 
                           item['albumRenderer'] ?? 
                           item;
          
          if (renderer is! Map) continue;

          final String? browseId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId'] ??
                                   renderer['title']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId'] ??
                                   renderer['playlistId'] ??
                                   renderer['navigationEndpoint']?['watchEndpoint']?['playlistId'];

          final videoId = renderer['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;

          if (videoId != null && videoId.isNotEmpty) {
            final titleText = renderer['title']?['runs']?[0]?['text'] ??
                              renderer['title']?['simpleText'] ?? 'Unknown Song';
            String artist = 'Unknown Artist';
            final subtitleRuns = renderer['subtitle']?['runs'] as List?;
            if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
              artist = subtitleRuns[0]['text'] as String? ?? 'Unknown Artist';
            }
            String thumbnail = '';
            final thumbnails = renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
            if (thumbnails != null && thumbnails.isNotEmpty) {
              thumbnail = thumbnails.last['url'] as String? ?? '';
            }

            sections['songs']!.add(Song(
              id: videoId,
              title: titleText,
              artist: artist,
              album: 'Single',
              duration: Duration.zero,
              artworkUrl: thumbnail,
              source: 'youtube_music',
              lyrics: null,
            ));
          } else if (browseId != null && browseId.isNotEmpty) {
            final titleText = renderer['title']?['runs']?[0]?['text'] ??
                              renderer['title']?['simpleText'] ?? 'Item';
            
            String subtitle = 'YouTube Music';
            final subtitleRuns = renderer['subtitle']?['runs'] as List?;
            if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
              subtitle = subtitleRuns[0]['text'] as String? ?? 'YouTube Music';
            }

            String thumbnail = '';
            final thumbnails = (renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
                                renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']) as List?;
            if (thumbnails != null && thumbnails.isNotEmpty) {
              thumbnail = thumbnails.last['url'] as String? ?? '';
            }

            if (browseId.startsWith('MPREb_') || browseId.contains('album') || browseId.contains('release') || titleLower.contains('album')) {
              sections['albums']!.add(Album(
                id: browseId,
                name: titleText,
                artist: subtitle,
                artworkUrl: thumbnail,
                songs: const [],
              ));
            } else {
              sections['playlists']!.add(Playlist(
                id: browseId,
                name: titleText,
                songs: const [],
              ));
            }
          }
        }
      }
    }

    void findContainers(dynamic node) {
      if (node is Map) {
        final carouselHeader = node['header']?['musicCarouselShelfBasicHeaderRenderer'];
        if (carouselHeader is Map) {
          final strapline = carouselHeader['strapline']?['runs']?[0]?['text'] as String?;
          if (strapline != null && strapline.isNotEmpty && !strapline.contains('YouTube') && strapline.length < 50) {
            _sessionManager.setAccountDetails(strapline, null);
          }
        }

        final title = node['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs']?[0]?['text'] as String? ??
                      node['header']?['musicShelfRenderer']?['title']?['runs']?[0]?['text'] as String? ??
                      node['title']?['runs']?[0]?['text'] as String? ??
                      node['title']?['simpleText'] as String? ?? '';

        if (node.containsKey('contents') && node['contents'] is List) {
          processContainer(node, title);
        } else if (node.containsKey('items') && node['items'] is List) {
          processContainer(node, title);
        }
        
        node.values.forEach(findContainers);
      } else if (node is List) {
        node.forEach(findContainers);
      }
    }

    findContainers(data);
    DALogger.info('YTM API Sync: Parsed personalized home sections. Total Shelves Returned: $shelfCount, Recommendations Shelves: $recommendationsShelvesCount, Songs: ${sections['songs']!.length}, Albums: ${sections['albums']!.length}, Playlists: ${sections['playlists']!.length}');
    return sections;
  }
}
