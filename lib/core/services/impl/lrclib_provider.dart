import 'dart:convert';
import 'dart:io';
import '../../../domain/entities/lyrics.dart';
import '../lyrics_provider.dart';
import '../logger_service.dart';
import '../network_identity.dart';

class LrcLibProvider implements LyricsProvider {
  static final Map<String, DateTime> _negativeCache = {};
  static HttpClient? _sharedClient;
  static HttpClient get _client => _sharedClient ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4;

  @override
  String get id => 'lrclib';

  @override
  String get name => 'LRCLIB';

  @override
  Future<Lyrics?> fetchLyrics({
    required String songId,
    required String title,
    required String artist,
    required String album,
    required Duration duration,
  }) async {
    final negExpiry = _negativeCache[songId];
    if (negExpiry != null && DateTime.now().isBefore(negExpiry)) {
      DALogger.info('LrcLibProvider: Skipping negative-cached song "$songId"');
      return null;
    }

    final cleanArtist = artist.replaceAll(' - Topic', '').replaceAll('VEVO', '').trim();
    final cleanTitle = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    final cleanAlbum = album == 'yt_album_unknown' ? '' : album;
    final durationSeconds = duration.inSeconds;

    final getUri = Uri.parse('https://lrclib.net/api/get').replace(
      queryParameters: {
        'artist_name': cleanArtist,
        'track_name': cleanTitle,
        if (cleanAlbum.isNotEmpty) 'album_name': cleanAlbum,
        'duration': durationSeconds.toString(),
      },
    );

    try {
      DALogger.info('LrcLibProvider: Sending direct GET query for "$cleanTitle" by "$cleanArtist"');
      final request = await _client.getUrl(getUri);
      request.headers.set('User-Agent', NetworkIdentity.lrclibUserAgent);
      final response = await request.close();

      if (response.statusCode == 429) {
        DALogger.warning('LrcLibProvider: Rate-limited by LRCLIB (429)');
        _negativeCache[songId] = DateTime.now().add(const Duration(minutes: 15));
        return null;
      }

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final lyrics = _parseApiResponse(songId, json);
        if (lyrics != null) {
          DALogger.info('LrcLibProvider: Found direct match for "$cleanTitle"');
          return lyrics;
        }
      }
    } catch (e) {
      DALogger.info('LrcLibProvider: Direct GET request failed or returned 404: $e');
    }

    // 2. Fallback to search endpoint with local ranking
    final searchUri = Uri.parse('https://lrclib.net/api/search').replace(
      queryParameters: {
        'q': '$cleanArtist $cleanTitle',
      },
    );

