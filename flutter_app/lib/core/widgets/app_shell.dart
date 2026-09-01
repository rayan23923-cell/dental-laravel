import 'package:flutter/material.dart';

import 'app_sidebar.dart';

/// Persistent navigation frame for the "inside" routes (see
/// `app_router.dart`'s own `ShellRoute` — hub/list screens get this,
/// forms/leaf/full-bleed screens push outside it). By request: "سايد بار
/// مشابه لواجهة chatgbt" — a permanent left sidebar on wide screens.
///
/// On narrow screens (revision, by request — "فعل وضعية السحب للسايدبار
/// للمشاهدة والإخفاء... كما في جي بيتي او تطبيق كلاود"): a drag-to-reveal
/// *push* drawer, not an overlay. ChatGPT's/Claude's own mobile apps don't
/// slide a panel on top of a dimmed, static screen — the sidebar sits
/// behind the content, and dragging the content itself (from anywhere, not
/// just the edge) slides it aside to reveal the sidebar underneath, in
/// perfect sync with the finger the whole way, not just triggered by a
/// tap. Built with a plain `AnimationController` driven manually during
/// the drag (`+=` on `onHorizontalDragUpdate`, `animateTo` on release) —
/// the same technique Flutter's own `Drawer` uses internally, just
/// exposed here since the built-in `Drawer`/`Scaffold.drawer` pairing
/// can't be wired without a shared `Scaffold` (none exists across the
/// ~20 screens this shell wraps — see the class-level "Deliberately NOT a
/// `Scaffold`" note below for why that's fine).
///
/// Deliberately NOT a `Scaffold` itself — a plain `Row`/`Stack`/
/// `Transform`. Every routed `child` keeps its own existing
/// `Scaffold`+`AppBar` completely untouched; the sidebar sits beside (wide)
/// or behind (narrow) the content, never above/below it, so there's no
/// double-AppBar concern and zero required changes to any of the ~20
/// screens rendered inside this shell.
class AppShell extends StatefulWidget {
  const AppShell({required this.child, super.key});
  final Widget child;

  static const _breakpoint = 900.0;
  static const _sidebarWidth = 280.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() => _controller.animateTo(1, curve: Curves.easeOut);
  void _close() => _controller.animateTo(0, curve: Curves.easeOut);
  void _toggle() => _controller.value > 0.5 ? _close() : _open();

  // RTL-aware: in an RTL layout (this app is Arabic) the sidebar sits at
  // the trailing/right edge, matching the permanent-sidebar placement
  // Flutter's own Row mirroring already gives it on wide screens — so
  // "open" is a drag toward the leading/left edge there, the opposite of
  // LTR. `primaryDelta` is the raw physical-pixel delta; flipping its
  // sign for RTL is what keeps the panel tracking the same physical
  // finger movement in both directions.
  void _onDragUpdate(DragUpdateDetails details, bool rtl) {
    final delta = details.primaryDelta ?? 0;
    final normalized = rtl ? -delta : delta;
    _controller.value += normalized / AppShell._sidebarWidth;
  }

  void _onDragEnd(DragEndDetails details, bool rtl) {
    final velocity = rtl
        ? -details.velocity.pixelsPerSecond.dx
        : details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() > 300) {
      velocity > 0 ? _open() : _close();
    } else {
      _controller.value > 0.5 ? _open() : _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppShell._breakpoint;
    final theme = Theme.of(context);

    if (wide) {
      return ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Row(
            children: [
              const SizedBox(
                width: AppShell._sidebarWidth,
                child: AppSidebar(),
              ),
              VerticalDivider(width: 1, color: theme.dividerColor),
              Expanded(child: widget.child),
            ],
          ),
        ),
      );
    }

    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The toggle button lives inside the pushed-content Stack, which sits
    // *outside* `content`'s own `SafeArea` (only `widget.child` itself is
    // wrapped — see the `AnimatedBuilder.child` comment below for why).
    // A bare `top: 8` therefore measured from the physical screen edge,
    // under the status bar/notch — confirmed live on a real iPhone: the
    // button visibly overlapped the clock/battery icons. Adding the real
    // top inset here fixes it without wrapping the button in its own
    // nested `SafeArea` (which would also have needed `right`/`left: false`
    // to avoid double-insetting a button that's already offset by 8px).
    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: GestureDetector(
        // Captured from anywhere on the screen, not just an edge strip —
        // matching ChatGPT's/Claude's own mobile drag area; none of this
        // shell's screens use a competing horizontal gesture (no
        // PageView/horizontal ListView on any of the wrapped hub/list
        // screens), so a whole-screen capture is safe here.
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, rtl),
        onHorizontalDragEnd: (d) => _onDragEnd(d, rtl),
        child: AnimatedBuilder(
          animation: _controller,
          // The routed screen itself is built once and reused across every
          // animation tick via AnimatedBuilder's own `child` — only the
          // Transform/Positioned wrapper around it repaints while dragging,
          // not the (potentially expensive) screen subtree.
          child: SafeArea(child: widget.child),
          builder: (context, content) {
            final t = _controller.value.clamp(0.0, 1.0);
            final shift = t * AppShell._sidebarWidth * (rtl ? -1 : 1);

            return Stack(
              children: [
                // Sidebar — full screen height, ignoring the outer SafeArea
                // (by request: "يكون على طول الشاشة السايدبار"), sitting
                // *behind* the content at the trailing edge; its own
                // internal SafeArea keeps the header/nav list clear of the
                // status bar/notch without shrinking the panel's own
                // full-bleed background.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: rtl ? null : 0,
                  right: rtl ? 0 : null,
                  width: AppShell._sidebarWidth,
                  // Elevation only while at least partly visible — a
                  // constant `elevation: 4` here was found live to bleed a
                  // faint shadow line through at the sidebar's edge even
                  // fully closed (t=0), when the pushed content sitting
                  // *above* it in this Stack should have hidden it
                  // completely; scaling elevation down to 0 with `t` removes
                  // any shadow to bleed in the first place rather than
                  // relying on the content layer to fully mask it.
                  child: Material(
                    elevation: 4 * t,
                    child: SafeArea(child: AppSidebar(onNavigate: _close)),
                  ),
                ),
                // Content, pushed aside in sync with the drag/animation.
                // `SizedBox.expand` forces the inner Stack to the full
                // screen size — without it, `Transform`'s non-positioned
                // Stack child gets merely *loose* constraints, and the
                // routed screen underneath was found live to shrink-wrap
                // to a fraction of the real width instead of filling it
                // (a real bug caught this way, not by inspection alone).
                Transform.translate(
                  offset: Offset(shift, 0),
                  child: SizedBox.expand(
                    child: Stack(
                      children: [
                        AbsorbPointer(absorbing: t > 0.02, child: content),
                        if (t > 0.02)
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: _close,
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.35 * t),
                              ),
                            ),
                          ),
                        // Top-leading menu toggle — not bottom (would collide
                        // with HomeScreen's/TaskListScreen's own bottom-end
                        // FABs). Icon swaps to a close "X" once open.
                        Positioned(
                          top: topInset + 8,
                          left: rtl ? null : 8,
                          right: rtl ? 8 : null,
                          child: Material(
                            color: theme.colorScheme.primary,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _toggle,
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Icon(
                                  t > 0.5 ? Icons.close : Icons.menu,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
