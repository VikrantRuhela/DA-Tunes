import 'package:flutter/material.dart';
import 'tokens.dart';

class DATypography {
  final TextStyle display;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle body;
  final TextStyle caption;

  const DATypography({
    required this.display,
    required this.headline,
    required this.title,
    required this.body,
    required this.caption,
  });

  static const DATypography dark = DATypography(
    display: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 32.0,
      fontWeight: FontWeight.bold,
      color: DATokens.darkTextPrimary,
      letterSpacing: -0.5,
    ),
    headline: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 22.0,
      fontWeight: FontWeight.bold,
      color: DATokens.darkTextPrimary,
      letterSpacing: -0.2,
    ),
    title: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 16.0,
      fontWeight: FontWeight.w600,
      color: DATokens.darkTextPrimary,
    ),
    body: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 14.0,
      fontWeight: FontWeight.normal,
      color: DATokens.darkTextSecondary,
    ),
    caption: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 12.0,
      fontWeight: FontWeight.normal,
      color: DATokens.darkTextSecondary,
    ),
  );

  static const DATypography light = DATypography(
    display: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 32.0,
      fontWeight: FontWeight.bold,
      color: DATokens.lightTextPrimary,
      letterSpacing: -0.5,
    ),
    headline: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 22.0,
      fontWeight: FontWeight.bold,
      color: DATokens.lightTextPrimary,
      letterSpacing: -0.2,
    ),
    title: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 16.0,
      fontWeight: FontWeight.w600,
      color: DATokens.lightTextPrimary,
    ),
    body: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 14.0,
      fontWeight: FontWeight.normal,
      color: DATokens.lightTextSecondary,
    ),
    caption: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 12.0,
      fontWeight: FontWeight.normal,
      color: DATokens.lightTextSecondary,
    ),
  );

  static const DATypography amoled = DATypography(
    display: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 32.0,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      letterSpacing: -0.5,
    ),
    headline: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 22.0,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      letterSpacing: -0.2,
    ),
    title: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 16.0,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
    body: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 14.0,
      fontWeight: FontWeight.normal,
      color: Colors.white70,
    ),
    caption: TextStyle(
      fontFamily: 'Funnel Display',
      fontSize: 12.0,
      fontWeight: FontWeight.normal,
      color: Colors.white70,
    ),
  );
}

class DAThemeExtension extends ThemeExtension<DAThemeExtension> {
  final Color background;
  final Color surface;
  final Color surfaceCard;
  final Color surfaceHover;
  final Color primary;
  final Color primaryButton;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final DATypography typography;
  final Color gradientStart;
  final Color gradientMiddle;
  final Color gradientEnd;

  const DAThemeExtension({
    required this.background,
    required this.surface,
    required this.surfaceCard,
    required this.surfaceHover,
    required this.primary,
    required this.primaryButton,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.typography,
    required this.gradientStart,
    required this.gradientMiddle,
    required this.gradientEnd,
  });

  static const DAThemeExtension dark = DAThemeExtension(
    background: DATokens.darkBackground,
    surface: DATokens.darkSurface,
    surfaceCard: DATokens.darkSurfaceCard,
    surfaceHover: DATokens.darkSurfaceHover,
    primary: DATokens.darkPrimary,
    primaryButton: DATokens.darkPrimaryButton,
    accent: DATokens.darkAccent,
    textPrimary: DATokens.darkTextPrimary,
    textSecondary: DATokens.darkTextSecondary,
    border: DATokens.darkBorder,
    typography: DATypography.dark,
    gradientStart: Color(0xFF000000),
    gradientMiddle: Color(0xFF000000),
    gradientEnd: Color(0xFF000000),
  );

  static const DAThemeExtension light = DAThemeExtension(
    background: DATokens.lightBackground,
    surface: DATokens.lightSurface,
    surfaceCard: DATokens.lightSurfaceCard,
    surfaceHover: DATokens.lightSurfaceHover,
    primary: DATokens.lightPrimary,
    primaryButton: DATokens.lightPrimaryButton,
    accent: DATokens.lightAccent,
    textPrimary: DATokens.lightTextPrimary,
    textSecondary: DATokens.lightTextSecondary,
    border: DATokens.lightBorder,
    typography: DATypography.light,
    gradientStart: Color(0xFFFFFFFF),
    gradientMiddle: Color(0xFFFFFFFF),
    gradientEnd: Color(0xFFFFFFFF),
  );

