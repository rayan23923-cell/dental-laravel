import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../data/groups_admin_repository.dart';
import '../domain/group_admin.dart';
import 'group_roster_pdf.dart';
import 'groups_admin_providers.dart';
import '../../../core/widgets/tg_spinner.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final int groupId;

  Future<void> _delete(BuildContext context, WidgetRef ref, GroupAdmin group) async {
    final t = ref.read(translationsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['groupsAdmin.deleteTitle']!),
        content: Text(trf(t['groupsAdmin.deleteConfirmBody']!, {'name': group.name})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['groupsAdmin.cancel']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['doctorsAdmin.delete']!)),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(groupsAdminRepositoryProvider).delete(groupId);
      ref.invalidate(groupListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['groupsAdmin.deletedSuccess']!)));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is ApiException ? e.userMessage : t['groupsAdmin.deleteFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref, GroupMember member) async {
    try {
      await ref.read(groupsAdminRepositoryProvider).removeDoctors(groupId, [member.id]);
      ref.invalidate(groupProvider(groupId));
      ref.invalidate(availableDoctorsProvider);
    } catch (e) {
      if (context.mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['groupsAdmin.removeFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _openAddDoctors(BuildContext context, WidgetRef ref, GroupAdmin group) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddDoctorsDialog(groupId: groupId, stageId: group.stageId),
    );
  }

  Future<void> _printRoster(BuildContext context, WidgetRef ref, GroupAdmin group) async {
    try {
      // .future — see doctor_list_screen.dart's `_printRoster` for why
      // `.valueOrNull` alone can race the provider's first-ever fetch.
      final settings = await ref.read(clinicSettingsProvider.future);
      final logo = await loadLetterheadLogo(ref, settings);
      final bytes = await buildGroupRosterPdf(group: group, settings: settings, logo: logo);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${group.name}.pdf');
    } catch (e) {
      if (context.mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(t['groupsAdmin.printFailed']!, {'error': e}))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));
    final t = ref.watch(translationsProvider);

    return groupAsync.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: TgSpinner())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(error is ApiException ? error.userMessage : t['groupsAdmin.loadFailed']!)),
      ),
      data: (group) {
        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.print_outlined),
                tooltip: t['groupsAdmin.printTooltip'],
                onPressed: () => _printRoster(context, ref, group),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/admin/groups/$groupId/edit'),
              ),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, ref, group)),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openAddDoctors(context, ref, group),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(t['groupsAdmin.addDoctorFab']!),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (group.stageName != null) Text(group.stageName!, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(t['groupsAdmin.weeklySlotsHeading']!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (group.slots.isEmpty) Text(t['groupsAdmin.noSlots']!),
              for (final slot in group.slots)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text('${slot.day} — ${slot.startTime} ${t['groupsAdmin.slotTo']} ${slot.endTime}'),
                  ),
                ),
              const SizedBox(height: 16),
              Text(trf(t['groupsAdmin.doctorsHeadingWithCount']!, {'n': group.members.length}), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (group.members.isEmpty) Text(t['groupsAdmin.noDoctorsYet']!),
              for (final member in group.members)
                Card(
                  child: ListTile(
                    title: Text(member.name),
                    subtitle: Text(member.email),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _removeMember(context, ref, member),
                    ),
                  ),
                ),
              const SizedBox(height: 72),
            ],
          ),
        );
      },
    );
  }
}

class _AddDoctorsDialog extends ConsumerStatefulWidget {
  const _AddDoctorsDialog({required this.groupId, required this.stageId});
  final int groupId;
  final int? stageId;

  @override
  ConsumerState<_AddDoctorsDialog> createState() => _AddDoctorsDialogState();
}

class _AddDoctorsDialogState extends ConsumerState<_AddDoctorsDialog> {
  final Set<int> _selected = {};
  bool _submitting = false;

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(groupsAdminRepositoryProvider).addDoctors(widget.groupId, _selected.toList());
      ref.invalidate(groupProvider(widget.groupId));
      ref.invalidate(availableDoctorsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['groupsAdmin.addFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctorsAsync = ref.watch(availableDoctorsProvider(widget.stageId));
    final t = ref.watch(translationsProvider);

    return AlertDialog(
      title: Text(t['groupsAdmin.addDoctorsDialogTitle']!),
      content: SizedBox(
        width: double.maxFinite,
        child: doctorsAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: TgSpinner())),
          error: (_, __) => Text(t['groupsAdmin.loadAvailableDoctorsFailed']!),
          data: (doctors) {
            if (doctors.isEmpty) {
              return Text(t['groupsAdmin.noAvailableDoctorsForStage']!);
            }
            return SizedBox(
              height: 320,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final doctor in doctors)
                    CheckboxListTile(
                      value: _selected.contains(doctor.id),
                      title: Text(doctor.name),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(doctor.id);
                        } else {
                          _selected.remove(doctor.id);
                        }
                      }),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['groupsAdmin.cancel']!)),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: TgSpinner(strokeWidth: 2))
              : Text(t['groupsAdmin.add']!),
        ),
      ],
    );
  }
}
