import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/academic_sessions_admin/presentation/academic_sessions_providers.dart';
import '../i18n/locale_controller.dart';

/// "العام الدراسي النشط: {name}" — shown on the Doctors/Groups/Tasks/
/// Task-Progress admin screens and the dashboard, mirroring the
/// `currentSession` banner the web app's equivalent pages already render
/// (`Doctors/Index.vue`, `Groups/Index.vue`, `Tasks/Index.vue`, and now
/// `TaskProgress/Index.vue`/`Dashboard.vue`, added alongside this).
/// Extracted as one shared widget from the start (5 call sites) rather
/// than duplicated, matching this codebase's own "extract once 3+ places
/// need it" convention (see `CascadingDropdown`'s doc comment).
///
/// Renders nothing while loading, on error, or when no academic year is
/// active — same "never blocks, only informs" contract as
/// `clinicSettingsProvider`; a missing/failed fetch here must not push
/// the rest of the screen around or show an error banner for what's
/// purely decorative context.
class AcademicYearBanner extends ConsumerWidget {
  // Defaults to the 12px-sides/8px-top inset that fits directly under an
  // unpadded Scaffold body Column (the four admin list screens). Callers
  // that already sit inside their own padded container (e.g.
  // home_screen.dart's `ListView(padding: all(16))`) pass a narrower
  // margin instead, so the two insets don't stack.
  const AcademicYearBanner({super.key, this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 0)});

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(currentAcademicYearProvider).valueOrNull;
    if (year == null) return const SizedBox.shrink();

    final t = ref.watch(translationsProvider);
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Text.rich(
            TextSpan(
              text: t['academicYear.active']!,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              children: [
                TextSpan(text: year.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