  static const DAThemeExtension amoled = DAThemeExtension(
    background: Color(0xFF000000),
    surface: Color(0xFF000000),
    surfaceCard: Color(0xFF000000),
    surfaceHover: Color(0xFF111111),
    primary: Color(0xFFFFFFFF),
    primaryButton: Color(0xFF000000),
    accent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    border: Color(0x4DFFFFFF),
    typography: DATypography.amoled,
    gradientStart: Color(0xFF000000),
    gradientMiddle: Color(0xFF000000),
    gradientEnd: Color(0xFF000000),
  );

  @override
  DAThemeExtension copyWith({
    Color? background,
    Color? surface,
    Color? surfaceCard,
    Color? surfaceHover,
    Color? primary,
    Color? primaryButton,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    DATypography? typography,
    Color? gradientStart,
    Color? gradientMiddle,
    Color? gradientEnd,
  }) {
    return DAThemeExtension(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      primary: primary ?? this.primary,
      primaryButton: primaryButton ?? this.primaryButton,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      typography: typography ?? this.typography,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientMiddle: gradientMiddle ?? this.gradientMiddle,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  DAThemeExtension lerp(ThemeExtension<DAThemeExtension>? other, double t) {
    if (other is! DAThemeExtension) return this;
    return DAThemeExtension(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryButton: Color.lerp(primaryButton, other.primaryButton, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      typography: typography,
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientMiddle: Color.lerp(gradientMiddle, other.gradientMiddle, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}

class DATheme {
  DATheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Funnel Display',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DATokens.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: DATokens.darkPrimary,
        surface: DATokens.darkSurface,
        onPrimary: Colors.white,
        onSurface: DATokens.darkTextPrimary,
        error: Colors.redAccent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DATokens.darkPrimaryButton,
          foregroundColor: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DATokens.darkPrimaryButton,
          foregroundColor: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: DATokens.darkPrimaryButton,
        foregroundColor: Colors.white,
      ),
      extensions: const [DAThemeExtension.dark],
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Funnel Display',
      brightness: Brightness.light,
      scaffoldBackgroundColor: DATokens.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: DATokens.lightPrimary,
        surface: DATokens.lightSurface,
        onPrimary: Colors.white,
        onSurface: DATokens.lightTextPrimary,
        error: Colors.redAccent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DATokens.lightPrimaryButton,
          foregroundColor: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DATokens.lightPrimaryButton,
          foregroundColor: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: DATokens.lightPrimaryButton,
        foregroundColor: Colors.white,
      ),
      extensions: const [DAThemeExtension.light],
    );
  }

  static ThemeData get amoledTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Funnel Display',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        surface: Colors.black,
        onPrimary: Colors.black,
        onSurface: Colors.white,
        error: Colors.redAccent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      extensions: const [DAThemeExtension.amoled],
    );
  }

  static ThemeData m3Theme({required Brightness brightness}) {
    final bool isDark = brightness == Brightness.dark;
    final colorScheme = isDark
        ? ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.dark,
          )
        : ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.light,
          );

    final m3Ext = DAThemeExtension(
      background: colorScheme.surface,
      surface: colorScheme.surfaceContainer,
      surfaceCard: colorScheme.surfaceContainerHigh,
      surfaceHover: colorScheme.surfaceContainerHighest,
      primary: colorScheme.primary,
      primaryButton: colorScheme.primary,
      accent: colorScheme.secondary,
      textPrimary: colorScheme.onSurface,
      textSecondary: colorScheme.onSurfaceVariant,
      border: colorScheme.outlineVariant,
      typography: isDark ? DATypography.dark : DATypography.light,
      gradientStart: colorScheme.surface,
      gradientMiddle: colorScheme.surfaceContainer,
      gradientEnd: colorScheme.surfaceContainerLow,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      brightness: brightness,
      scaffoldBackgroundColor: colorScheme.surface,
      colorScheme: colorScheme,
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
        ),
      ),
      extensions: [m3Ext],
    );
  }
}
