import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/waiting_screen_admin_repository.dart';
import '../../../core/widgets/tg_spinner.dart';

final pairedScreensProvider = FutureProvider.autoDispose<List<PairedScreen>>((ref) {
  return ref.watch(waitingScreenAdminRepositoryProvider).screens();
});

final waitingScreenSettingsProvider = FutureProvider.autoDispose<WaitingScreenSettingsPage>((ref) {
  return ref.watch(waitingScreenAdminRepositoryProvider).fetch();
});

/// "إعدادات شاشة الانتظار" (2026-10-17) — the web's
/// `WaitingScreenSettings/Edit.vue`: how many patients per page and how
/// often it turns the page. The screen shows the lab only (no stages).
class WaitingScreenSettingsScreen extends ConsumerStatefulWidget {
  const WaitingScreenSettingsScreen({super.key});

  @override
  ConsumerState<WaitingScreenSettingsScreen> createState() => _WaitingScreenSettingsScreenState();
}

class _WaitingScreenSettingsScreenState extends ConsumerState<WaitingScreenSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _perPage = TextEditingController();
  final _rotation = TextEditingController();
  String _labScope = 'today';
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _perPage.dispose();
    _rotation.dispose();
    super.dispose();
  }

  void _seed(WaitingScreenSettingsPage page) {
    if (_seeded) return;
    _seeded = true;
    _perPage.text = '${page.settings.patientsPerPage}';
    _rotation.text = '${page.settings.rotationSeconds}';
    _labScope = page.settings.labScope;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = ref.read(translationsProvider);
    setState(() => _saving = true);
    try {
      await ref.read(waitingScreenAdminRepositoryProvider).save(
            groupId: null,
            patientsPerPage: int.parse(_perPage.text.trim()),
            rotationSeconds: int.parse(_rotation.text.trim()),
            labScope: _labScope,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['waitingScreenSettings.saved']!)));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['waitingScreenSettings.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _range(String? value, int min, int max) {
    final t = ref.read(translationsProvider);
    final n = int.tryParse(value?.trim() ?? '');
    if (n == null || n < min || n > max) {
      return trf(t['waitingScreenSettings.rangeError']!, {'min': '$min', 'max': '$max'});
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final pageAsync = ref.watch(waitingScreenSettingsProvider);
    final screenUrl = '${AppConfig.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '')}/waiting-screen';

    return Scaffold(
      appBar: AppBar(title: Text(t['waitingScreenSettings.title']!)),
      body: pageAsync.when(
        loading: () => const Center(child: TgSpinner()),
        error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : t['waitingScreenSettings.loadFailed']!)),
        data: (page) {
          _seed(page);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t['waitingScreenSettings.description']!, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                // Lab filter (2026-11-03, by request): today's only or all pending.
                Text(t['waitingScreenSettings.labScopeLabel']!, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'today', icon: const Icon(Icons.today_outlined), label: Text(t['waitingScreenSettings.labScope_today']!)),
                    ButtonSegment(value: 'all', icon: const Icon(Icons.groups_outlined), label: Text(t['waitingScreenSettings.labScope_all']!)),
                  ],
                  selected: {_labScope},
                  onSelectionChanged: (v) => setState(() => _labScope = v.first),
                ),
                const SizedBox(height: 6),
                Text(t['waitingScreenSettings.labScope_${_labScope}_hint']!, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _perPage,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: t['waitingScreenSettings.patientsPerPageLabel'], border: const OutlineInputBorder()),
                  validator: (v) => _range(v, 1, 50),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rotation,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: t['waitingScreenSettings.rotationSecondsLabel'], border: const OutlineInputBorder()),
                  validator: (v) => _range(v, 3, 300),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(height: 18, width: 18, child: TgSpinner(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(t['waitingScreenSettings.save']!),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/admin/waiting-screen/pair'),
                  icon: const Icon(Icons.connected_tv_outlined),
                  label: Text(t['waitingScreenPairing.title']!),
                ),
                const SizedBox(height: 24),
                const _PairedScreens(),
                const SizedBox(height: 20),
                Text(t['waitingScreenSettings.screenAddress']!, style: Theme.of(context).textTheme.bodySmall),
                SelectableText(screenUrl, textDirection: TextDirection.ltr),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paired TVs and their remote control (2026-11-03, by request) — the
/// web's "الشاشات المربوطة" section.
class _PairedScreens extends ConsumerStatefulWidget {
  const _PairedScreens();

  @override
  ConsumerState<_PairedScreens> createState() => _PairedScreensState();
}

class _PairedScreensState extends ConsumerState<_PairedScreens> {
  Future<void> _run(Future<void> Function() action, {bool sent = true}) async {
    final t = ref.read(translationsProvider);
    try {
      await action();
      ref.invalidate(pairedScreensProvider);
      if (mounted && sent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['waitingScreenSettings.sent']!)));
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : t['waitingScreenSettings.saveFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _rename(PairedScreen screen, String current) async {
    final t = ref.read(translationsProvider);
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['waitingScreenSettings.renamePrompt']!),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t['nav.cancel']!)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(t['waitingScreenSettings.save']!)),
        ],
      ),
    );
    if (name == null) return;
    await _run(() => ref.read(waitingScreenAdminRepositoryProvider).rename(screen.id, name), sent: false);
  }

  Future<void> _unpair(PairedScreen screen) async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t['waitingScreenSettings.unpairConfirm']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['nav.cancel']!)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t['waitingScreenSettings.unpair']!)),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(waitingScreenAdminRepositoryProvider).unpair(screen.id), sent: false);
  }

  String _minutes(int m) {
    final t = ref.read(translationsProvider);
    return m == 0 ? t['waitingScreenSettings.never']! : trf(t['waitingScreenSettings.minutes']!, {'n': '$m'});
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final repo = ref.read(waitingScreenAdminRepositoryProvider);
    final screensAsync = ref.watch(pairedScreensProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(t['waitingScreenSettings.screensHeading']!, style: theme.textTheme.titleMedium)),
            IconButton(onPressed: () => ref.invalidate(pairedScreensProvider), icon: const Icon(Icons.refresh)),
          ],
        ),
        Text(t['waitingScreenSettings.screensHint']!, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        screensAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: TgSpinner())),
          error: (e, _) => Text(e is ApiException ? e.userMessage : t['waitingScreenSettings.loadFailed']!),
          data: (screens) {
            if (screens.isEmpty) return Text(t['waitingScreenSettings.noScreens']!);
            return Column(
              children: [
                for (var i = 0; i < screens.length; i++)
                  Builder(builder: (context) {
                    final screen = screens[i];
                    final name = screen.name ?? trf(t['waitingScreenSettings.screenUnnamed']!, {'n': '${i + 1}'});
                    final seen = screen.lastSeenAt == null
                        ? t['waitingScreenSettings.neverSeen']!
                        : trf(t['waitingScreenSettings.lastSeen']!, {'time': MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(screen.lastSeenAt!))});
                    final kind = screen.tvApp
                        ? trf(t['waitingScreenSettings.tvApp']!, {'version': screen.version ?? ''})
                        : t['waitingScreenSettings.browser']!;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, size: 10, color: screen.online ? Colors.green : Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
                                IconButton(onPressed: () => _rename(screen, name), icon: const Icon(Icons.edit_outlined)),
                                IconButton(onPressed: () => _unpair(screen), icon: const Icon(Icons.link_off, color: Colors.red)),
                              ],
                            ),
                            Text('${screen.online ? t['waitingScreenSettings.online'] : t['waitingScreenSettings.offline']} · $seen · $kind',
                                style: theme.textTheme.bodySmall),
                            if (screen.tvApp && screen.overlay == false)
                              Text(t['waitingScreenSettings.overlayOff']!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
                            if (screen.pending.isNotEmpty)
                              Text(t['waitingScreenSettings.pendingShort']!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.blue)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _run(() => repo.command(screen.id, 'reload')),
                                  icon: const Icon(Icons.refresh),
                                  label: Text(t['waitingScreenSettings.reload']!),
                                ),
                                if (screen.tvApp)
                                  OutlinedButton.icon(
                                    onPressed: () => _run(() => repo.command(screen.id, 'check_update')),
                                    icon: const Icon(Icons.system_update_outlined),
                                    label: Text(t['waitingScreenSettings.checkUpdate']!),
                                  ),
                              ],
                            ),
                            if (screen.tvApp) ...[
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(t['waitingScreenSettings.openOnBoot']!),
                                value: screen.openOnBoot ?? false,
                                onChanged: (v) => _run(() => repo.command(screen.id, 'open_on_boot', v)),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(t['waitingScreenSettings.openOnWake']!),
                                value: screen.openOnWake ?? false,
                                onChanged: (v) => _run(() => repo.command(screen.id, 'open_on_wake', v)),
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text(t['waitingScreenSettings.returnMinutes']!)),
                                  DropdownButton<int>(
                                    value: pairedScreenReturnMinutes.contains(screen.returnMinutes) ? screen.returnMinutes : null,
                                    hint: Text(t['waitingScreenSettings.unknown']!),
                                    items: [
                                      for (final m in pairedScreenReturnMinutes) DropdownMenuItem(value: m, child: Text(_minutes(m))),
                                    ],
                                    onChanged: (m) {
                                      if (m != null) _run(() => repo.command(screen.id, 'return_minutes', m));
                                    },
                                  ),
                                ],
                              ),
                            ] else
                              Text(t['waitingScreenSettings.needsTvApp']!, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ],
    );
  }
}
