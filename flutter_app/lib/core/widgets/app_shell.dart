import 'package:flutter/material.dart';

import 'app_sidebar.dart';

/// Persistent navigation frame for the "inside" routes (see
/// `app_router.dart`'s own `ShellRoute` — hub/list screens get this,
/// forms/leaf/full-bleed screens push outside it). By request: "سايد بار
/// مشابه لواجهة chatgbt" — a permanent left sidebar on wide screens, a
/// slide-in overlay on narrow ones.
///
/// Deliberately NOT a `Scaffold` itself — a plain `Row`/`Stack`. Every
/// routed `child` keeps its own existing `Scaffold`+`AppBar` completely
/// untouched; the sidebar sits *beside* the content, not above/below it,
/// so there's no double-AppBar concern and zero required changes to any
/// of the ~20 screens rendered inside this shell.
class AppShell extends StatefulWidget {
  const AppShell({required this.child, super.key});
  final Widget child;

  static const _breakpoint = 900.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _overlayOpen = false;

  void _toggleOverlay() => setState(() => _overlayOpen = !_overlayOpen);
  void _closeOverlay() => setState(() => _overlayOpen = false);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppShell._breakpoint;
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                if (wide) const SizedBox(width: 280, child: AppSidebar()),
                if (wide) VerticalDivider(width: 1, color: theme.dividerColor),
                Expanded(child: widget.child),
              ],
            ),
            if (!wide) ...[
              // Top-leading menu toggle — not bottom (would collide with
              // HomeScreen's/TaskListScreen's own FABs, both bottom-end).
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _toggleOverlay,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.menu, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
              if (_overlayOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeOverlay,
                    child: Container(color: Colors.black.withValues(alpha: 0.4)),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 280,
                  child: Material(
                    elevation: 8,
                    child: AppSidebar(onNavigate: _closeOverlay),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
