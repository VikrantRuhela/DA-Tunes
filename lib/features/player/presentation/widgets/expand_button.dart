import 'package:flutter/material.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../app/theme/tokens.dart';

class ExpandButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const ExpandButton({
    super.key,
    this.onPressed,
  });

  @override
  State<ExpandButton> createState() => _ExpandButtonState();
}

class _ExpandButtonState extends State<ExpandButton> {
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: duration,
          curve: DATokens.curveHover,
          child: Container(
            padding: const EdgeInsets.all(DATokens.spacingSmall),
            decoration: BoxDecoration(
              color: _isHovered ? colors.surfaceHover : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.open_in_full_outlined,
              size: DATokens.iconMedium,
              color: _isHovered ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
