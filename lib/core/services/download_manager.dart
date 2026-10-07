import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/music_models.dart';
import '../../data/repositories/download_repository.dart';
import 'stream_resolver.dart';
import 'logger_service.dart';
import 'network_identity.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

class DownloadTask {
  final String songId;
  final String title;
  final String artist;
  final DownloadStatus status;
  final double progress; // 0.0 to 1.0
  final String? localFilePath;
  final String? error;
  final double speedMb; // Speed in MB/s
  final int remainingBytes; // Remaining size in bytes
  final int etaSeconds; // Estimated time remaining in seconds

  const DownloadTask({
    required this.songId,
    required this.title,
    required this.artist,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.localFilePath,
    this.error,
    this.speedMb = 0.0,
    this.remainingBytes = 0,
    this.etaSeconds = 0,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? localFilePath,
    String? error,
    double? speedMb,
    int? remainingBytes,
    int? etaSeconds,
  }) {
    return DownloadTask(
      songId: songId,
      title: title,
      artist: artist,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      localFilePath: localFilePath ?? this.localFilePath,
      error: error ?? this.error,
      speedMb: speedMb ?? this.speedMb,
      remainingBytes: remainingBytes ?? this.remainingBytes,
      etaSeconds: etaSeconds ?? this.etaSeconds,
    );
  }
}

class DownloadManager extends ChangeNotifier {
  static HttpClient? _sharedDownloadClient;
  static HttpClient get _downloadClient => _sharedDownloadClient ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = 4;

  final StreamResolver _streamResolver;
  final DownloadRepository _repository;
  final Map<String, DownloadTask> _tasks = {};
  final Set<String> _runningTaskIds = {};
  String _preferredQuality = 'High';

  DownloadManager(this._streamResolver, this._repository) {
    _loadTasksFromDb();
    _loadSettings();
  }

  List<DownloadTask> get allTasks => _tasks.values.toList();
  DownloadTask? getTask(String songId) => _tasks[songId];
  String get preferredQuality => _preferredQuality;

  Future<void> _loadTasksFromDb() async {
    try {
      final tasks = await _repository.getAllTasks();
      for (final t in tasks) {
        _tasks[t.songId] = t;
      }
      notifyListeners();
      _processQueue();
    } catch (e) {
      DALogger.error('DownloadManager: Failed to load tasks from DB', e);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _preferredQuality = prefs.getString('download_quality') ?? 'High';
      notifyListeners();
    } catch (e) {
      DALogger.error('DownloadManager: Failed to load settings', e);
    }
  }

