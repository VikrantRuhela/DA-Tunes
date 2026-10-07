import 'dart:io';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'theme.dart';
import '../../shared/providers/player_providers.dart';
import '../../shared/providers/theme_providers.dart';
import '../../shared/models/music_models.dart';

final activeThemeProvider = Provider<ThemeData>((ref) {
  final mode = ref.watch(appThemeModeProvider);
  if (mode == AppThemeMode.amoled) {
    return DATheme.amoledTheme;
  }
  if (mode == AppThemeMode.material3) {
    final m3Mode = ref.watch(m3ThemeModeProvider);
    final brightness = m3Mode == M3ThemeMode.light ? Brightness.light : Brightness.dark;
    return DATheme.m3Theme(brightness: brightness);
  }
  return ref.watch(dynamicThemeProvider);
});

final dynamicThemeProvider = StateNotifierProvider<DynamicThemeNotifier, ThemeData>((ref) {
  final notifier = DynamicThemeNotifier();
  ref.listen<Song?>(currentSongProvider, (previous, next) {
    notifier.updatePalette(next);
  });
  return notifier;
});

class DynamicThemeNotifier extends StateNotifier<ThemeData> {
  static final Map<String, ThemeData> _themeCache = {};

  DynamicThemeNotifier() : super(DATheme.darkTheme);

  bool _isMonochromeOrVeryDark(Color color) {
    final hsl = HSLColor.fromColor(color);
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    final maxDiff = (r - g).abs() + (g - b).abs() + (b - r).abs();
    return hsl.saturation < 0.16 || hsl.lightness < 0.18 || maxDiff < 32;
  }

  String? _activeProcessingSongId;

