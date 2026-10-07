import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../shared/models/music_models.dart';
import 'stream_resolver.dart';
import 'local_stream_proxy.dart';
import 'logger_service.dart';
import 'network_identity.dart';

class PlaybackPrefetchManager {
  final StreamResolver _streamResolver;
  final LocalStreamProxy _proxy;
  
  final Map<String, HttpClientRequest> _activeDownloads = {};
  final Set<String> _promotedTrackIds = {};
  Timer? _prefetchDebounceTimer;
  
  static HttpClient? _sharedPrefetchClient;
  static HttpClient get _client => _sharedPrefetchClient ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4;

  List<Song> _currentQueue = [];
  int _currentIndex = -1;
  Song? _currentlyPlayingSong;
  bool _hasPromotedCurrentSong = false;
  bool isPermanentCacheEnabled = true;
  
  static const int prefetchWindowCount = 1;
  static const double promotionThreshold = 0.85;

  PlaybackPrefetchManager(this._streamResolver, this._proxy);

  List<Song> get currentQueue => _currentQueue;
  int get currentIndex => _currentIndex;

  /// Called whenever the queue or current song index changes.
  Future<void> updateQueue(List<Song> queue, int currentIndex) async {
    _currentQueue = List.from(queue);
    _currentIndex = currentIndex;
    
    final Song? newCurrentSong = (currentIndex >= 0 && currentIndex < queue.length)
        ? queue[currentIndex]
        : null;

    if (_currentlyPlayingSong?.id != newCurrentSong?.id) {
      _currentlyPlayingSong = newCurrentSong;
      _hasPromotedCurrentSong = false;
    }

    final upcomingSongIds = <String>[];
    if (currentIndex >= 0 && currentIndex < queue.length) {
      final nextIndex = currentIndex + 1;
      if (nextIndex < queue.length) {
        upcomingSongIds.add(queue[nextIndex].id);
      }
    }

    _cancelUnneededDownloads(upcomingSongIds);
    await _purgeObsoletePrefetchFiles(upcomingSongIds);
    
    _prefetchDebounceTimer?.cancel();
    if (upcomingSongIds.isNotEmpty) {
      _prefetchDebounceTimer = Timer(const Duration(milliseconds: 600), () {
        _startPrefetchForSongs(queue, currentIndex, upcomingSongIds);
      });
    }
  }

  Future<void> onPositionUpdate(Song? currentSong, Duration position) async {
    if (!isPermanentCacheEnabled) return;
    if (currentSong == null || currentSong.duration.inMilliseconds <= 0) return;
    if (_hasPromotedCurrentSong) return;

    final ratio = position.inMilliseconds / currentSong.duration.inMilliseconds;
    if (ratio >= promotionThreshold) {
      _hasPromotedCurrentSong = true;
      await promoteToCache(currentSong.id);
    }
  }

