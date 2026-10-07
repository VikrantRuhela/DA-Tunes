import 'dart:async';
import 'source_adapter.dart';
import '../exceptions/playback_exceptions.dart';
import 'logger_service.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/home_feed.dart';
import '../../domain/entities/audio_stream.dart';

/// Singleton manager executing Pluggable Source Adapters with retry limits, rate queues and caches.
class SourceManager {
  final Map<String, MusicSourceAdapter> _adapters = {};
  final Map<String, dynamic> _cache = {};
  final Map<String, Future<dynamic>> _pendingRequests = {};
  String? _activeSourceId;

  static final SourceManager _instance = SourceManager._internal();
  factory SourceManager() => _instance;
  SourceManager._internal();

  String? get activeSourceId => _activeSourceId;

  MusicSourceAdapter get activeAdapter {
    if (_activeSourceId == null) {
      throw const SourceException('No music source adapter is selected');
    }
    final adapter = _adapters[_activeSourceId];
    if (adapter == null) {
      throw SourceException('Selected adapter "$_activeSourceId" is not registered');
    }
    return adapter;
  }

  void registerAdapter(MusicSourceAdapter adapter) {
    DALogger.info('Registering source adapter: ${adapter.name} (${adapter.id})');
    _adapters[adapter.id] = adapter;
  }

  Future<void> selectSource(String id) async {
    DALogger.info('Selecting active music source: $id');
    final adapter = _adapters[id];
    if (adapter == null) {
      throw SourceException('Cannot select unregistered source adapter: $id');
    }

    try {
      await adapter.initialize();
      _activeSourceId = id;
      clearCache();
    } catch (e, stack) {
      DALogger.error('ERROR initializing source adapter $id', e, stack);
      throw SourceException('Failed to select active music source: $id', e.toString());
    }
  }

  void clearCache() {
    _cache.clear();
    _pendingRequests.clear();
    DALogger.info('Source manager caches cleared.');
  }

  Future<T> _executeWithRetry<T>(Future<T> Function() action, {int retries = 2}) async {
    int attempts = 0;
    while (attempts <= retries) {
      try {
        return await action();
      } catch (e, stack) {
        attempts++;
        if (attempts > retries) {
          DALogger.error('Operation failed after $attempts attempts', e, stack);
          rethrow;
        }
        final errStr = e.toString().toLowerCase();
        int delayMs = 400 * attempts;
        if (errStr.contains('429') || errStr.contains('rate') || errStr.contains('too many')) {
          delayMs = 1500 * attempts;
        }
        final jitter = (DateTime.now().microsecond % 200);
        delayMs += jitter;
        DALogger.warning('Operation failed. Backing off for ${delayMs}ms (Attempt $attempts of $retries)');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw const SourceException('Operation failed after retries');
  }

  Future<T> _executeRequest<T>(String key, Future<T> Function() action, {int retries = 2}) async {
    if (_pendingRequests.containsKey(key)) {
      DALogger.info('Deduplicating identical request for key: $key');
      return await _pendingRequests[key] as T;
    }

    final future = _executeWithRetry(action, retries: retries).whenComplete(() {
      _pendingRequests.remove(key);
    });
    _pendingRequests[key] = future;
    return await future;
  }

  // Routing actions
  Future<SearchResult> search(String query) async {
    final cacheKey = 'search_$query';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as SearchResult;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.search(query), retries: 0);
    _cache[cacheKey] = result;
    return result;
  }

  Future<List<Artist>> searchArtists(String query) async {
    final cacheKey = 'search_artists_$query';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as List<Artist>;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.searchArtists(query), retries: 0);
    _cache[cacheKey] = result;
    return result;
  }

  Future<HomeFeed> getHome() async {
    const cacheKey = 'home_feed';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as HomeFeed;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getHome(), retries: 1);
    _cache[cacheKey] = result;
    return result;
  }

  Future<Album> getAlbum(String id) async {
    final cacheKey = 'album_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as Album;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getAlbum(id));
    _cache[cacheKey] = result;
    return result;
  }

  Future<Artist> getArtist(String id) async {
    final cacheKey = 'artist_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as Artist;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getArtist(id));
    _cache[cacheKey] = result;
    return result;
  }

  Future<Playlist> getPlaylist(String id) async {
    final cacheKey = 'playlist_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as Playlist;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getPlaylist(id));
    _cache[cacheKey] = result;
    return result;
  }

  Future<Song> getSong(String id) async {
    final cacheKey = 'song_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as Song;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getSong(id));
    _cache[cacheKey] = result;
    return result;
  }

  Future<Lyrics> getLyrics(String id) async {
    final cacheKey = 'lyrics_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as Lyrics;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getLyrics(id));
    _cache[cacheKey] = result;
    return result;
  }

  Future<List<Song>> getRelated(String id) async {
    final cacheKey = 'related_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as List<Song>;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getRelated(id));
    _cache[cacheKey] = result;
    return result;
  }

  Future<List<Song>> getRecommendations(String id) async {
    final cacheKey = 'recommendations_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as List<Song>;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getRecommendations(id));
    _cache[cacheKey] = result;
    return result;
  }

  Future<AudioStream> getAudioStream(String id) async {
    final cacheKey = 'stream_$id';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey] as AudioStream;
    }

    final result = await _executeRequest(cacheKey, () => activeAdapter.getAudioStream(id));
    _cache[cacheKey] = result;
    return result;
  }

  List<Song> getArtistSongs(String artistId) => activeAdapter.getArtistSongs(artistId);
  List<Album> getArtistAlbums(String artistId) => activeAdapter.getArtistAlbums(artistId);
  List<Album> getArtistSingles(String artistId) => activeAdapter.getArtistSingles(artistId);
  List<Playlist> getArtistPlaylists(String artistId) => activeAdapter.getArtistPlaylists(artistId);
  List<Artist> getArtistRelated(String artistId) => activeAdapter.getArtistRelated(artistId);

  Future<void> dispose() async {
    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }
    _adapters.clear();
    clearCache();
  }
}
