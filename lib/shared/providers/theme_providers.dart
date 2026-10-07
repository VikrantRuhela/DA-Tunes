import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/storage_service.dart';
import 'library_providers.dart';

enum AppThemeMode { defaultDA, amoled, material3 }

enum M3ThemeMode { dark, light }

final appThemeModeProvider = StateNotifierProvider<AppThemeModeNotifier, AppThemeMode>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return AppThemeModeNotifier(storage);
});

class AppThemeModeNotifier extends StateNotifier<AppThemeMode> {
  final StorageService _storage;
  static const _key = 'app_theme_mode';

  AppThemeModeNotifier(this._storage) : super(AppThemeMode.defaultDA) {
    _load();
  }

  void _load() async {
    final val = await _storage.getString(_key);
    if (val != null) {
      final matched = AppThemeMode.values.firstWhere(
        (e) => e.name == val,
        orElse: () => AppThemeMode.defaultDA,
      );
      state = matched;
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    await _storage.setString(_key, mode.name);
  }
}

final m3ThemeModeProvider = StateNotifierProvider<M3ThemeModeNotifier, M3ThemeMode>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return M3ThemeModeNotifier(storage);
});

class M3ThemeModeNotifier extends StateNotifier<M3ThemeMode> {
  final StorageService _storage;
  static const _key = 'm3_theme_mode';

  M3ThemeModeNotifier(this._storage) : super(M3ThemeMode.dark) {
    _load();
  }

  void _load() async {
    final val = await _storage.getString(_key);
    if (val != null) {
      final matched = M3ThemeMode.values.firstWhere(
        (e) => e.name == val,
        orElse: () => M3ThemeMode.dark,
      );
      state = matched;
    }
  }

  Future<void> setMode(M3ThemeMode mode) async {
    state = mode;
    await _storage.setString(_key, mode.name);
  }
}