  Future<void> setPreferredQuality(String quality) async {
    _preferredQuality = quality;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('download_quality', quality);
    } catch (e) {
      DALogger.error('DownloadManager: Failed to save quality setting', e);
    }
  }

  Future<void> startDownload(Song song) async {
    if (_tasks.containsKey(song.id)) {
      final task = _tasks[song.id]!;
      if (task.status == DownloadStatus.completed) return;
      if (task.status == DownloadStatus.paused) {
        resumeDownload(song.id);
        return;
      }
    }

    DALogger.info('DownloadManager: Queued download for: ${song.title}');
    final task = DownloadTask(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      status: DownloadStatus.queued,
      progress: 0.0,
    );

    _updateTask(task);
    await _repository.saveSongMetadata(song, downloaded: false);
    await _repository.saveDownloadTask(song.id, DownloadStatus.queued, 0.0, null);

    _processQueue();
  }

  void pauseDownload(String songId) {
    final task = _tasks[songId];
    if (task == null || task.status != DownloadStatus.downloading) return;

    DALogger.info('DownloadManager: Pausing download for: ${task.title}');
    _updateTask(task.copyWith(status: DownloadStatus.paused, speedMb: 0.0, etaSeconds: 0));
    _repository.saveDownloadTask(songId, DownloadStatus.paused, task.progress, null);
  }

  void resumeDownload(String songId) {
    final task = _tasks[songId];
    if (task == null || task.status != DownloadStatus.paused) return;

    DALogger.info('DownloadManager: Resuming download for: ${task.title}');
    _updateTask(task.copyWith(status: DownloadStatus.queued));
    _repository.saveDownloadTask(songId, DownloadStatus.queued, task.progress, null);

    _processQueue();
  }

  Future<void> cancelDownload(String songId) async {
    final task = _tasks[songId];
    if (task == null) return;

    DALogger.info('DownloadManager: Cancelling download for: ${task.title}');
    _updateTask(task.copyWith(status: DownloadStatus.cancelled, speedMb: 0.0, etaSeconds: 0));
    await _repository.deleteDownloadTask(songId);

    // Delete partial file
    final docDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docDir.path, 'da_tunes_downloads', '$songId.mp3'));
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (e) {
        DALogger.error('DownloadManager: Failed to delete cancelled partial file', e);
      }
    }

    _tasks.remove(songId);
    notifyListeners();
    _processQueue();
  }

  Future<void> removeDownload(String songId) async {
    await cancelDownload(songId);
  }

  void _processQueue() {
    final activeCount = _tasks.values.where((t) => t.status == DownloadStatus.downloading).length;
    const maxConcurrent = 3;
    if (activeCount >= maxConcurrent) return;

    final queuedTasks = _tasks.values.where((t) => t.status == DownloadStatus.queued).toList();
    if (queuedTasks.isEmpty) return;

    final slotsAvailable = maxConcurrent - activeCount;
    for (int i = 0; i < slotsAvailable && i < queuedTasks.length; i++) {
      final task = queuedTasks[i];
      if (!_runningTaskIds.contains(task.songId)) {
        _runningTaskIds.add(task.songId);
        _downloadWorker(task.songId);
      }
    }
  }

  Future<void> _downloadWorker(String songId) async {
    final task = _tasks[songId];
    if (task == null) {
      _runningTaskIds.remove(songId);
      return;
    }

    _updateTask(task.copyWith(status: DownloadStatus.downloading));
    await _repository.saveDownloadTask(songId, DownloadStatus.downloading, task.progress, null);

    try {
      final song = await _repository.getSongById(songId);
      final providerId = song?.source ?? 'youtube_music';

      final stream = await _streamResolver.resolve(
        trackId: songId,
        providerId: providerId,
        songTitle: song?.title,
        artist: song?.artist,
        duration: song?.duration,
      );

      final docDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory(p.join(docDir.path, 'da_tunes_downloads'));
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      final localFile = File(p.join(downloadsDir.path, '$songId.mp3'));
      int existingBytes = 0;
      bool isResume = false;

      if (task.progress > 0.0 && localFile.existsSync()) {
        existingBytes = localFile.lengthSync();
        isResume = true;
      }

      final request = await _downloadClient.getUrl(Uri.parse(stream.streamUrl));

      stream.headers.forEach((key, val) {
        request.headers.set(key, val);
      });

      request.headers.set('User-Agent', NetworkIdentity.platformUserAgent);

      if (isResume && existingBytes > 0) {
        request.headers.set('Range', 'bytes=$existingBytes-');
      }

      final response = await request.close();
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final bool rangeAccepted = response.statusCode == 206;
      final int totalContentLength = response.contentLength;
      final int totalBytes = rangeAccepted ? (totalContentLength + existingBytes) : totalContentLength;

      final iosink = localFile.openWrite(mode: rangeAccepted ? FileMode.append : FileMode.write);

      int downloadedBytes = rangeAccepted ? existingBytes : 0;
      final stopwatch = Stopwatch()..start();
      int lastCheckedBytes = downloadedBytes;
      int lastCheckedTimeMs = stopwatch.elapsedMilliseconds;
      double lastSavedDbProgress = task.progress;
      int lastSavedDbTimeMs = stopwatch.elapsedMilliseconds;

      await for (final chunk in response) {
        final currentTaskState = _tasks[songId];
        if (currentTaskState == null || currentTaskState.status != DownloadStatus.downloading) {
          await iosink.close();
          if (currentTaskState?.status == DownloadStatus.cancelled) {
            if (localFile.existsSync()) {
              localFile.deleteSync();
            }
          }
          return;
        }

        iosink.add(chunk);
        downloadedBytes += chunk.length;

        final int nowMs = stopwatch.elapsedMilliseconds;
        final int timeDiffMs = nowMs - lastCheckedTimeMs;

        // UI progress update (every 400ms in memory, very cheap)
        if (timeDiffMs >= 400) {
          final double progress = totalBytes > 0 ? (downloadedBytes / totalBytes) : 0.0;
          final int bytesInInterval = downloadedBytes - lastCheckedBytes;
          
          double speed = 0.0;
          if (timeDiffMs > 0) {
            speed = (bytesInInterval / (1024 * 1024)) / (timeDiffMs / 1000.0);
          }

          final int remaining = totalBytes - downloadedBytes;
          int eta = 0;
          if (speed > 0) {
            final double speedBytesPerSec = speed * 1024 * 1024;
            eta = (remaining / speedBytesPerSec).round();
          }

          _updateTask(currentTaskState.copyWith(
            progress: progress.clamp(0.0, 1.0),
            speedMb: speed,
            remainingBytes: remaining,
            etaSeconds: eta,
          ));

          // Throttled DB save (only write to DB if 10% progress has passed OR 3 seconds since last DB save)
          final double progressDiff = progress - lastSavedDbProgress;
          final int timeSinceLastDbSaveMs = nowMs - lastSavedDbTimeMs;
          if (progressDiff >= 0.10 || timeSinceLastDbSaveMs >= 3000) {
            await _repository.saveDownloadTask(songId, DownloadStatus.downloading, progress.clamp(0.0, 1.0), null);
            lastSavedDbProgress = progress;
            lastSavedDbTimeMs = nowMs;
          }

          lastCheckedBytes = downloadedBytes;
          lastCheckedTimeMs = nowMs;
        }
      }

      await iosink.flush();
      await iosink.close();

      final completedTask = _tasks[songId];
      if (completedTask != null && completedTask.status == DownloadStatus.downloading) {
        // Update database first to avoid race conditions with reactive providers
        await _repository.saveDownloadTask(songId, DownloadStatus.completed, 1.0, localFile.path);
        
        final song = await _repository.getSongById(songId);
        if (song != null) {
          await _repository.saveSongMetadata(
            song,
            downloaded: true,
          );
          if (song.artworkUrl != null && song.artworkUrl!.isNotEmpty) {
            try {
              final artFile = File(p.join(downloadsDir.path, '$songId.jpg'));
              if (!artFile.existsSync()) {
                final client = HttpClient();
                client.connectionTimeout = const Duration(seconds: 10);
                final req = await client.getUrl(Uri.parse(song.artworkUrl!));
                req.headers.set(
                  'User-Agent',
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                );
                final res = await req.close();
                if (res.statusCode == 200) {
                  final tempArtFile = File(p.join(downloadsDir.path, '$songId.art.tmp'));
                  if (tempArtFile.existsSync()) tempArtFile.deleteSync();
                  final sink = tempArtFile.openWrite();
                  await res.pipe(sink);
                  await tempArtFile.rename(artFile.path);
                  DALogger.info('DownloadManager: Saved downloaded artwork for "$songId".');
                }
                client.close();
              }
            } catch (e) {
              DALogger.warning('DownloadManager: Failed to download artwork for "$songId": $e');
            }
          }
        }

        // Notify listeners after database is fully synchronized
        _updateTask(completedTask.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          localFilePath: localFile.path,
          speedMb: 0.0,
          remainingBytes: 0,
          etaSeconds: 0,
        ));
      }
    } catch (e, stack) {
      DALogger.error('DownloadWorker failed for songId: $songId', e, stack);
      final currentTaskState = _tasks[songId];
      if (currentTaskState != null && currentTaskState.status == DownloadStatus.downloading) {
        _updateTask(currentTaskState.copyWith(
          status: DownloadStatus.failed,
          error: e.toString(),
          speedMb: 0.0,
          remainingBytes: 0,
          etaSeconds: 0,
        ));
        await _repository.saveDownloadTask(songId, DownloadStatus.failed, currentTaskState.progress, null);
      }
    } finally {
      _runningTaskIds.remove(songId);
      _processQueue();
    }
  }

  void _updateTask(DownloadTask task) {
    _tasks[task.songId] = task;
    notifyListeners();
  }

}
