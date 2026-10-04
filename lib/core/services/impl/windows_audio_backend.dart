import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../platform_audio_backend.dart';
import '../logger_service.dart';
import '../stream_resolver.dart';
import '../../../app/router/router.dart';

/// Windows client-side implementation of PlatformAudioBackend wrapping the audioplayers engine.
class WindowsAudioBackend implements PlatformAudioBackend {
  final AudioPlayer _player = AudioPlayer();
  final StreamController<PlatformAudioEvent> _eventController = StreamController<PlatformAudioEvent>.broadcast();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double _volume = 1.0;
  double _speed = 1.0;
  String _state = 'idle';

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _logSub;
  StreamSubscription? _completeSub;

  WindowsAudioBackend() {
    _setupListeners();
  }

  void _setupListeners() {
    _posSub = _player.onPositionChanged.listen((p) {
      _position = p;
    });
    _durSub = _player.onDurationChanged.listen((d) {
      _duration = d;
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      // ignore: avoid_print
      print('WindowsAudioBackend: onPlayerStateChanged event: $s');
      _state = s.name;
      DALogger.info('WindowsAudioBackend: State changed to: ${_state.toUpperCase()}');
      if (s == PlayerState.playing) {
        _eventController.add(const PlatformPlaybackStarted());
      } else if (s == PlayerState.paused) {
        _eventController.add(const PlatformPlaybackPaused());
      } else if (s == PlayerState.stopped) {
        _eventController.add(const PlatformPlaybackStopped());
      } else if (s == PlayerState.completed) {
        final isNormalCompletion = _duration > Duration.zero && 
            (_duration - _position).inMilliseconds.abs() < 2000;
        
        if (!isNormalCompletion) {
          final song = StreamResolver.lastResolvedSong;
          final url = StreamResolver.lastResolvedUrl;
          final title = song?.title ?? "Unknown Title";
          // ignore: avoid_print
          print('=== SKIPPED SONG DIAGNOSTIC ===');
          // ignore: avoid_print
          print('- Song Title: $title');
          // ignore: avoid_print
          print('- Song ID: ${song?.id ?? "Unknown ID"}');
          // ignore: avoid_print
          print('- Provider ID: ${song?.sourceId ?? "Unknown Provider"}');
          // ignore: avoid_print
          print('- Resolved Stream URL: ${url ?? "Unknown URL"}');
          // ignore: avoid_print
          print('- Exception from StreamResolver (if any): None');
          // ignore: avoid_print
          print('- Exception from the audio backend (if any): Player completed unexpectedly. Position: $_position, Duration: $_duration');
          // ignore: avoid_print
          print('- Exact reason why playback was skipped: Audio player failed to buffer or play the stream asynchronously');
          // ignore: avoid_print
          print('===============================');

          // Display SnackBar to the user
          final context = rootNavigatorKey.currentContext;
          if (context != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cannot play "$title": Failed to decode or buffer audio stream.'),
                  backgroundColor: Colors.redAccent,
                  duration: const Duration(seconds: 4),
                ),
              );
            });
          }

          _eventController.add(const PlatformPlaybackError('Immediate playback error/completion'));
        } else {
          _eventController.add(const PlatformPlaybackCompleted());
        }
      }
    });
    _logSub = _player.onLog.listen((msg) {
      // ignore: avoid_print
      print('WindowsAudioBackend: onLog event: $msg');
      DALogger.info('WindowsAudioBackend: AudioPlayer log: $msg');
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      // ignore: avoid_print
      print('WindowsAudioBackend: onPlayerComplete event');
    });
  }

  @override
  Future<void> initialize() async {
    DALogger.info('WindowsAudioBackend: Initializing AudioPlayer engine...');
    _state = 'ready';
    _eventController.add(const PlatformEngineInitialized());
  }

  @override
  Future<void> dispose() async {
    DALogger.info('WindowsAudioBackend: Disposing AudioPlayer engine...');
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _stateSub?.cancel();
    await _logSub?.cancel();
    await _completeSub?.cancel();
    await _player.dispose();
    _state = 'disposed';
    _eventController.add(const PlatformEngineDisposed());
    _eventController.close();
  }

  @override
  Future<void> load(String url) async {
    DALogger.info('WindowsAudioBackend: Loading streaming URL: "$url"');
    await _player.stop();
    _state = 'loading';
    DALogger.info('WindowsAudioBackend: State changed to: LOADING');
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    _eventController.add(const PlatformBufferingStarted());
    try {
      await _player.setSource(UrlSource(url));
    } catch (e) {
      final song = StreamResolver.lastResolvedSong;
      final title = song?.title ?? "Unknown Title";
      // ignore: avoid_print
      print('=== SKIPPED SONG DIAGNOSTIC ===');
      // ignore: avoid_print
      print('- Song Title: $title');
      // ignore: avoid_print
      print('- Song ID: ${song?.id ?? "Unknown ID"}');
      // ignore: avoid_print
      print('- Provider ID: ${song?.sourceId ?? "Unknown Provider"}');
      // ignore: avoid_print
      print('- Resolved Stream URL: $url');
      // ignore: avoid_print
      print('- Exception from StreamResolver (if any): None');
      // ignore: avoid_print
      print('- Exception from the audio backend (if any): $e');
      // ignore: avoid_print
      print('- Exact reason why playback was skipped: setSource threw an exception');
      // ignore: avoid_print
      print('===============================');

      // Display SnackBar to the user
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot play "$title": Audio backend failed to load URL.'),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 4),
            ),
          );
        });
      }
      rethrow;
    }
    _state = 'ready';
    DALogger.info('WindowsAudioBackend: State changed to: READY');
    _eventController.add(const PlatformBufferingFinished());
  }

  @override
  Future<void> play() async {
    DALogger.info('WindowsAudioBackend: Start playback.');
    try {
      await _player.setVolume(_volume);
      await _player.resume();
    } catch (e) {
      // ignore: avoid_print
      print('WindowsAudioBackend: play/resume failed with exception: $e');
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    DALogger.info('WindowsAudioBackend: Pause playback.');
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    DALogger.info('WindowsAudioBackend: Resume playback.');
    try {
      await _player.setVolume(_volume);
      await _player.resume();
    } catch (e) {
      // ignore: avoid_print
      print('WindowsAudioBackend: resume failed with exception: $e');
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    DALogger.info('WindowsAudioBackend: Stop playback.');
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    DALogger.info('WindowsAudioBackend: Seek to position ${position.inSeconds}s');
    await _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _player.setVolume(volume);
    _eventController.add(PlatformVolumeChanged(volume));
  }

  @override
  Future<void> mute() async {
    await _player.setVolume(0.0);
    _eventController.add(const PlatformVolumeChanged(0.0));
  }

  @override
  Future<void> unmute() async {
    await _player.setVolume(_volume);
    _eventController.add(PlatformVolumeChanged(_volume));
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player.setPlaybackRate(speed);
    _eventController.add(PlatformSpeedChanged(speed));
  }

  @override
  Future<void> setLoopMode(bool enabled) async {
    await _player.setReleaseMode(enabled ? ReleaseMode.loop : ReleaseMode.release);
  }

  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Duration get currentPosition => _position;

  @override
  Duration get duration => _duration;

  @override
  Duration get bufferedPosition => _buffered;

  @override
  double get speed => _speed;

  @override
  String get currentState => _state;

  @override
  Stream<PlatformAudioEvent> get eventStream => _eventController.stream;
}
