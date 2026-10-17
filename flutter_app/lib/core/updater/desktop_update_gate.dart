import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../router/app_router.dart';
import 'desktop_update_checker.dart';

/// Wraps the app's root widget and checks once on startup for a newer
/// build (Windows, and since 2026-10-17 Android and iPhone), unless turned
/// off on the profile page. See [DesktopUpdateChecker] for the
/// check/download/install flow.
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
    if (!kIsWeb && DesktopUpdateChecker.isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await DesktopUpdateChecker.autoCheckEnabled() && mounted) {
          final info = await DesktopUpdateChecker.checkForUpdate();
          // This widget sits above the router's Navigator, so the dialogs
          // use the navigator's own context.
          final navContext = rootNavigatorKey.currentContext;
          if (info != null && navContext != null && navContext.mounted) await AppUpdateFlow.offer(navContext, info);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The update dialogs, shared by the startup check and the profile page's
/// "check for updates" button.
class AppUpdateFlow {
  const AppUpdateFlow._();

  /// Manual check: says when the app is already up to date or the server
  /// can't be reached.
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await DesktopUpdateChecker.checkForUpdate(throwOnError: true);
      if (!context.mounted) return;
      if (info == null) {
        messenger.showSnackBar(const SnackBar(content: Text('التطبيق محدّث إلى آخر نسخة.')));
      } else {
        await offer(context, info);
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذّر الاتصال بالخادم للتحقق من التحديثات.')));
    }
  }

  static Future<void> offer(BuildContext context, DesktopUpdateInfo info) async {
    final notes = info.notes != null && info.notes!.isNotEmpty ? '\n\n${info.notes}' : '';

    if (!DesktopUpdateChecker.canSelfInstall) {
      // iPhone: an app can't install another build, only the download page can.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تحديث جديد متوفر'),
          content: SelectableText(
            'نسخة ${info.version} متوفرة في صفحة التحميل:\n${info.url.replaceFirst(RegExp(r'/downloads/.*$'), '/download')}$notes',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا'))],
        ),
      );
      return;
    }

    final shouldUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('تحديث جديد متوفر'),
        content: Text('نسخة ${info.version} جاهزة للتنزيل.$notes'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لاحقًا')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تحديث الآن')),
        ],
      ),
    );
    if (shouldUpdate != true || !context.mounted) return;

    // Android installs only after the user lets this app install apps.
    if (Platform.isAndroid && !await DesktopUpdateChecker.canInstallPackages()) {
      if (!context.mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('السماح بتثبيت التحديث'),
          content: const Text(
            'لتثبيت التحديث من داخل التطبيق، فعّل "السماح من هذا المصدر" في الصفحة التي ستفتح، ثم ارجع واضغط "تحديث الآن" مرة أخرى.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('فتح الإعدادات')),
          ],
        ),
      );
      if (open == true) await DesktopUpdateChecker.openInstallSettings();
      return;
    }
    if (!context.mounted) return;

    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 16),
              Text(value == null ? 'جارِ تنزيل التحديث...' : 'جارِ تنزيل التحديث... ${(value * 100).round()}%'),
            ],
          ),
        ),
      ),
    );

    try {
      // Windows exits the process here; Android opens the installer.
      await DesktopUpdateChecker.downloadAndInstall(info, onProgress: (p) => progress.value = p);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تنزيل التحديث، حاول مرة أخرى.')));
    }
  }
}
