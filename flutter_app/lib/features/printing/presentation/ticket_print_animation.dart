import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Shows a "the ticket feeds out of the printer" animation while [task]
/// runs in the background, and dismisses once both the animation has
/// played through once and [task] has finished — whichever takes longer,
/// so a fast Bluetooth write doesn't cut the animation short and a slow
/// one doesn't leave the ticket frozen half-fed.
///
/// [ticketPngBytes] is the same rendered raster already being sent to the
/// printer (`renderWidgetToPng`'s output) — the animation shows the real
/// ticket, not a placeholder.
Future<T> showTicketPrintAnimation<T>({
  required BuildContext context,
  required Uint8List ticketPngBytes,
  required Future<T> Function() task,
}) async {
  final resultCompleter = Completer<T>();
  unawaited(task().then(resultCompleter.complete, onError: resultCompleter.completeError));

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => _TicketFeedDialog(
      ticketPngBytes: ticketPngBytes,
      // A dialog must never surface the task's error itself — the
      // caller's own try/catch around `task()`'s awaited result handles
      // that (same contract as the print calls already had before this
      // animation existed). This just needs to know *when* to close.
      whenDone: resultCompleter.future.then((_) {}, onError: (_) {}),
    ),
  );

  return resultCompleter.future;
}

class _TicketFeedDialog extends StatefulWidget {
  const _TicketFeedDialog({required this.ticketPngBytes, required this.whenDone});

  final Uint8List ticketPngBytes;
  final Future<void> whenDone;

  @override
  State<_TicketFeedDialog> createState() => _TicketFeedDialogState();
}

class _TicketFeedDialogState extends State<_TicketFeedDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.wait([_controller.forward(), widget.whenDone]);
    if (!mounted) return;
    // A short hold on the fully-fed ticket so it doesn't vanish the
    // instant printing finishes — long enough to register, short enough
    // to not feel like a stall.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The printer's body/slot — fixed in place; the ticket below
            // appears to feed out from underneath it.
            Container(
              width: 220,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF3a3f47),
                borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.print, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text('جاري الطباعة...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Container(height: 6, width: 220, color: Colors.black),
            ClipRect(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Align(
                  alignment: Alignment.topCenter,
                  heightFactor: Curves.easeOut.transform(_controller.value).clamp(0.001, 1.0),
                  child: child,
                ),
                child: Container(
                  width: 220,
                  constraints: const BoxConstraints(maxHeight: 460),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: Image.memory(widget.ticketPngBytes, width: 220, fit: BoxFit.fitWidth),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
