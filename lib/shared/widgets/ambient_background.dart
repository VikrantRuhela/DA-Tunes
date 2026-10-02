import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/extensions/context_extensions.dart';
import '../providers/player_providers.dart';
import '../providers/library_providers.dart';
import '../providers/theme_providers.dart';

class BlurredBackgroundCache {
  static final Map<String, Widget> _cache = {};

  static Widget get(String imageUrl) {
    return _cache.putIfAbsent(imageUrl, () => BlurredBackground(imageUrl: imageUrl));
  }
}

class BlurredBackground extends StatelessWidget {
  final String imageUrl;

  const BlurredBackground({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: Colors.black,
        ),
        Opacity(
          opacity: 0.85,
          child: imageUrl.startsWith('http://') || imageUrl.startsWith('https://')
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                )
              : (imageUrl.startsWith('assets/')
                  ? Image.asset(
                      imageUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                    )
                  : Image.file(
                      File(imageUrl),
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                    )),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.4,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35),
              ],
              stops: const [0.35, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class AmbientBackground extends ConsumerWidget {
  final Widget child;

  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final themeMode = ref.watch(appThemeModeProvider);
    final showAlbumArt = ref.watch(showAlbumArtBackgroundProvider);
    final currentSong = ref.watch(currentSongProvider);
    final String? artworkUrl = currentSong?.artworkUrl;

    Widget backgroundWidget;

    if (themeMode == AppThemeMode.amoled) {
      backgroundWidget = Container(color: Colors.black);
    } else if (themeMode == AppThemeMode.material3) {
      backgroundWidget = Container(color: Theme.of(context).colorScheme.surface);
    } else if (showAlbumArt && artworkUrl != null && artworkUrl.isNotEmpty) {
      backgroundWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: Container(
          key: ValueKey(artworkUrl),
          child: BlurredBackgroundCache.get(artworkUrl),
        ),
      );
    } else {
      backgroundWidget = Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.background,
                  Colors.black,
                ],
              ),
            ),
          ),
          Positioned(
            left: -150,
            top: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.15),
                    colors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -200,
            bottom: -100,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.accent.withValues(alpha: 0.12),
                    colors.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.4,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: backgroundWidget),
        Positioned.fill(child: child),
      ],
    );
  }
}
