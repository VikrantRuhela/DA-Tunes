import 'package:flutter/material.dart';
import '../../app/theme/theme.dart';

extension DAContextExtension on BuildContext {
  ThemeData get theme => Theme.of(this);

  DAThemeExtension get daColors {
    final ext = Theme.of(this).extension<DAThemeExtension>();
    assert(ext != null, 'DAThemeExtension was not found in Theme. Make sure you set theme in MaterialApp.');
    return ext!;
  }

  DATypography get daTypography => daColors.typography;
}

extension ColorContrast on Color {
  Color get contrastingColor {
    return ThemeData.estimateBrightnessForColor(this) == Brightness.light
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
  }

  Color get contrastingColorMuted {
    return ThemeData.estimateBrightnessForColor(this) == Brightness.light
        ? const Color(0xFF666666)
        : const Color(0xB3FFFFFF);
  }
}
