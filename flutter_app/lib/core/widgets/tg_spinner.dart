import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Telegram's loading spinner (by request, 2026-10-29: "اعمل لودنك انميشن
/// مشابه لتليجرام") — a port of Telegram Android's `RadialProgressView`:
/// the ring keeps turning at one turn per 2s while its arc stretches from
/// a dot to 280° and back every 500ms, the tail chasing the head so the
/// arc never jumps.
///
/// Drop-in for an indeterminate `CircularProgressIndicator`: same
/// `strokeWidth`/`color`/`valueColor`, fills its parent's `SizedBox` like
/// it does, and is 36px when nothing sizes it.
class TgSpinner extends StatefulWidget {
  const TgSpinner({this.size, this.strokeWidth = 3, this.color, this.valueColor, super.key});

  final double? size;
  final double strokeWidth;
  final Color? color;
  final Animation<Color?>? valueColor;

  @override
  State<TgSpinner> createState() => _TgSpinnerState();
}

class _TgSpinnerState extends State<TgSpinner> with SingleTickerProviderStateMixin {
  // Four rise/fall cycles: each adds 270° of hand-off plus 180° of spin,
  // so after four the ring is back where it started and the loop is seamless.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.valueColor?.value ?? widget.color ?? Theme.of(context).colorScheme.primary;
    final painter = CustomPaint(
      painter: _TgArcPainter(_controller, color, widget.strokeWidth),
    );
    final size = widget.size;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: size != null
          ? SizedBox.square(dimension: size, child: painter)
          : ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              child: painter,
            ),
    );
  }
}

class _TgArcPainter extends CustomPainter {
  _TgArcPainter(this.animation, this.color, this.strokeWidth) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final double strokeWidth;

  static const _rad = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = animation.value * 4000;
    final cycle = ms ~/ 1000;
    final half = ms % 1000;
    final rising = half < 500;
    final q = (half % 500) / 500;

    // The head runs ahead while the tail holds, then the tail catches up;
    // each catch-up carries the arc's start 270° forward.
    final e = Curves.easeInOut.transform(q);
    final sweep = rising ? 10 + 270 * e : 280 - 270 * e;
    final start = -90 + cycle * 270 + (rising ? 0 : 270 * e) + ms * 360 / 2000;

    final d = math.min(size.width, size.height);
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: d, height: d)
        .deflate(strokeWidth / 2);
    canvas.drawArc(
      rect,
      start * _rad,
      sweep * _rad,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TgArcPainter old) => old.color != color || old.strokeWidth != strokeWidth;
}
