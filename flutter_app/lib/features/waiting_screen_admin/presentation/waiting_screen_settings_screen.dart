import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../data/waiting_screen_admin_repository.dart';
import '../../../core/widgets/tg_spinner.dart';

final waitingScreenSettingsProvider = FutureProvider.autoDispose<WaitingScreenSettingsPage>((ref) {
  return ref.watch(waitingScreenAdminRepositoryProvider).fetch();
});

/// "إعدادات شاشة الانتظار" (2026-10-17) — the web's
/// `WaitingScreenSettings/Edit.vue`: which group the public screen shows,
/// how many patients per page, how often it turns the page. Each TV's
/// stage is chosen when pairing it ([WaitingScreenPairScreen]).
class WaitingScreenSettingsScreen extends ConsumerStatefulWidget {
  const WaitingScreenSettingsScreen({super.key});

  @override
  ConsumerState<WaitingScreenSettingsScreen> createState() => _WaitingScreenSettingsScreenState();
}

class _WaitingScreenSettingsScreenState extends ConsumerState<WaitingScreenSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _perPage = TextEditingController();
  final _rotation = TextEditingController();
  int? _groupId;
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
    _groupId = page.settings.groupId;
    _perPage.text = '${page.settings.patientsPerPage}';
    _rotation.text = '${page.settings.rotationSeconds}';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = ref.read(translationsProvider);
    setState(() => _saving = true);
    try {
      await ref.read(waitingScreenAdminRepositoryProvider).save(
            groupId: _groupId,
            patientsPerPage: int.parse(_perPage.text.trim()),
            rotationSeconds: int.parse(_rotation.text.trim()),
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
    final groupsEnabled = ref.watch(groupsEnabledProvider);
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(t['waitingScreenSettings.stageMovedNote']!, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 16),
                if (groupsEnabled) ...[
                  DropdownButtonFormField<int?>(
                    initialValue: page.groups.any((g) => g.id == _groupId) ? _groupId : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t['waitingScreenSettings.groupLabel'], border: const OutlineInputBorder()),
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text(t['waitingScreenSettings.allGroups']!)),
                      for (final g in page.groups)
                        DropdownMenuItem<int?>(
                          value: g.id,
                          child: Text(g.stageName == null ? g.name : '${g.name} — ${g.stageName}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _groupId = v),
                  ),
                  const SizedBox(height: 12),
                ],
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
