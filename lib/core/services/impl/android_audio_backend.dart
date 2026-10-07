import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import '../platform_audio_backend.dart';
import '../logger_service.dart';

/// Android client-side implementation of PlatformAudioBackend wrapping the audioplayers engine.
class AndroidAudioBackend implements PlatformAudioBackend {
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

  AndroidAudioBackend() {
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
      _state = s.name;
      DALogger.info('AndroidAudioBackend: State changed to: ${_state.toUpperCase()}');
      if (s == PlayerState.playing) {
        _eventController.add(const PlatformPlaybackStarted());
      } else if (s == PlayerState.paused) {
        _eventController.add(const PlatformPlaybackPaused());
      } else if (s == PlayerState.stopped) {
        _eventController.add(const PlatformPlaybackStopped());
      } else if (s == PlayerState.completed) {
        _eventController.add(const PlatformPlaybackCompleted());
      }
    });
    _player.onLog.listen((msg) {
      DALogger.info('AndroidAudioBackend: AudioPlayer log: $msg');
    });
  }

  @override
  Future<void> initialize() async {
    DALogger.info('AndroidAudioBackend: Initializing AudioPlayer engine...');
    _state = 'ready';
    _eventController.add(const PlatformEngineInitialized());
  }

  @override
  Future<void> dispose() async {
    DALogger.info('AndroidAudioBackend: Disposing AudioPlayer engine...');
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _stateSub?.cancel();
    await _player.dispose();
    _state = 'disposed';
    _eventController.add(const PlatformEngineDisposed());
    _eventController.close();
  }

  @override
  Future<void> load(String url) async {
    DALogger.info('AndroidAudioBackend: Loading streaming URL: "$url"');
    await _player.stop();
    _state = 'loading';
    DALogger.info('AndroidAudioBackend: State changed to: LOADING');
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    _eventController.add(const PlatformBufferingStarted());
    await _player.setSource(UrlSource(url));
    _state = 'ready';
    DALogger.info('AndroidAudioBackend: State changed to: READY');
    _eventController.add(const PlatformBufferingFinished());
  }

  @override
  Future<void> play() async {
    DALogger.info('AndroidAudioBackend: Start playback.');
    await _player.setVolume(_volume);
    await _player.resume();
  }

  @override
  Future<void> pause() async {
    DALogger.info('AndroidAudioBackend: Pause playback.');
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    DALogger.info('AndroidAudioBackend: Resume playback.');
    await _player.setVolume(_volume);
    await _player.resume();
  }

  @override
  Future<void> stop() async {
    DALogger.info('AndroidAudioBackend: Stop playback.');
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    DALogger.info('AndroidAudioBackend: Seek to position ${position.inSeconds}s');
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
