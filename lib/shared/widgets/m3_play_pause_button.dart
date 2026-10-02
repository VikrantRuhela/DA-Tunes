import 'package:flutter/material.dart';

class M3PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const M3PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.size = 72.0,
    this.iconSize = 38.0,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? colorScheme.primary;
    final fg = foregroundColor ?? colorScheme.onPrimary;

    final shape = isPlaying
        ? StarBorder(
            points: 7,
            pointRounding: 0.35,
            valleyRounding: 0.35,
            innerRadiusRatio: 0.76,
          )
        : const CircleBorder();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: bg,
        shape: shape,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: iconSize,
        color: fg,
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        onPressed: onPressed,
      ),
    );
  }
}
