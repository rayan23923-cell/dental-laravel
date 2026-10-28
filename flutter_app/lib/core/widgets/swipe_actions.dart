import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One side of a [SwipeActions] row.
class SwipeAction {
  const SwipeAction({required this.icon, required this.label, required this.color, required this.onTriggered});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTriggered;
}

/// Swipe a list row for a quick action, as Telegram's swipe-to-reply
/// (2026-10-28, by request): the row slides, shows the action's icon and
/// label, runs it on release past the threshold, and springs back — it is
/// never removed from the list. [start] is revealed by a swipe toward the
/// reading direction's end, [end] by the other way.
class SwipeActions extends StatelessWidget {
  const SwipeActions({required this.child, required this.rowKey, this.start, this.end, super.key});
  final Widget child;
  final Key rowKey;
  final SwipeAction? start;
  final SwipeAction? end;

  @override
  Widget build(BuildContext context) {
    if (start == null && end == null) return child;
    // DismissDirection is logical: startToEnd drags in the reading
    // direction (right to left in Arabic) and shows `background`.
    SwipeAction? actionFor(DismissDirection d) => d == DismissDirection.startToEnd ? start : end;

    Widget background(SwipeAction? action, AlignmentDirectional alignment) => action == null
        ? const SizedBox.shrink()
        : ColoredBox(
            color: action.color.withValues(alpha: 0.15),
            child: Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(action.icon, color: action.color),
                    const SizedBox(height: 2),
                    Text(
                      action.label,
                      style: TextStyle(color: action.color, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          );

    return Dismissible(
      key: rowKey,
      direction: start != null && end != null
          ? DismissDirection.horizontal
          : start != null
              ? DismissDirection.startToEnd
              : DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.startToEnd: 0.25, DismissDirection.endToStart: 0.25},
      background: background(start, AlignmentDirectional.centerStart),
      secondaryBackground: background(end, AlignmentDirectional.centerEnd),
      confirmDismiss: (direction) async {
        final action = actionFor(direction);
        if (action != null) {
          HapticFeedback.mediumImpact();
          action.onTriggered();
        }
        return false;
      },
      child: child,
    );
  }
}
