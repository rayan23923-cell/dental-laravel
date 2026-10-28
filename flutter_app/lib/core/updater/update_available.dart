import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop_update_checker.dart';

/// A newer build found by the startup check (2026-10-28, by request): the
/// footer's account tab and the account sheet's update row show a badge
/// while it is set. Null when up to date or not checked.
final updateAvailableProvider = StateProvider<DesktopUpdateInfo?>((ref) => null);
