import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/nfc/nfc_uid_reader.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../domain/group_admin.dart';
import 'groups_admin_providers.dart';

/// Previously had no search or filter UI at all. Education type here is
/// UI-only (`Group` has no `education_type_id` column, confirmed) —
/// narrows the stage dropdown client-side, never sent to the server;
/// `stage_id` and `search` are real query params on `Api\GroupController::index()`.
/// NFC is a third, separate filter — scanning a doctor's card doesn't
/// match a *group name*, so it narrows to "groups this doctor belongs
/// to" (`doctor_id`) instead, shown as a removable chip rather than
/// stuffed into the name search box.
class GroupListScreen extends ConsumerStatefulWidget {
  const GroupListScreen({super.key});

  @override
  ConsumerState<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends ConsumerState<GroupListScreen> {
  final _searchController = TextEditingController();
  String? _search;
  int? _educationTypeId;
  int? _stageId;
  int? _doctorId;
  String? _doctorName;
  bool _scanningNfc = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ({String? search, int? stageId, int? doctorId}) get _filter =>
      (search: _search, stageId: _stageId, doctorId: _doctorId);

  Future<void> _scanNfc() async {
    setState(() => _scanningNfc = true);
    try {
      final uid = await NfcUidReader.readUid();
      final doctor = await ref.read(lookupRepositoryProvider).doctorByNfcTag(uid);
      if (!mounted) return;
      setState(() {
        _doctorId = doctor.id;
        _doctorName = doctor.name;
      });
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر التعرف على البطاقة.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _scanningNfc = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final educationTypesAsync = ref.watch(groupEducationTypesProvider);
    final stagesAsync = ref.watch(groupStagesProvider);
    final groupsAsync = ref.watch(groupListProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: const Text('المجموعات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/groups/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const AcademicYearBanner(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'ابحث بالاسم',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _scanningNfc
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(icon: const Icon(Icons.nfc), tooltip: 'مسح بطاقة طبيب (NFC)', onPressed: _scanNfc),
                  ),
                  onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : v.trim()),
                ),
                if (_doctorName != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Chip(
                      avatar: const Icon(Icons.nfc, size: 18),
                      label: Text('مجموعات $_doctorName'),
                      onDeleted: () => setState(() {
                        _doctorId = null;
                        _doctorName = null;
                      }),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                CascadingDropdown(
                  label: 'نوع التعليم',
                  itemsAsync: educationTypesAsync,
                  value: _educationTypeId,
                  onChanged: (v) => setState(() {
                    _educationTypeId = v;
                    _stageId = null;
                  }),
                ),
                const SizedBox(height: 8),
                CascadingDropdown(
                  key: ValueKey('stage-$_educationTypeId'),
                  label: 'المرحلة',
                  itemsAsync: stagesAsync.whenData(
                    (items) => _educationTypeId == null
                        ? items
                        : items.where((s) => s.educationTypeId == _educationTypeId).toList(),
                  ),
                  value: _stageId,
                  enabled: _educationTypeId != null,
                  onChanged: (v) => setState(() => _stageId = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: groupsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return const Center(child: Text('لا توجد مجموعات مطابقة.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(groupListProvider(_filter)),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _GroupTile(group: groups[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});
  final GroupAdmin group;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(group.name),
        subtitle: Text([
          if (group.stageName != null) group.stageName!,
          '${group.doctorsCount} طبيب',
          '${group.slots.length} موعد أسبوعي',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => context.push('/admin/groups/${group.id}'),
      ),
    );
  }
}
