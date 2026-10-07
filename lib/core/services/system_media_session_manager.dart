import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'playback_controller.dart';
import '../../shared/models/music_models.dart';
import '../../shared/models/playback_state.dart' as clean;
import 'logger_service.dart';
import '../../shared/providers/library_providers.dart';

class SystemMediaSessionManager {
  static PlaybackController? controller;
  static MyAudioHandler? _audioHandler;
  static StreamSubscription? _controllerSubscription;
  static StreamSubscription? _becomingNoisySubscription;
  static StreamSubscription? _devicesSubscription;
  static StreamSubscription? _interruptionSubscription;
  static Set<AudioDevice>? _previousDevices;
  static Timer? _positionTimer;

  static clean.PlaybackStatus? _lastStatus;
  static String? _lastSongId;
  static bool? _lastIsPlaying;
  static bool? _lastIsBuffering;

  static Future<void> initialize(PlaybackController playbackController) async {
    controller = playbackController;

    if (!kIsWeb) {
      _setupEarphoneDisconnectListener();
    }

    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isWindows) return;

    try {
      DALogger.info('SystemMediaSessionManager: Initializing AudioService...');
      _audioHandler = await AudioService.init(
        builder: () => MyAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.vikrantruhela.datunes.channel.audio',
          androidNotificationChannelName: 'Music Playback',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
          androidNotificationIcon: 'drawable/ic_notification',
        ),
      );
      _setupStateListener();
    } catch (e, stack) {
      DALogger.error('SystemMediaSessionManager: Initialization failed', e, stack);
    }
  }

  static Future<void> _setupEarphoneDisconnectListener() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      _becomingNoisySubscription?.cancel();
      _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
        DALogger.info('SystemMediaSessionManager: Earphones disconnected. Pausing song.');
        final c = controller;
        if (c != null && c.status == clean.PlaybackStatus.playing) {
          c.pause();
        }
      });

      _interruptionSubscription?.cancel();
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          DALogger.info('SystemMediaSessionManager: Audio interruption started. Pausing song.');
          final c = controller;
          if (c != null && c.status == clean.PlaybackStatus.playing) {
            c.pause();
          }
        }
      });

      _devicesSubscription?.cancel();
      _devicesSubscription = session.devicesStream.listen((devices) {
        final currentDevices = devices.toSet();
        if (_previousDevices != null) {
          final removed = _previousDevices!.difference(currentDevices);
          for (final device in removed) {
            final typeStr = device.type.toString().toLowerCase();
            final nameStr = device.name.toLowerCase();
            final isEarphoneOrHeadset = typeStr.contains('headset') ||
                typeStr.contains('headphone') ||
                typeStr.contains('bluetooth') ||
                typeStr.contains('a2dp') ||
                typeStr.contains('usb') ||
                typeStr.contains('hearingaid') ||
                nameStr.contains('earphone') ||
                nameStr.contains('headphone') ||
                nameStr.contains('headset') ||
                nameStr.contains('airpod') ||
                nameStr.contains('bud');

            if (isEarphoneOrHeadset) {
              DALogger.info('SystemMediaSessionManager: Earphone device removed (${device.name}). Pausing song.');
              final c = controller;
              if (c != null && c.status == clean.PlaybackStatus.playing) {
                c.pause();
              }
              break;
            }
          }
        }
        _previousDevices = currentDevices;
      });
    } catch (e, stack) {
      DALogger.error('SystemMediaSessionManager: Earphone disconnect listener setup failed', e, stack);
    }
  }

  static void _setupStateListener() {
    _controllerSubscription?.cancel();
    final c = controller;
    if (c == null) return;

    // Reset tracking variables on new setup
    _lastStatus = null;
    _lastSongId = null;
    _lastIsPlaying = null;
    _lastIsBuffering = null;

    // Listen to changes on PlaybackController
    c.addListener(_onControllerStateChanged);
    _onControllerStateChanged(); // update immediately with current state
  }

  static void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final activeController = controller;
      if (activeController == null) return;

      final position = activeController.position;
      final song = activeController.currentSong;
      final isPlaying = activeController.status == clean.PlaybackStatus.playing;

      if (isPlaying && song != null && _audioHandler != null) {
        _audioHandler!.updatePlaybackPosition(position, isPlaying);
      }
    });
  }

  static void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  static void _onControllerStateChanged() {
    final c = controller;
    if (c == null) return;

    final song = c.currentSong;
    final isPlaying = c.status == clean.PlaybackStatus.playing;
    final isBuffering = c.status == clean.PlaybackStatus.buffering;

    final songIdChanged = song?.id != _lastSongId;
    final statusChanged = c.status != _lastStatus || isPlaying != _lastIsPlaying || isBuffering != _lastIsBuffering;
    final isSeeking = c.isSeeking;

    if (songIdChanged || statusChanged || isSeeking) {
      _lastSongId = song?.id;
      _lastStatus = c.status;
      _lastIsPlaying = isPlaying;
      _lastIsBuffering = isBuffering;

      if (song != null && _audioHandler != null) {
        final duration = song.duration;
        final position = c.position;

        _audioHandler!.updateMetadata(song, duration);
        _audioHandler!.updatePlaybackState(isPlaying, isBuffering, position);

        if (isPlaying) {
          _startPositionTimer();
        } else {
          _stopPositionTimer();
        }
      } else if (_audioHandler != null) {
        // Stopped / Idle
        _stopPositionTimer();
        _audioHandler!.playbackState.add(_audioHandler!.playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
          speed: 0.0,
        ));
      }
    }
  }

  static void dispose() {
    _positionTimer?.cancel();
    _controllerSubscription?.cancel();
    _becomingNoisySubscription?.cancel();
    _interruptionSubscription?.cancel();
    _devicesSubscription?.cancel();
    controller?.removeListener(_onControllerStateChanged);
  }
}

