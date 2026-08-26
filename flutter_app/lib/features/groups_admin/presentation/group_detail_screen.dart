import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../data/groups_admin_repository.dart';
import '../domain/group_admin.dart';
import 'group_roster_pdf.dart';
import 'groups_admin_providers.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final int groupId;

  Future<void> _delete(BuildContext context, WidgetRef ref, GroupAdmin group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المجموعة'),
        content: Text('هل أنت متأكد من حذف "${group.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(groupsAdminRepositoryProvider).delete(groupId);
      ref.invalidate(groupListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحذف.';
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
        final message = e is ApiException ? e.userMessage : 'تعذر الإزالة.';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء ملف PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));

    return groupAsync.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.')),
      ),
      data: (group) {
        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.print_outlined),
                tooltip: 'طباعة بيانات المجموعة (PDF)',
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
            label: const Text('إضافة طبيب'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (group.stageName != null) Text(group.stageName!, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text('المواعيد الأسبوعية', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (group.slots.isEmpty) const Text('لا توجد مواعيد.'),
              for (final slot in group.slots)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text('${slot.day} — ${slot.startTime} إلى ${slot.endTime}'),
                  ),
                ),
              const SizedBox(height: 16),
              Text('الأطباء (${group.members.length})', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (group.members.isEmpty) const Text('لا يوجد أطباء بعد.'),
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
        final message = e is ApiException ? e.userMessage : 'تعذر الإضافة.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctorsAsync = ref.watch(availableDoctorsProvider(widget.stageId));

    return AlertDialog(
      title: const Text('إضافة أطباء'),
      content: SizedBox(
        width: double.maxFinite,
        child: doctorsAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          error: (_, __) => const Text('تعذر تحميل قائمة الأطباء المتاحين.'),
          data: (doctors) {
            if (doctors.isEmpty) {
              return const Text('لا يوجد أطباء متاحون لهذه المرحلة.');
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إضافة'),
        ),
      ],
    );
  }
}
