import 'package:flutter/material.dart';

/// Instagram's real, well-known brand colours — not an approximation from
/// a seed colour. `useMaterial3`'s `ColorScheme.fromSeed` was deliberately
/// not used here: it derives a full tonal palette algorithmically, which
/// drifts from the exact greys/blacks/blue Instagram's own app actually
/// uses (`#0095F6` action blue, `#262626` near-black text rather than pure
/// black, `#8E8E8E` secondary grey, `#DBDBDB`/`#262626` hairline borders).
/// Built by hand instead, per field, so every token traces to a real
/// Instagram UI colour rather than a generated shade.
class InstagramColors {
  const InstagramColors._();

  static const blue = Color(0xFF0095F6); // primary action colour — buttons, links, focus rings
  static const red = Color(0xFFED4956); // like/error red
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000); // true black — dark-mode background
  static const nearBlack = Color(0xFF262626); // body text on light backgrounds
  static const offWhite = Color(0xFFFAFAFA); // light-mode field/surface fill
  static const darkSurface = Color(0xFF121212); // dark-mode field/surface fill (not pure black, for depth)
  static const gray = Color(0xFF8E8E8E); // secondary/muted text, both modes
  static const lightBorder = Color(0xFFDBDBDB); // hairline borders/dividers, light mode
  static const darkBorder = Color(0xFF262626); // hairline borders/dividers, dark mode

  /// The Instagram wordmark/story-ring gradient — used sparingly (an
  /// accent highlight, not a UI-wide colour), matching how Instagram's own
  /// app actually spends it: the logo and the unseen-story ring, never
  /// buttons or backgrounds.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFEDA75),
      Color(0xFFFA7E1E),
      Color(0xFFD62976),
      Color(0xFF962FBF),
      Color(0xFF4F5BD5),
    ],
  );
}

const _radius = 8.0; // Instagram's buttons/fields/cards — a subtly rounded
// rectangle, not the pill shape Material's defaults reach for.

OutlineInputBorder _fieldBorder(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radius),
      borderSide: BorderSide(color: color, width: width),
    );

ThemeData _buildTheme({required bool dark}) {
  final background = dark ? InstagramColors.black : InstagramColors.white;
  final surface = dark ? InstagramColors.darkSurface : InstagramColors.offWhite;
  final onSurface = dark ? InstagramColors.offWhite : InstagramColors.nearBlack;
  final border = dark ? InstagramColors.darkBorder : InstagramColors.lightBorder;

  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: InstagramColors.blue,
    onPrimary: InstagramColors.white,
    // A pale (or, dark, deep) tint of the blue (2026-10-21). Unset, it fell
    // back to primary itself, so selected cards were solid blue and the
    // blue text on them vanished.
    primaryContainer: dark ? const Color(0xFF0B3550) : const Color(0xFFE3F2FD),
    onPrimaryContainer: dark ? const Color(0xFFD6ECFF) : const Color(0xFF0B3550),
    secondary: onSurface,
    onSecondary: background,
    surface: dark ? InstagramColors.darkSurface : InstagramColors.white,
    onSurface: onSurface,
    error: InstagramColors.red,
    onError: InstagramColors.white,
    outline: border,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    dividerColor: border,
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: onSurface, fontSize: 18, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(color: onSurface),
    ),

    // Flat, hairline-bordered cards — Instagram doesn't use Material
    // elevation shadows anywhere in its own UI.
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? InstagramColors.darkSurface : InstagramColors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(color: border),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: _fieldBorder(border),
      enabledBorder: _fieldBorder(border),
      disabledBorder: _fieldBorder(border),
      focusedBorder: _fieldBorder(InstagramColors.blue, width: 1.5),
      errorBorder: _fieldBorder(InstagramColors.red),
      focusedErrorBorder: _fieldBorder(InstagramColors.red, width: 1.5),
      labelStyle: TextStyle(color: InstagramColors.gray),
      hintStyle: TextStyle(color: InstagramColors.gray),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: InstagramColors.blue,
        foregroundColor: InstagramColors.white,
        disabledBackgroundColor: InstagramColors.blue.withValues(alpha: 0.3),
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: BorderSide(color: border),
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: InstagramColors.blue,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: InstagramColors.blue,
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      labelStyle: TextStyle(color: onSurface, fontSize: 13, fontWeight: FontWeight.w500),
      secondaryLabelStyle: const TextStyle(color: InstagramColors.white, fontSize: 13, fontWeight: FontWeight.w500),
      checkmarkColor: InstagramColors.white,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? InstagramColors.white : InstagramColors.gray,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? InstagramColors.blue : border,
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? InstagramColors.blue : InstagramColors.gray,
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: InstagramColors.blue),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: onSurface,
      contentTextStyle: TextStyle(color: background),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    ),

    textTheme: Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(bodyColor: onSurface, displayColor: onSurface)
        .copyWith(
          titleLarge: TextStyle(color: onSurface, fontWeight: FontWeight.w700, fontSize: 22),
          titleMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w600, fontSize: 16),
          bodySmall: TextStyle(color: InstagramColors.gray, fontSize: 12),
        ),
  );
}

final ThemeData instagramLightTheme = _buildTheme(dark: false);
final ThemeData instagramDarkTheme = _buildTheme(dark: true);