/// Audio Handler implementation for audio_service.
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  MyAudioHandler() {
    // Emit initial empty state
    playbackState.add(PlaybackState(
      controls: const [],
      systemActions: const {
        MediaAction.seek,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0],
      processingState: AudioProcessingState.idle,
      playing: false,
      speed: 0.0,
    ));
  }

  Future<void> updateMetadata(Song song, Duration duration) async {
    Uri? resolvedArtUri;

    if (song.artworkUrl != null && song.artworkUrl!.isNotEmpty) {
      if (song.artworkUrl!.startsWith('http')) {
        resolvedArtUri = Uri.tryParse(song.artworkUrl!);
      } else {
        final file = File(song.artworkUrl!);
        if (await file.exists()) {
          resolvedArtUri = Uri.file(song.artworkUrl!);
        }
      }
    }

    if (resolvedArtUri == null && song.source == 'local') {
      try {
        final audioFile = File(song.id);
        if (await audioFile.exists()) {
          final parentDir = audioFile.parent;
          if (await parentDir.exists()) {
            final commonNames = [
              'cover.jpg', 'cover.png', 'cover.jpeg',
              'folder.jpg', 'folder.png', 'folder.jpeg',
              'albumart.jpg', 'albumart.png', 'albumart.jpeg',
              'album.jpg', 'album.png', 'album.jpeg',
              'art.jpg', 'art.png', 'art.jpeg',
            ];

            File? foundFile;
            for (final name in commonNames) {
              final f = File('${parentDir.path}/$name');
              if (await f.exists()) {
                foundFile = f;
                break;
              }
            }

            if (foundFile == null) {
              await for (final entity in parentDir.list()) {
                if (entity is File) {
                  final filename = entity.path.split('/').last.split('\\').last.toLowerCase();
                  final ext = filename.split('.').last;
                  if (ext == 'jpg' || ext == 'png' || ext == 'jpeg') {
                    if (filename.contains('cover') ||
                        filename.contains('folder') ||
                        filename.contains('albumart') ||
                        filename.contains('album') ||
                        filename.contains('art')) {
                      foundFile = entity;
                      break;
                    }
                  }
                }
              }
            }

            if (foundFile != null) {
              resolvedArtUri = Uri.file(foundFile.path);
            }
          }
        }
      } catch (_) {}
    }

    if (resolvedArtUri == null && !kIsWeb && Platform.isAndroid) {
      resolvedArtUri = Uri.parse('android.resource://com.vikrantruhela.datunes/drawable/ic_notification');
    }

    mediaItem.add(MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: duration,
      artUri: resolvedArtUri,
    ));
  }

  void updatePlaybackState(bool isPlaying, bool isBuffering, Duration position) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: isBuffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: isPlaying,
      updatePosition: position,
      speed: isPlaying ? 1.0 : 0.0,
    ));
  }

  void updatePlaybackPosition(Duration position, bool isPlaying) {
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
      playing: isPlaying,
      speed: isPlaying ? 1.0 : 0.0,
    ));
  }

  @override
  Future<void> play() async {
    SystemMediaSessionManager.controller?.play();
  }

  @override
  Future<void> pause() async {
    SystemMediaSessionManager.controller?.pause();
  }

  @override
  Future<void> stop() async {
    final c = SystemMediaSessionManager.controller;
    if (c != null) {
      await c.stop();
    }
    SystemMediaSessionManager._stopPositionTimer();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
      controls: const [],
    ));
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preventAppKilled = prefs.getString('prevent_app_killed') == 'true';
      if (preventAppKilled) {
        DALogger.info('SystemMediaSessionManager: App removed from Recents, but preventAppKilled is enabled. Background service will continue.');
        return;
      }
    } catch (e) {
      DALogger.error('SystemMediaSessionManager: Error checking preventAppKilled setting', e);
    }

    DALogger.info('SystemMediaSessionManager: App removed from Recents. Initiating shutdown.');
    final c = SystemMediaSessionManager.controller;
    if (c != null) {
      await c.stop();
    }
    SystemMediaSessionManager._stopPositionTimer();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
      controls: const [],
    ));
    await stop();
    await super.onTaskRemoved();
  }

  @override
  Future<void> skipToNext() async {
    SystemMediaSessionManager.controller?.next();
  }

  @override
  Future<void> skipToPrevious() async {
    SystemMediaSessionManager.controller?.previous();
  }

  @override
  Future<void> seek(Duration position) async {
    SystemMediaSessionManager.controller?.seek(position);
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == "toggle_favorite") {
      final c = SystemMediaSessionManager.controller;
      if (c != null) {
        final current = c.currentSong;
        final ref = c.ref;
        if (current != null && ref != null) {
          ref.read(libraryManagerProvider.notifier).toggleLikeSong(current);
        }
      }
    }
    return null;
  }
}
