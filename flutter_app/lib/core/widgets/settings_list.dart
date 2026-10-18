import 'package:flutter/material.dart';

/// Section label above a settings card (Telegram-style, 2026-10-14).
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, bottom: 6),
      child: Text(
        text,
        style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      // hardEdge, not antiAlias (2026-10-18): the permissions screen showed
      // only its upper half on an Android phone, and an anti-aliased clip
      // of a tall card is the likely cause (the layout itself measures fine).
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class SettingsSectionIcon extends StatelessWidget {
  const SettingsSectionIcon({super.key, required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: Colors.white, size: 20),
  );
}

/// A collapsible settings row: icon, title, summary of the current values
/// and a chevron. Closed fields stay mounted (just hidden) so the form still
/// validates them.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.summary,
    required this.open,
    required this.onToggle,
    required this.children,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SettingsSectionIcon(icon: icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        Visibility(
          visible: open,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}
