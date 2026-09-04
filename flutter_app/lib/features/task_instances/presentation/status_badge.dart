import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../domain/task_instance_status.dart';

class StatusBadge extends ConsumerWidget {
  const StatusBadge({super.key, required this.status});
  final TaskInstanceStatus status;

  Color _color(BuildContext context) => switch (status) {
        TaskInstanceStatus.pending => Colors.orange,
        TaskInstanceStatus.assigned => Theme.of(context).colorScheme.primary,
        TaskInstanceStatus.completed => Colors.green,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _color(context);
    final t = ref.watch(translationsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(status.label(t), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
