import 'package:flutter/material.dart';

/// One motion vocabulary for the whole app.
///
/// Enter is short, exit is shorter, press is fast enough to feel physical.
abstract final class SoftMotion {
  static const easeOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const enter = Duration(milliseconds: 240);
  static const exit = Duration(milliseconds: 180);
  static const press = Duration(milliseconds: 110);
}

/// Three corner radii. Nothing in the app may invent a fourth.
abstract final class SoftShape {
  static const inset = 14.0;
  static const control = 18.0;
  static const surface = 24.0;

  static const insetRadius = BorderRadius.all(Radius.circular(inset));
  static const controlRadius = BorderRadius.all(Radius.circular(control));
  static const surfaceRadius = BorderRadius.all(Radius.circular(surface));
}

/// Spacing scale. Every gap in the app is one of these.
abstract final class SoftSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const huge = 40.0;

  /// Horizontal page gutter.
  static const gutter = 20.0;
}

/// Resolved colours for the current brightness.
///
/// Read with `SoftPalette.of(context)` — feature code never hardcodes a
/// colour, so light and dark stay in step by construction.
@immutable
class SoftPalette extends ThemeExtension<SoftPalette> {
  const SoftPalette({
    required this.base,
    required this.faceHigh,
    required this.faceLow,
    required this.well,
    required this.shadowLight,
    required this.shadowDark,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.hairline,
  });

  /// Page background. Raised surfaces are moulded out of this, not laid on it.
  final Color base;

  /// Lit and shaded faces of a raised surface (top-left is lit).
  final Color faceHigh;
  final Color faceLow;

  /// Floor of an inset surface. Reads as a hole because it is darker than
  /// both faces around it.
  final Color well;

  /// The two light sources every depth effect in the app is built from.
  final Color shadowLight;
  final Color shadowDark;

  /// Body text.
  final Color ink;

  /// Secondary text. Still passes AA against [base].
  final Color muted;

  /// Fill for the one primary action per screen. Never used as a text colour.
  final Color accent;
  final Color onAccent;

  final Color danger;
  final Color hairline;

  static const _light = SoftPalette(
    base: Color(0xFFE7EAF0),
    faceHigh: Color(0xFFEFF1F6),
    faceLow: Color(0xFFDFE3EB),
    well: Color(0xFFDADFE8),
    shadowLight: Color(0xF2FFFFFF),
    shadowDark: Color(0x8CA6AFC0),
    ink: Color(0xFF1B2130),
    muted: Color(0xFF5B6577),
    accent: Color(0xFF5566DE),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFA8332F),
    hairline: Color(0xFFCFD5E0),
  );

  static const _dark = SoftPalette(
    base: Color(0xFF23272F),
    faceHigh: Color(0xFF2A2F38),
    faceLow: Color(0xFF1E222A),
    well: Color(0xFF1A1E25),
    shadowLight: Color(0x99353B47),
    shadowDark: Color(0xD912151B),
    ink: Color(0xFFE5E9F0),
    muted: Color(0xFF98A2B4),
    accent: Color(0xFF5566DE),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFE8827E),
    hairline: Color(0xFF333945),
  );

  static SoftPalette forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? _dark : _light;
  }

  static SoftPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SoftPalette>() ?? forBrightness(theme.brightness);
  }

  /// Top-left lit gradient shared by every raised surface.
  Gradient get raisedFace => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [faceHigh, faceLow],
  );

  /// The one raised-shadow recipe. [depth] scales it for small controls.
  List<BoxShadow> raisedShadow({double depth = 1}) => [
    BoxShadow(
      color: shadowDark,
      offset: Offset(5 * depth, 5 * depth),
      blurRadius: 12 * depth,
    ),
    BoxShadow(
      color: shadowLight,
      offset: Offset(-5 * depth, -5 * depth),
      blurRadius: 12 * depth,
    ),
  ];

  /// A thing that sits above the page instead of being moulded out of it: no
  /// lit edge, and two shadow stops the way a real object reads — a tight one
  /// for the contact edge, a wide soft one for the cast.
  List<BoxShadow> get floatingShadow => [
    BoxShadow(color: shadowDark, offset: const Offset(0, 2), blurRadius: 6),
    BoxShadow(color: shadowDark, offset: const Offset(0, 12), blurRadius: 32),
  ];

  @override
  SoftPalette copyWith({
    Color? base,
    Color? faceHigh,
    Color? faceLow,
    Color? well,
    Color? shadowLight,
    Color? shadowDark,
    Color? ink,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? hairline,
  }) {
    return SoftPalette(
      base: base ?? this.base,
      faceHigh: faceHigh ?? this.faceHigh,
      faceLow: faceLow ?? this.faceLow,
      well: well ?? this.well,
      shadowLight: shadowLight ?? this.shadowLight,
      shadowDark: shadowDark ?? this.shadowDark,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      hairline: hairline ?? this.hairline,
    );
  }

  @override
  SoftPalette lerp(ThemeExtension<SoftPalette>? other, double t) {
    if (other is! SoftPalette) {
      return this;
    }
    return SoftPalette(
      base: Color.lerp(base, other.base, t)!,
      faceHigh: Color.lerp(faceHigh, other.faceHigh, t)!,
      faceLow: Color.lerp(faceLow, other.faceLow, t)!,
      well: Color.lerp(well, other.well, t)!,
      shadowLight: Color.lerp(shadowLight, other.shadowLight, t)!,
      shadowDark: Color.lerp(shadowDark, other.shadowDark, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
    );
  }
}

ThemeData lectureTheme({required Brightness brightness}) {
  final p = SoftPalette.forBrightness(brightness);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.danger,
    onError: p.onAccent,
    surface: p.base,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    outline: p.hairline,
    outlineVariant: p.hairline,
    surfaceContainerHighest: p.faceHigh,
  );

  final text = TextTheme(
    displaySmall: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.1,
      color: p.ink,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.15,
      color: p.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.3,
      color: p.ink,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      height: 1.35,
      color: p.muted,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.55,
      color: p.ink,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: p.ink,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: p.muted,
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.2,
      color: p.ink,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      height: 1.35,
      color: p.muted,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.base,
    canvasColor: p.base,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.base,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    // Text fields are the app's only inset control: they read as a well
    // pressed into the surface, so they carry no border of their own.
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SoftSpace.lg,
        vertical: SoftSpace.md,
      ),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      hintStyle: text.bodyMedium?.copyWith(color: p.muted),
      labelStyle: text.bodySmall,
      floatingLabelStyle: text.bodySmall,
    ),
    dividerTheme: DividerThemeData(
      color: p.hairline,
      thickness: 1,
      space: SoftSpace.xxl,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.shadowDark,
      circularTrackColor: p.shadowDark,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.base,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: SoftShape.surfaceRadius,
      ),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
      shape: const RoundedRectangleBorder(
        borderRadius: SoftShape.controlRadius,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? p.accent : p.muted;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? p.onAccent : p.faceHigh;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? p.accent : p.faceLow;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : p.hairline;
      }),
    ),
  );
}

/// Readable measure on a desk display; full width on a phone.
double lectureContentWidth(double maxWidth) {
  if (maxWidth >= 1200) {
    return 880;
  }
  if (maxWidth >= 800) {
    return 720;
  }
  return maxWidth;
}