    try {
      DALogger.info('LrcLibProvider: Falling back to search for "$cleanArtist $cleanTitle"');
      final request = await _client.getUrl(searchUri);
      request.headers.set('User-Agent', NetworkIdentity.lrclibUserAgent);
      final response = await request.close();

      if (response.statusCode == 429) {
        DALogger.warning('LrcLibProvider: Rate-limited by LRCLIB during search (429)');
        _negativeCache[songId] = DateTime.now().add(const Duration(minutes: 15));
        return null;
      }

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final candidatesList = jsonDecode(body) as List;
        final candidates = candidatesList.cast<Map<String, dynamic>>();

        final ranked = <({Map<String, dynamic> item, int score, String reasons})>[];

        for (final item in candidates) {
          final candTitle = item['trackName'] as String? ?? '';
          final candArtist = item['artistName'] as String? ?? '';
          final candAlbum = item['albumName'] as String? ?? '';
          final candDuration = item['duration'] as num? ?? 0;

          int score = 0;
          final reasons = <String>[];

          final normOrigArtist = _normalize(cleanArtist);
          final normCandArtist = _normalize(candArtist);
          if (normCandArtist == normOrigArtist) {
            score += 1000;
            reasons.add('Artist match (+1000)');
          } else if (normCandArtist.contains(normOrigArtist) || normOrigArtist.contains(normCandArtist)) {
            score += 600;
            reasons.add('Partial artist match (+600)');
          }

          final normOrigTitle = _normalize(cleanTitle);
          final normCandTitle = _normalize(candTitle);
          if (normCandTitle == normOrigTitle) {
            score += 300;
            reasons.add('Title match (+300)');
          } else if (normCandTitle.contains(normOrigTitle) || normOrigTitle.contains(normCandTitle)) {
            score += 100;
            reasons.add('Partial title match (+100)');
          } else {
            score -= 5000;
            reasons.add('Title mismatch penalty (-5000)');
          }

          if (cleanAlbum.isNotEmpty) {
            final normOrigAlbum = _normalize(cleanAlbum);
            final normCandAlbum = _normalize(candAlbum);
            if (normCandAlbum == normOrigAlbum) {
              score += 200;
              reasons.add('Album match (+200)');
            }
          }

          final diff = (candDuration - durationSeconds).abs();
          if (diff <= 3) {
            score += 150;
            reasons.add('Duration match ±3s (+150)');
          } else {
            score -= 1000;
            reasons.add('Duration mismatch penalty (-1000)');
          }

          ranked.add((item: item, score: score, reasons: reasons.join(', ')));
        }

        if (ranked.isNotEmpty) {
          ranked.sort((a, b) => b.score.compareTo(a.score));

          DALogger.info('=== LRCLIB CANDIDATE RANKINGS FOR "$cleanTitle" ===');
          for (final r in ranked) {
            DALogger.info('  - Candidate "${r.item['trackName']}" by "${r.item['artistName']}": Score = ${r.score} (Reasons: ${r.reasons})');
          }

          final best = ranked.first;
          if (best.score >= 200) {
            DALogger.info('LrcLibProvider: Selected candidate with score ${best.score}');
            return _parseApiResponse(songId, best.item);
          } else {
            DALogger.info('LrcLibProvider: Top candidate score (${best.score}) is below confidence threshold. Discarding match.');
          }
        }
      }
    } catch (e) {
      DALogger.info('LrcLibProvider: Search request failed: $e');
    }

    _negativeCache[songId] = DateTime.now().add(const Duration(hours: 48));
    return null;
  }

  String _normalize(String str) {
    return str.toLowerCase()
              .replaceAll('&', 'and')
              .replaceAll(RegExp(r'[^a-z0-9]'), '')
              .trim();
  }

  Lyrics? _parseApiResponse(String songId, Map<String, dynamic> json) {
    final isInstrumental = json['instrumental'] as bool? ?? false;
    final plain = json['plainLyrics'] as String? ?? '';
    final syncedStr = json['syncedLyrics'] as String? ?? '';

    if (isInstrumental) {
      return Lyrics(
        songId: songId,
        plainLyrics: 'Instrumental',
        syncedLyrics: null,
        language: 'en',
        provider: id,
      );
    }

    if (plain.isEmpty && syncedStr.isEmpty) {
      return null;
    }

    final syncedMap = _parseLrc(syncedStr);
    return Lyrics(
      songId: songId,
      plainLyrics: plain.isNotEmpty ? plain : 'No plain text lyrics available.',
      syncedLyrics: syncedMap,
      language: 'en',
      provider: id,
    );
  }

  Map<Duration, String>? _parseLrc(String lrcStr) {
    if (lrcStr.isEmpty) return null;
    final Map<Duration, String> synced = {};
    final lines = lrcStr.split('\n');
    final regex = RegExp(r'^\[(\d+):(\d+)(?:\.(\d+))?\](.*)$');

    for (var line in lines) {
      line = line.trim();
      final match = regex.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        var ms = 0;
        final msGroup = match.group(3);
        if (msGroup != null) {
          if (msGroup.length == 2) {
            ms = int.parse(msGroup) * 10;
          } else if (msGroup.length == 3) {
            ms = int.parse(msGroup);
          } else {
            ms = int.parse(msGroup);
          }
        }
        final text = match.group(4)!.trim();
        final duration = Duration(minutes: min, seconds: sec, milliseconds: ms);
        synced[duration] = text;
      }
    }
    return synced.isNotEmpty ? synced : null;
  }
}
