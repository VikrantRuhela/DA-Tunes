import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/playback_controller.dart';
import '../../core/services/storage_service.dart';
import '../models/music_models.dart';
import '../models/playback_state.dart';
import 'backend_providers.dart';
import 'library_providers.dart';
import 'theme_providers.dart';

final immersiveModeProvider = StateProvider<bool>((ref) => false);

final playbackControllerProvider = ChangeNotifierProvider<PlaybackController>((ref) {
  final engine = ref.watch(playbackEngineProvider);
  final sourceManager = ref.watch(sourceManagerProvider);
  final artistRepo = ref.watch(artistRepositoryProvider);
  final albumRepo = ref.watch(albumRepositoryProvider);
  final recommendationRepo = ref.watch(recommendationRepositoryProvider);
  final prefetchManager = ref.watch(playbackPrefetchManagerProvider);
  return PlaybackController(
    engine,
    ref,
    sourceManager,
    artistRepo,
    albumRepo,
    recommendationRepo,
    prefetchManager,
  );
});

final playbackStateProvider = Provider<PlaybackState>((ref) {
  final controller = ref.watch(playbackControllerProvider);
  return PlaybackState(
    status: controller.status,
    bufferingProgress: controller.bufferProgress,
  );
});

final currentSongProvider = Provider<Song?>((ref) {
  final controller = ref.watch(playbackControllerProvider);
  return controller.currentSong;
});

final volumeProvider = Provider<int>((ref) {
  final controller = ref.watch(playbackControllerProvider);
  return controller.settings.volume;
});

final muteProvider = Provider<bool>((ref) {
  final controller = ref.watch(playbackControllerProvider);
  return controller.settings.isMuted;
});

final repeatModeProvider = Provider<RepeatMode>((ref) {
  final controller = ref.watch(playbackControllerProvider);
  return controller.settings.repeatMode;
});

final shuffleProvider = Provider<bool>((ref) {
  final controller = ref.watch(playbackControllerProvider);
  return controller.settings.isShuffle;
});

final queueProvider = Provider<List<QueueItem>>((ref) {
  final controller = ref.watch(playbackControllerProvider);
  return controller.queue;
});

final sleepTimerProvider = StateProvider<Timer?>((ref) => null);
final sleepTimerDurationProvider = StateProvider<Duration?>((ref) => null);

class SleepTimerState {
  final bool isActive;
  final int remainingSeconds;
  final Duration? initialDuration;

  const SleepTimerState({
    this.isActive = false,
    this.remainingSeconds = 0,
    this.initialDuration,
  });

  String get formattedRemaining {
    if (!isActive || remainingSeconds <= 0) return '';
    if (remainingSeconds >= 3600) {
      final hours = (remainingSeconds / 3600).ceil();
      return '${hours}h';
    }
    if (remainingSeconds >= 60) {
      final minutes = (remainingSeconds / 60).ceil();
      return '${minutes}m';
    }
    return '${remainingSeconds}s';
  }

  SleepTimerState copyWith({
    bool? isActive,
    int? remainingSeconds,
    Duration? initialDuration,
  }) {
    return SleepTimerState(
      isActive: isActive ?? this.isActive,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      initialDuration: initialDuration ?? this.initialDuration,
    );
  }
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final Ref _ref;
  Timer? _timer;

  SleepTimerNotifier(this._ref) : super(const SleepTimerState());

  void setTimer(Duration duration) {
    cancelTimer();
    final totalSeconds = duration.inSeconds;
    state = SleepTimerState(
      isActive: true,
      remainingSeconds: totalSeconds,
      initialDuration: duration,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.remainingSeconds <= 1) {
        cancelTimer();
        _ref.read(playbackControllerProvider).pause();
      } else {
        state = state.copyWith(
          remainingSeconds: state.remainingSeconds - 1,
        );
      }
    });
  }

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sleepTimerNotifierProvider = StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  return SleepTimerNotifier(ref);
});

enum PlayerStyle { immersive, vinyl, minimal }

final playerStyleNotifierProvider = StateNotifierProvider<PlayerStyleNotifier, PlayerStyle>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return PlayerStyleNotifier(storage);
});

final playerStyleProvider = Provider<PlayerStyle>((ref) {
  final themeMode = ref.watch(appThemeModeProvider);
  if (themeMode == AppThemeMode.amoled) {
    return PlayerStyle.immersive;
  }
  return ref.watch(playerStyleNotifierProvider);
});

class PlayerStyleNotifier extends StateNotifier<PlayerStyle> {
  final StorageService _storage;
  static const _key = 'player_style';

  PlayerStyleNotifier(this._storage) : super(PlayerStyle.immersive) {
    _load();
  }

  void _load() async {
    final val = await _storage.getString(_key);
    if (val != null) {
      final matched = PlayerStyle.values.firstWhere(
        (e) => e.name == val,
        orElse: () => PlayerStyle.immersive,
      );
      state = matched;
    }
  }

  Future<void> setStyle(PlayerStyle style) async {
    state = style;
    await _storage.setString(_key, style.name);
  }
}

final crossfadeEnabledProvider = StateNotifierProvider<CrossfadeEnabledNotifier, bool>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return CrossfadeEnabledNotifier(storage);
});

class CrossfadeEnabledNotifier extends StateNotifier<bool> {
  final StorageService _storage;
  static const _key = 'crossfade_enabled';

  CrossfadeEnabledNotifier(this._storage) : super(false) {
    _load();
  }

  void _load() async {
    final val = await _storage.getString(_key);
    if (val != null) state = val == 'true';
  }

  Future<void> toggle(bool val) async {
    state = val;
    await _storage.setString(_key, val.toString());
  }
}

final crossfadeDurationProvider = StateNotifierProvider<CrossfadeDurationNotifier, int>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return CrossfadeDurationNotifier(storage);
});

class CrossfadeDurationNotifier extends StateNotifier<int> {
  final StorageService _storage;
  static const _key = 'crossfade_duration';

  CrossfadeDurationNotifier(this._storage) : super(0) {
    _load();
  }

  void _load() async {
    final val = await _storage.getString(_key);
    if (val != null) {
      final parsed = int.tryParse(val);
      if (parsed != null) state = parsed.clamp(0, 12);
    }
  }

  Future<void> setDuration(int seconds) async {
    state = seconds.clamp(0, 12);
    await _storage.setString(_key, state.toString());
  }
}
