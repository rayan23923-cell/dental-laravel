import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/form_settings_repository.dart';
import '../../../core/widgets/tg_spinner.dart';

/// "إعدادات النماذج" (2026-10-22, by request), opened from task progress:
/// the supervisor's own rotating code on top, then paper/electronic forms,
/// grades shown to students and the supervisor code settings — the web's
/// FormSettings/Index page.
class FormSettingsScreen extends ConsumerStatefulWidget {
  const FormSettingsScreen({super.key});

  @override
  ConsumerState<FormSettingsScreen> createState() => _FormSettingsScreenState();
}

class _FormSettingsScreenState extends ConsumerState<FormSettingsScreen> {
  FormSettingsPage? _page;
  FormSettings? _form;
  SupervisorCodeNow? _code;
  Object? _loadError;
  bool _saving = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_code != null && !_code!.expiresAt.isAfter(DateTime.now())) _refreshCode();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = await ref.read(formSettingsRepositoryProvider).get();
      if (!mounted) return;
      setState(() {
        _page = page;
        _form = page.settings;
        _code = page.myCode;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _refreshCode() async {
    final current = _code;
    _code = null;
    try {
      final next = await ref.read(formSettingsRepositoryProvider).myCode();
      if (mounted) setState(() => _code = next);
    } catch (_) {
      if (mounted) setState(() => _code = current);
    }
  }

  Future<void> _save() async {
    final t = ref.read(translationsProvider);
    setState(() => _saving = true);
    try {
      final saved = await ref.read(formSettingsRepositoryProvider).save(_form!);
      if (!mounted) return;
      setState(() => _form = saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['formSettings.saved']!)));
      if (_code != null) _refreshCode();
    } catch (e) {
      if (!mounted) return;
      final message = e is ValidationException
          ? (e.errors.values.expand((v) => v).firstOrNull ?? e.message)
          : e is ApiException
              ? e.userMessage
              : t['formSettings.failed']!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _remaining() {
    final s = _code!.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999999);
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return '${h > 0 ? '$h:' : ''}${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final scheme = Theme.of(context).colorScheme;
    final form = _form;
    final canEdit = _page?.canEdit ?? false;

    Widget section(IconData icon, Color color, String title, List<Widget> children) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]),
                ...children,
              ],
            ),
          ),
        );

    Widget toggle(String label, String hint, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: Text(hint, style: const TextStyle(fontSize: 12)),
          value: value,
          onChanged: canEdit ? onChanged : null,
        );

    return Scaffold(
      appBar: AppBar(title: Text(t['formSettings.title']!)),
      body: _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError is ApiException ? (_loadError as ApiException).userMessage : t['formSettings.failed']!),
                  TextButton(onPressed: _load, child: Text(t['common.retry'] ?? 'Retry')),
                ],
              ),
            )
          : form == null
              ? const Center(child: TgSpinner())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(t['formSettings.subtitle']!, style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    if (_code != null) _CodeCard(code: _code!, remaining: _remaining(), enabled: form.codeEnabled, hourly: form.period == 'hourly'),
                    if (!canEdit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(t['formSettings.readOnly']!, style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    // Forms, grades and task switches live with the general settings (2026-10-22).
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(Icons.settings_outlined, color: scheme.primary),
                        title: Text(t['formSettings.generalLink']!, style: const TextStyle(fontSize: 13)),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => context.push('/admin/clinic-settings'),
                      ),
                    ),
                    section(Icons.pin_outlined, Colors.deepPurple, t['formSettings.codeSection']!, [
                      toggle(t['formSettings.codeEnabled']!, t['formSettings.codeEnabledHint']!, form.codeEnabled, (v) => setState(() => _form = form.copyWith(codeEnabled: v))),
                      if (form.codeEnabled) ...[
                        const SizedBox(height: 4),
                        Text(t['formSettings.period']!),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(value: 'daily', icon: const Icon(Icons.today), label: Text(t['formSettings.daily']!)),
                            ButtonSegment(value: 'hourly', icon: const Icon(Icons.hourglass_top), label: Text(t['formSettings.hourly']!)),
                          ],
                          selected: {form.period},
                          onSelectionChanged: canEdit ? (v) => setState(() => _form = form.copyWith(period: v.first)) : null,
                        ),
                        const SizedBox(height: 12),
                        Text(t['formSettings.actions']!),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final a in const ['start', 'step', 'finish'])
                              FilterChip(
                                label: Text(t['formSettings.action_$a']!),
                                selected: form.actions.contains(a),
                                onSelected: canEdit
                                    ? (on) => setState(() => _form = form.copyWith(actions: on ? [...form.actions, a] : form.actions.where((x) => x != a).toList()))
                                    : null,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ]),
                    if (canEdit)
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving ? const SizedBox(width: 18, height: 18, child: TgSpinner(strokeWidth: 2)) : const Icon(Icons.save),
                        label: Text(t['formSettings.save']!),
                      ),
                  ],
                ),
    );
  }
}

class _CodeCard extends ConsumerWidget {
  const _CodeCard({required this.code, required this.remaining, required this.enabled, required this.hourly});
  final SupervisorCodeNow code;
  final String remaining;
  final bool enabled;
  final bool hourly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        boxShadow: [BoxShadow(color: const Color(0xFF4F46E5).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.key, color: Colors.white70, size: 20),
              const SizedBox(width: 6),
              Expanded(child: Text(t['formSettings.myCode']!, style: const TextStyle(color: Colors.white70))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
                child: Text(t[hourly ? 'formSettings.hourly' : 'formSettings.daily']!, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in code.code.split(''))
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 42,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white38)),
                    child: Text(d, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.schedule, color: Colors.white70, size: 18),
              const SizedBox(width: 4),
              Expanded(child: Text(t['formSettings.changesAt']!.replaceAll('{time}', remaining), style: const TextStyle(color: Colors.white70))),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code.code));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['formSettings.copied']!)));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(t['formSettings.copy']!),
              ),
            ],
          ),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t['formSettings.codeOff']!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
