import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'desktop_update_checker.dart';

/// Wraps the app's root widget and, on Windows only, checks once on startup
/// for a newer desktop build. See [DesktopUpdateChecker] for the actual
/// check/download/silent-install flow (mirrors Telegram Desktop's updater).
class DesktopUpdateGate extends StatefulWidget {
  const DesktopUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  State<DesktopUpdateGate> createState() => _DesktopUpdateGateState();
}

class _DesktopUpdateGateState extends State<DesktopUpdateGate> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final info = await DesktopUpdateChecker.checkForUpdate();
    if (info == null || !mounted) return;

    final shouldUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('تحديث جديد متوفر'),
        content: Text(
          'نسخة ${info.version} جاهزة للتنزيل.'
          '${info.notes != null && info.notes!.isNotEmpty ? '\n\n${info.notes}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لاحقًا'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تحديث الآن'),
          ),
        ],
      ),
    );
    if (shouldUpdate != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('جارِ تنزيل التحديث...')),
          ],
        ),
      ),
    );

    await DesktopUpdateChecker.downloadAndInstall(info); // exits the process
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