  Future<void> updatePalette(Song? song) async {
    if (song == null) {
      state = DATheme.darkTheme;
      return;
    }

    final songId = song.id;
    if (songId != null && _themeCache.containsKey(songId)) {
      state = _themeCache[songId]!;
      return;
    }

    final String? artworkUrl = song.artworkUrl;
    if (artworkUrl == null || artworkUrl.isEmpty) {
      state = DATheme.darkTheme;
      return;
    }

    _activeProcessingSongId = songId;

    try {
      final ImageProvider imageProvider =
          (artworkUrl.startsWith('http://') || artworkUrl.startsWith('https://'))
              ? NetworkImage(artworkUrl)
              : (artworkUrl.startsWith('assets/')
                  ? AssetImage(artworkUrl)
                  : FileImage(File(artworkUrl))) as ImageProvider;

      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        ResizeImage(imageProvider, width: 60, height: 60),
        maximumColorCount: 12,
        timeout: const Duration(milliseconds: 1500),
      ).timeout(const Duration(milliseconds: 1500));

      if (_activeProcessingSongId != songId) return;

      final Color dominant = paletteGenerator.dominantColor?.color ?? const Color(0xFF1E1E1E);
      final Color vibrant = paletteGenerator.vibrantColor?.color ?? dominant;
      final Color muted = paletteGenerator.mutedColor?.color ?? dominant;
      final Color darkVibrant = paletteGenerator.darkVibrantColor?.color ?? vibrant;
      final Color darkMuted = paletteGenerator.darkMutedColor?.color ?? muted;

      Color primaryColor;
      Color accentColor;
      Color gradientStart;
      Color gradientMiddle;
      Color gradientEnd;

      final bool isDarkCover = _isMonochromeOrVeryDark(dominant);

      if (isDarkCover) {
        final domHsl = HSLColor.fromColor(dominant);
        final vibHsl = HSLColor.fromColor(vibrant);

        if (vibHsl.saturation > 0.18) {
          primaryColor = vibHsl
              .withSaturation(vibHsl.saturation.clamp(0.6, 0.95))
              .withLightness(vibHsl.lightness.clamp(0.5, 0.75))
              .toColor();
        } else {
          primaryColor = domHsl
              .withSaturation(domHsl.saturation.clamp(0.0, 0.1))
              .withLightness(0.85)
              .toColor();
        }

        final mutHsl = HSLColor.fromColor(muted);
        if (mutHsl.saturation > 0.15) {
          accentColor = mutHsl
              .withSaturation(mutHsl.saturation.clamp(0.4, 0.8))
              .withLightness(mutHsl.lightness.clamp(0.45, 0.65))
              .toColor();
        } else {
          accentColor = domHsl
              .withSaturation(domHsl.saturation.clamp(0.0, 0.1))
              .withLightness(0.55)
              .toColor();
        }

        gradientStart = domHsl
            .withSaturation(domHsl.saturation.clamp(0.02, 0.15))
            .withLightness(0.14)
            .toColor();

        gradientMiddle = domHsl
            .withSaturation(domHsl.saturation.clamp(0.02, 0.12))
            .withLightness(0.08)
            .toColor();

        gradientEnd = domHsl
            .withSaturation(domHsl.saturation.clamp(0.01, 0.08))
            .withLightness(0.04)
            .toColor();
      } else {
        final primaryHsl = HSLColor.fromColor(vibrant);
        primaryColor = primaryHsl
            .withSaturation((primaryHsl.saturation).clamp(0.5, 0.95))
            .withLightness((primaryHsl.lightness).clamp(0.45, 0.70))
            .toColor();

        final accentHsl = HSLColor.fromColor(muted);
        accentColor = accentHsl
            .withSaturation((accentHsl.saturation).clamp(0.45, 0.90))
            .withLightness((accentHsl.lightness).clamp(0.45, 0.70))
            .toColor();

        gradientStart = _darkenForBackground(vibrant, targetLightness: 0.12);
        gradientMiddle = _darkenForBackground(darkVibrant ?? darkMuted, targetLightness: 0.08);
        gradientEnd = _darkenForBackground(dominant, targetLightness: 0.04);
      }

      final bgHsl = HSLColor.fromColor(dominant);
      final surfaceColor = bgHsl
          .withSaturation((bgHsl.saturation * 0.15).clamp(0.0, 0.22))
          .withLightness(0.09)
          .toColor();

      final surfaceCardColor = bgHsl
          .withSaturation((bgHsl.saturation * 0.15).clamp(0.0, 0.22))
          .withLightness(0.12)
          .toColor();

      final surfaceHoverColor = bgHsl
          .withSaturation((bgHsl.saturation * 0.15).clamp(0.0, 0.22))
          .withLightness(0.16)
          .toColor();

      final borderColor = bgHsl
          .withSaturation((bgHsl.saturation * 0.15).clamp(0.0, 0.22))
          .withLightness(0.20)
          .toColor();

      final customExtension = DAThemeExtension(
        background: gradientMiddle,
        surface: surfaceColor,
        surfaceCard: surfaceCardColor,
        surfaceHover: surfaceHoverColor,
        primary: primaryColor,
        primaryButton: primaryColor,
        accent: accentColor,
        textPrimary: Colors.white,
        textSecondary: Colors.white70,
        border: borderColor,
        typography: DATypography.dark,
        gradientStart: gradientStart,
        gradientMiddle: gradientMiddle,
        gradientEnd: gradientEnd,
      );

      final themeData = _buildThemeData(customExtension);
      _themeCache[song.id] = themeData;
      if (_themeCache.length > 30) {
        _themeCache.remove(_themeCache.keys.first);
      }
      state = themeData;
    } catch (e) {
      dev.log('DynamicTheme: Palette extraction failed: $e');
      if (state == DATheme.darkTheme) {
        state = DATheme.darkTheme;
      }
    }
  }

  Color _darkenForBackground(Color color, {required double targetLightness}) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation((hsl.saturation * 0.35).clamp(0.05, 0.4))
        .withLightness(targetLightness)
        .toColor();
  }

  ThemeData _buildThemeData(DAThemeExtension extension) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Funnel Display',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: extension.background,
      colorScheme: ColorScheme.dark(
        primary: extension.primary,
        surface: extension.surface,
        onPrimary: Colors.white,
        onSurface: extension.textPrimary,
        error: Colors.redAccent,
      ),
      extensions: [extension],
    );
  }
}
