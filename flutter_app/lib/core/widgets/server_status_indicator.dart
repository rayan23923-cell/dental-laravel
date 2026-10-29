import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../config/server_settings_controller.dart';
import '../i18n/locale_controller.dart';
import '../network/server_status.dart';
import '../theme/app_theme.dart';
import 'tg_spinner.dart';

/// The connection dot's colours: green connected, red not, amber while the
/// very first check runs.
const serverOnlineColor = Color(0xFF2EB872);
const serverOfflineColor = InstagramColors.red;
const serverCheckingColor = Color(0xFFF5A623);

Color serverStatusColor(ServerStatus status) => switch (status.link) {
  ServerLink.online => serverOnlineColor,
  ServerLink.offline => serverOfflineColor,
  ServerLink.checking => serverCheckingColor,
};

String serverStatusLabel(ServerStatus status, Map<String, String> t) => switch (status.link) {
  ServerLink.online => t['conn.online']!,
  ServerLink.offline => status.checking ? t['conn.retrying']! : t['conn.offline']!,
  ServerLink.checking => t['conn.checking']!,
};

/// A small glowing dot — green / red / amber — that pulses while a check
/// is running.
class ServerStatusDot extends ConsumerStatefulWidget {
  const ServerStatusDot({super.key, this.size = 10});
  final double size;

  @override
  ConsumerState<ServerStatusDot> createState() => _ServerStatusDotState();
}

class _ServerStatusDotState extends ConsumerState<ServerStatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    lowerBound: 0.35,
    upperBound: 1,
    value: 1,
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(serverStatusProvider);
    if (status.checking) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 1) {
      _pulse.stop();
      _pulse.value = 1;
    }
    final color = serverStatusColor(status);
    return FadeTransition(
      opacity: _pulse,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: widget.size >= 10 ? 1.5 : 1),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: widget.size * 0.6)],
        ),
      ),
    );
  }
}

/// Dot + "متصل بالسيرفر" / "غير متصل"; tap for details and reconnect.
class ServerStatusChip extends ConsumerWidget {
  const ServerStatusChip({super.key, this.dense = false});
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider);
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showServerStatusSheet(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 10, vertical: dense ? 2 : 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ServerStatusDot(size: dense ? 8 : 10),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                serverStatusLabel(status, t),
                overflow: TextOverflow.ellipsis,
                style: (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(
                  color: serverStatusColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Details: which server, last check, why it is down, and the
/// "إعادة الاتصال" button.
Future<void> showServerStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _ServerStatusSheet(),
  );
}

class _ServerStatusSheet extends ConsumerWidget {
  const _ServerStatusSheet();

  String _reason(ServerStatus status, Map<String, String> t) => switch (status.reason) {
    ServerDownReason.noNetwork => t['conn.reason.noNetwork']!,
    ServerDownReason.database => t['conn.reason.database']!,
    ServerDownReason.server => trf(t['conn.reason.server']!, {'code': status.statusCode ?? ''}),
    ServerDownReason.unreachable || null => t['conn.reason.unreachable']!,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider);
    final server = ref.watch(serverSettingsProvider);
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final time = DateFormat('HH:mm:ss');
    final color = serverStatusColor(status);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const ServerStatusDot(size: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    serverStatusLabel(status, t),
                    style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(trf(t['conn.server']!, {'name': server.isClinic ? server.host : t['server.cloud']!})),
            if (status.isOffline) ...[
              const SizedBox(height: 6),
              Text(_reason(status, t), style: theme.textTheme.bodyMedium?.copyWith(color: serverOfflineColor)),
              const SizedBox(height: 6),
              Text(t['conn.autoRetry']!, style: theme.textTheme.bodySmall),
            ],
            if (status.checkedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                trf(t['conn.lastChecked']!, {'time': time.format(status.checkedAt!)}),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (status.isOffline && status.lastOnlineAt != null)
              Text(
                trf(t['conn.lastOnline']!, {'time': time.format(status.lastOnlineAt!)}),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: status.checking ? null : () => ref.read(serverStatusProvider.notifier).check(),
              icon: status.checking
                  ? const SizedBox(width: 18, height: 18, child: TgSpinner(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(status.checking ? t['conn.retrying']! : t['conn.retry']!),
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/server');
                },
                icon: const Icon(Icons.dns_outlined),
                label: Text(t['conn.settings']!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps the whole app (`MaterialApp.builder`): a red strip at the bottom
/// while the server can't be reached, with a reconnect button, and a short
/// green "عاد الاتصال" once it is back. Hidden while the keyboard is open.
class ServerStatusFrame extends ConsumerStatefulWidget {
  const ServerStatusFrame({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<ServerStatusFrame> createState() => _ServerStatusFrameState();
}

class _ServerStatusFrameState extends ConsumerState<ServerStatusFrame> {
  bool _restored = false;
  Timer? _restoredTimer;

  @override
  void dispose() {
    _restoredTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(serverStatusProvider, (previous, next) {
      if (previous?.isOffline == true && next.isOnline) {
        setState(() => _restored = true);
        _restoredTimer?.cancel();
        _restoredTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _restored = false);
        });
      } else if (next.isOffline && _restored) {
        setState(() => _restored = false);
      }
    });
    final status = ref.watch(serverStatusProvider);
    final t = ref.watch(translationsProvider);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final show = !keyboardOpen && (status.isOffline || _restored);

    final online = status.isOnline;
    final color = online ? serverOnlineColor : serverOfflineColor;
    // The same tree whether the strip shows or not — swapping the routed
    // app in and out of a Column would rebuild the navigator and lose
    // every open screen.
    final media = MediaQuery.of(context);
    return Column(
      children: [
        Expanded(
          child: MediaQuery(
            data: show
                ? media.copyWith(
                    padding: media.padding.copyWith(bottom: 0),
                    viewPadding: media.viewPadding.copyWith(bottom: 0),
                  )
                : media,
            child: widget.child,
          ),
        ),
        if (show)
          Material(
            color: color,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        online ? t['conn.restored']! : (status.checking ? t['conn.retrying']! : t['conn.banner']!),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!online)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: status.checking ? null : () => ref.read(serverStatusProvider.notifier).check(),
                        icon: status.checking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: TgSpinner(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(t['conn.retry']!, style: const TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