  Future<void> promoteToCache(String songId) async {
    if (!isPermanentCacheEnabled) {
      DALogger.info('PlaybackPrefetchManager: Permanent cache is disabled. Skipping promotion for "$songId".');
      return;
    }
    if (_promotedTrackIds.contains(songId)) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final prefetchDir = Directory(p.join(tempDir.path, 'da_tunes_prefetch'));
      final cacheDir = Directory(p.join(tempDir.path, 'da_tunes_cache'));

      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      final prefetchedFile = File(p.join(prefetchDir.path, '$songId.prefetch'));
      final cachedFile = File(p.join(cacheDir.path, '$songId.mp3'));

      if (prefetchedFile.existsSync()) {
        if (cachedFile.existsSync()) cachedFile.deleteSync();
        await prefetchedFile.rename(cachedFile.path);
        DALogger.info('PlaybackPrefetchManager: Promoted track "$songId" to permanent cache.');
      }

      final prefetchedArt = File(p.join(prefetchDir.path, '$songId.jpg'));
      final cachedArt = File(p.join(cacheDir.path, '$songId.jpg'));
      if (prefetchedArt.existsSync()) {
        if (cachedArt.existsSync()) cachedArt.deleteSync();
        await prefetchedArt.rename(cachedArt.path);
        DALogger.info('PlaybackPrefetchManager: Promoted artwork for "$songId" to permanent cache.');
      }

      _promotedTrackIds.add(songId);
      _proxy.manageCacheSize(cacheDir);
    } catch (e, stack) {
      DALogger.error('PlaybackPrefetchManager: Failed to promote track "$songId" to cache', e, stack);
    }
  }

  void _cancelUnneededDownloads(List<String> neededIds) {
    final neededSet = neededIds.toSet();
    final toCancel = _activeDownloads.keys.where((id) => !neededSet.contains(id)).toList();
    for (final id in toCancel) {
      final req = _activeDownloads.remove(id);
      req?.abort();
      DALogger.info('PlaybackPrefetchManager: Cancelled prefetch download for track "$id".');
    }
  }

  Future<void> _purgeObsoletePrefetchFiles(List<String> neededIds) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final prefetchDir = Directory(p.join(tempDir.path, 'da_tunes_prefetch'));
      if (!await prefetchDir.exists()) return;

      final neededSet = neededIds.toSet();
      if (_currentlyPlayingSong != null) {
        neededSet.add(_currentlyPlayingSong!.id);
      }

      await for (final entity in prefetchDir.list()) {
        if (entity is File) {
          final baseName = p.basenameWithoutExtension(entity.path);
          if (!neededSet.contains(baseName)) {
            try {
              await entity.delete();
              DALogger.info('PlaybackPrefetchManager: Purged obsolete prefetch file "${entity.path}".');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      DALogger.error('PlaybackPrefetchManager: Error purging obsolete prefetch files', e);
    }
  }

  Future<void> _startPrefetchForSongs(List<Song> queue, int currentIndex, List<String> upcomingIds) async {
    if (upcomingIds.isEmpty || _activeDownloads.isNotEmpty) return;
    final tempDir = await getTemporaryDirectory();
    final prefetchDir = Directory(p.join(tempDir.path, 'da_tunes_prefetch'));
    if (!await prefetchDir.exists()) {
      await prefetchDir.create(recursive: true);
    }
    final cacheDir = Directory(p.join(tempDir.path, 'da_tunes_cache'));

    final songId = upcomingIds.first;
    if (_activeDownloads.containsKey(songId)) return;

    final cachedFile = File(p.join(cacheDir.path, '$songId.mp3'));
    if (await cachedFile.exists()) return;

    final prefetchedFile = File(p.join(prefetchDir.path, '$songId.prefetch'));
    if (await prefetchedFile.exists()) return;

    final song = queue.firstWhere((s) => s.id == songId, orElse: () => queue[0]);
    _downloadPrefetchTask(song, prefetchDir);
  }

  Future<void> _downloadPrefetchTask(Song song, Directory prefetchDir) async {
    final songId = song.id;
    try {
      DALogger.info('PlaybackPrefetchManager: Starting background prefetch for "${song.title}" ($songId)');
      
      final stream = await _streamResolver.resolvePrefetch(
        trackId: songId,
        providerId: song.source,
        songTitle: song.title,
        artist: song.artist,
        duration: song.duration,
      );

      final targetUrl = stream.streamUrl.startsWith('http://127.0.0.1')
          ? Uri.parse(stream.streamUrl).queryParameters['url'] ?? stream.streamUrl
          : stream.streamUrl;

      final req = await _client.getUrl(Uri.parse(targetUrl));
      _activeDownloads[songId] = req;

      stream.headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('User-Agent', NetworkIdentity.platformUserAgent);

      final res = await req.close();
      if (res.statusCode != 200 && res.statusCode != 206) {
        _activeDownloads.remove(songId);
        return;
      }

      final tmpFile = File(p.join(prefetchDir.path, '$songId.prefetch.tmp'));
      final targetFile = File(p.join(prefetchDir.path, '$songId.prefetch'));
      if (tmpFile.existsSync()) tmpFile.deleteSync();

      final sink = tmpFile.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      if (tmpFile.existsSync()) {
        if (targetFile.existsSync()) targetFile.deleteSync();
        await tmpFile.rename(targetFile.path);
        DALogger.info('PlaybackPrefetchManager: Successfully prefetched "${song.title}" ($songId)');
      }

      if (song.artworkUrl != null && song.artworkUrl!.isNotEmpty) {
        _prefetchArtwork(songId, song.artworkUrl!, prefetchDir);
      }
    } catch (e) {
      DALogger.warning('PlaybackPrefetchManager: Prefetch failed for "$songId": $e');
    } finally {
      _activeDownloads.remove(songId);
      final tmpFile = File(p.join(prefetchDir.path, '$songId.prefetch.tmp'));
      if (tmpFile.existsSync() && !File(p.join(prefetchDir.path, '$songId.prefetch')).existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> _prefetchArtwork(String songId, String artworkUrl, Directory prefetchDir) async {
    try {
      final artFile = File(p.join(prefetchDir.path, '$songId.jpg'));
      if (artFile.existsSync()) return;

      final req = await _client.getUrl(Uri.parse(artworkUrl));
      req.headers.set('User-Agent', NetworkIdentity.platformUserAgent);
      final res = await req.close();
      if (res.statusCode == 200) {
        final tmpArt = File(p.join(prefetchDir.path, '$songId.art.tmp'));
        if (tmpArt.existsSync()) tmpArt.deleteSync();
        final sink = tmpArt.openWrite();
        await res.pipe(sink);
        await tmpArt.rename(artFile.path);
        DALogger.info('PlaybackPrefetchManager: Saved prefetched artwork for "$songId".');
      }
    } catch (e) {
      DALogger.warning('PlaybackPrefetchManager: Failed to prefetch artwork for "$songId": $e');
    }
  }

  void dispose() {
    _prefetchDebounceTimer?.cancel();
    for (final req in _activeDownloads.values) {
      req.abort();
    }
    _activeDownloads.clear();
  }
}
