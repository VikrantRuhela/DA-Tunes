import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../app/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/player_providers.dart';
import '../../../../shared/providers/library_providers.dart';
import '../../../../core/services/device_memory_manager.dart';
import '../../../../shared/animations/motion_system.dart';

class PlayerBackground extends ConsumerWidget {
  final Widget child;

  const PlayerBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final isImmersive = ref.watch(immersiveModeProvider);
    final showAlbumArt = ref.watch(showAlbumArtBackgroundProvider);
    final isLowRam = !ref.watch(enableExtraEffectsProvider);

    final duration = ref.scaledDuration(DAMotion.playerDuration);
    final curve = isImmersive ? Curves.easeOutCubic : Curves.easeInOutCubic;

    final borderRadius = isImmersive
        ? BorderRadius.zero
        : const BorderRadius.only(
            topLeft: Radius.circular(DATokens.radiusXXLarge),
            bottomLeft: Radius.circular(DATokens.radiusXXLarge),
          );

    final border = isImmersive
        ? const Border.symmetric(
            horizontal: BorderSide(color: Colors.transparent, width: 0.0),
            vertical: BorderSide(color: Colors.transparent, width: 0.0),
          )
        : Border(
            left: BorderSide(
              color: colors.border,
              width: 1.0,
            ),
          );

    Widget content = child;
    if (!isImmersive && showAlbumArt) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isLowRam ? 16.0 : 25.0,
            sigmaY: isLowRam ? 16.0 : 25.0,
          ),
          child: child,
        ),
      );
    }

    return AnimatedContainer(
      duration: duration,
      curve: curve,
      height: double.infinity,
      decoration: BoxDecoration(
        color: isImmersive ? Colors.transparent : colors.surface.withValues(alpha: 0.55),
        borderRadius: borderRadius,
        border: isImmersive
            ? border
            : Border(
                left: BorderSide(
                  color: colors.border.withValues(alpha: 0.4),
                  width: 1.0,
                ),
              ),
      ),
      child: content,
    );
  }
}
