import 'package:flutter/material.dart';

/// Secondary text and faint marks that follow the theme (2026-10-21):
/// screens used Colors.black54 / black38 / black12, which vanish on the
/// dark theme's black background.
extension MutedColors on BuildContext {
  Color get _onSurface => Theme.of(this).colorScheme.onSurface;

  /// Secondary text (was Colors.black54).
  Color get mutedText => _onSurface.withValues(alpha: 0.6);

  /// Hints, captions and chevrons (was Colors.black38 / black26).
  Color get faintText => _onSurface.withValues(alpha: 0.42);

  /// Progress-bar tracks and empty fills (was Colors.black12).
  Color get track => _onSurface.withValues(alpha: 0.12);
}
