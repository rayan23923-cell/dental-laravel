import 'package:flutter/material.dart';
import '../theme/muted_colors.dart';

/// Chat-list rows (2026-10-13, by request: the reference-data screens styled
/// like the permissions list, "انستقرام او تليجرام"), matching the web's
/// `Components/ChatList`: a coloured avatar (an icon, or the first letter of
/// [title]), the name, a line of [ChatChip]s and optional trailing actions.
class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.title,
    required this.color,
    this.icon,
    this.imageUrl,
    this.subtitle,
    this.chips = const [],
    this.actions = const [],
    this.onTap,
    this.leading,
    this.selected = false,
  });

  final String title;
  final Color color;
  final IconData? icon;

  /// A photo for the avatar (e.g. a doctor's profile image), over [color].
  final String? imageUrl;
  final String? subtitle;
  final List<Widget> chips;
  final List<Widget> actions;
  final VoidCallback? onTap;

  /// Shown before the avatar, e.g. a selection checkbox.
  final Widget? leading;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

    return Material(
      color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 4)],
              CircleAvatar(
                radius: 24,
                backgroundColor: color,
                foregroundColor: Colors.white,
                backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
                child: imageUrl != null
                    ? null
                    : icon != null
                    ? Icon(icon, size: 24)
                    : Text(initial, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          style: TextStyle(fontSize: 12, color: context.mutedText),
                          overflow: TextOverflow.ellipsis),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 4, children: chips),
                    ],
                  ],
                ),
              ),
              ...actions,
              if (actions.isEmpty && onTap != null) Icon(Icons.chevron_left, color: context.faintText),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small coloured label under a [ChatListTile]'s name.
class ChatChip extends StatelessWidget {
  const ChatChip({super.key, required this.label, this.icon, this.color = Colors.blueGrey});

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// A round icon-only action at the end of a [ChatListTile].
class ChatAction extends StatelessWidget {
  const ChatAction({super.key, required this.icon, required this.tooltip, required this.onPressed, this.danger = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      color: danger ? Colors.red.shade400 : context.mutedText,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

/// The rounded search pill above a chat list.
class ChatSearchField extends StatelessWidget {
  const ChatSearchField({super.key, required this.hintText, this.controller, this.onChanged, this.onSubmitted});

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.04),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      ),
    );
  }
}

const _rotation = <Color>[
  Colors.indigo,
  Colors.green,
  Colors.lightBlue,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.deepPurple,
];

/// A stable colour per id, so rows of one list don't all share one colour.
Color chatToneFor(int id) => _rotation[id.abs() % _rotation.length];

/// A thin divider indented past the avatar, between [ChatListTile]s.
const chatDivider = Divider(height: 1, indent: 76);
