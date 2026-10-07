import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../shared/providers/player_providers.dart';
import '../../../../shared/models/music_models.dart';
import '../../../../shared/models/playback_state.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackControllerProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final isShuffle = ref.watch(shuffleProvider);
    final repeatMode = ref.watch(repeatModeProvider);

    final isPlaying = playbackState.status == PlaybackStatus.playing;

    IconData repeatIcon = Icons.repeat_outlined;
    bool isRepeatSelected = false;
    if (repeatMode == RepeatMode.one) {
      repeatIcon = Icons.repeat_one_outlined;
      isRepeatSelected = true;
    } else if (repeatMode == RepeatMode.all) {
      repeatIcon = Icons.repeat_outlined;
      isRepeatSelected = true;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle
        _ControlButton(
          icon: Icons.shuffle_outlined,
          size: DATokens.iconMedium,
          isSelected: isShuffle,
          onPressed: () => controller.toggleShuffle(),
        ),
        const SizedBox(width: DATokens.spacingSmall),

        // Previous
        _ControlButton(
          icon: Icons.skip_previous_outlined,
          size: DATokens.iconLarge,
          onPressed: () => controller.previous(),
        ),
        const SizedBox(width: DATokens.spacingMedium),

        // Play/Pause (Center, larger)
        _ControlButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          size: DATokens.iconLarge + 4,
          isPrimary: true,
          onPressed: () {
            if (isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          },
        ),
        const SizedBox(width: DATokens.spacingMedium),

        // Next
        _ControlButton(
          icon: Icons.skip_next_outlined,
          size: DATokens.iconLarge,
          onPressed: () => controller.next(),
        ),
        const SizedBox(width: DATokens.spacingSmall),

        // Repeat
        _ControlButton(
          icon: repeatIcon,
          size: DATokens.iconMedium,
          isSelected: isRepeatSelected,
          onPressed: () {
            RepeatMode nextMode;
            if (repeatMode == RepeatMode.off) {
              nextMode = RepeatMode.all;
            } else if (repeatMode == RepeatMode.all) {
              nextMode = RepeatMode.one;
            } else {
              nextMode = RepeatMode.off;
            }
            controller.setRepeatMode(nextMode);
          },
        ),
      ],
    );
  }
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final bool isSelected;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.size,
    this.isSelected = false,
    this.isPrimary = false,
    required this.onPressed,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;

    double scale = 1.0;
    if (_isPressed) {
      scale = 0.98;
    } else if (_isHovered) {
      scale = 1.02;
    }

    final duration = _isPressed ? DATokens.durationMedium : DATokens.durationFast;

    final defaultColor = widget.isSelected ? colors.primary : colors.textSecondary;
    final finalColor = widget.isPrimary
        ? colors.primary.contrastingColor
        : (_isHovered ? colors.textPrimary : defaultColor);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: duration,
          curve: DATokens.curveHover,
          child: Container(
            width: widget.isPrimary ? 56.0 : 40.0,
            height: widget.isPrimary ? 56.0 : 40.0,
            decoration: BoxDecoration(
              color: widget.isPrimary
                  ? colors.primary
                  : (_isHovered ? colors.surfaceHover : Colors.transparent),
              shape: BoxShape.circle,
              boxShadow: widget.isPrimary
                  ? [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: _isHovered ? 0.45 : 0.22),
                        blurRadius: _isHovered ? 16.0 : 8.0,
                        spreadRadius: _isHovered ? 2.0 : 0.0,
                        offset: Offset(0, _isHovered ? 6 : 3),
                      )
                    ]
                  : [],
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: finalColor,
            ),
          ),
        ),
      ),
    );
  }
}
