import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/locale_controller.dart';

/// Today / this week / this month quick ranges beside the date filters
/// (2026-11-01, by request). The week starts on Saturday. Tapping the
/// active chip clears the range ([onChanged] gets null).
class PeriodChips extends ConsumerWidget {
  const PeriodChips({super.key, required this.from, required this.to, required this.onChanged});

  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTimeRange?> onChanged;

  static DateTimeRange rangeFor(String key, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (key) {
      // DateTime.weekday: Monday = 1 … Saturday = 6, Sunday = 7.
      'week' => DateTimeRange(start: today.subtract(Duration(days: (today.weekday + 1) % 7)), end: today),
      'month' => DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
      _ => DateTimeRange(start: today, end: today),
    };
  }

  static bool _sameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    const items = [
      ('today', Icons.today_outlined, 'periods.today'),
      ('week', Icons.date_range_outlined, 'periods.week'),
      ('month', Icons.calendar_month_outlined, 'periods.month'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final (key, icon, label) in items)
          Builder(builder: (context) {
            final r = rangeFor(key);
            final active = _sameDay(from, r.start) && _sameDay(to, r.end);
            return FilterChip(
              avatar: Icon(icon, size: 18),
              label: Text(t[label]!),
              selected: active,
              showCheckmark: false,
              shape: const StadiumBorder(),
              onSelected: (_) => onChanged(active ? null : r),
            );
          }),
      ],
    );
  }
}
