import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../app/theme/tokens.dart';
import '../../../../../shared/providers/player_providers.dart';

class CollapseButton extends StatefulWidget {
  const CollapseButton({super.key});

  @override
  State<CollapseButton> createState() => _CollapseButtonState();
}

class _CollapseButtonState extends State<CollapseButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final colors = context.daColors;

        double scale = 1.0;
        if (_isPressed) {
          scale = 0.98;
        } else if (_isHovered) {
          scale = 1.02;
        }

        final duration = _isPressed ? DATokens.durationMedium : DATokens.durationFast;

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
            onTap: () => ref.read(immersiveModeProvider.notifier).state = false,
            child: AnimatedScale(
              scale: scale,
              duration: duration,
              curve: DATokens.curveHover,
              child: Container(
                padding: const EdgeInsets.all(DATokens.spacingSmall + 2.0),
                decoration: BoxDecoration(
                  color: _isHovered ? colors.surfaceHover : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isHovered ? colors.border : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Icon(
                  Icons.close_fullscreen_outlined,
                  size: DATokens.iconMedium,
                  color: _isHovered ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
