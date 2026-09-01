import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A rotating gradient ring — Instagram's own signature "story ring" look,
/// reused as a loading indicator (by request, 2026-09-01: "عدل loading
/// animation عند تسجيل الدخول واجعلها متوافقة مع instagram loading").
/// Replaces the plain single-colour `CircularProgressIndicator` on the
/// login screen (and its "forgot password" dialog) with the same 5-stop
/// `InstagramColors.gradient` already used everywhere else in this app as
/// an accent (the sidebar header badge, the profile "story ring", the
/// selected-nav indicator bar — see `app_sidebar.dart`) — a loading
/// spinner is exactly that same kind of small, recognisable accent
/// moment, not a full-UI repaint, so it fits the app's own established
/// "gradient = accent only" rule rather than breaking it.
class InstagramSpinner extends StatefulWidget {
  const InstagramSpinner({this.size = 20, this.strokeWidth = 2.5, super.key});
  final double size;
  final double strokeWidth;

  @override
  State<InstagramSpinner> createState() => _InstagramSpinnerState();
}

class _InstagramSpinnerState extends State<InstagramSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _GradientRingPainter(strokeWidth: widget.strokeWidth),
      ),
    );
  }
}

class _GradientRingPainter extends CustomPainter {
  _GradientRingPainter({required this.strokeWidth});
  final double strokeWidth;

  // Same colours, same order, as `InstagramColors.gradient` — reused
  // directly rather than duplicated, plus one repeat of the first colour
  // at the end so the ring's start/end meet without a hard seam (a
  // `SweepGradient` needs that closing stop; `InstagramColors.gradient`
  // itself is a `LinearGradient` and doesn't carry one, since it runs
  // corner-to-corner rather than wrapping a full circle).
  static final _colors = [
    ...InstagramColors.gradient.colors,
    InstagramColors.gradient.colors.first,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = SweepGradient(colors: _colors).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      0,
      6.28318530718,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth;
}
