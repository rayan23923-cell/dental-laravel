import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/nfc/nfc_uid_reader.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../domain/group_admin.dart';
import 'groups_admin_providers.dart';
import '../../../core/widgets/tg_spinner.dart';

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
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['groupsAdmin.nfcScanFailed']!;
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
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['groupsAdmin.title']!)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/groups/new'),
        tooltip: t['groupsAdmin.newTitle'],
        child: const Icon(Icons.group_add_outlined),
      ),
      body: Column(
        children: [
          const AcademicYearBanner(),
          // Chat-list style (2026-10-13, by request): search pill + compact
          // rounded filter row instead of stacked outlined fields.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChatSearchField(
                        controller: _searchController,
                        hintText: t['groupsAdmin.searchHint']!,
                        onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : v.trim()),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _scanningNfc
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(height: 20, width: 20, child: TgSpinner(strokeWidth: 2)),
                          )
                        : IconButton(icon: const Icon(Icons.nfc), tooltip: t['groupsAdmin.scanNfcTooltip'], onPressed: _scanNfc),
                  ],
                ),
                if (_doctorName != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: InputChip(
                      avatar: const Icon(Icons.nfc, size: 18),
                      shape: const StadiumBorder(),
                      label: Text(trf(t['groupsAdmin.doctorGroupsChip']!, {'name': _doctorName!})),
                      onDeleted: () => setState(() {
                        _doctorId = null;
                        _doctorName = null;
                      }),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Theme(
                  data: _pillFilterTheme(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: CascadingDropdown(
                          label: t['groupsAdmin.educationTypeLabel']!,
                          itemsAsync: educationTypesAsync,
                          value: _educationTypeId,
                          onChanged: (v) => setState(() {
                            _educationTypeId = v;
                            _stageId = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CascadingDropdown(
                          key: ValueKey('stage-$_educationTypeId'),
                          label: t['groupsAdmin.stageLabel']!,
                          itemsAsync: stagesAsync.whenData(
                            (items) => _educationTypeId == null
                                ? items
                                : items.where((s) => s.educationTypeId == _educationTypeId).toList(),
                          ),
                          value: _stageId,
                          enabled: _educationTypeId != null,
                          onChanged: (v) => setState(() => _stageId = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: groupsAsync.when(
              loading: () => const Center(child: TgSpinner()),
              error: (error, stackTrace) => Center(
                child: Text(error is ApiException ? error.userMessage : t['groupsAdmin.loadFailed']!),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return Center(child: Text(t['groupsAdmin.emptyList']!));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(groupListProvider(_filter)),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => chatDivider,
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

/// Chat-list row (2026-10-13, by request): group icon, name, and chips for
/// the stage, doctor count and weekly slot count.
class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});
  final GroupAdmin group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final color = chatToneFor(group.id);
    return ChatListTile(
      title: group.name,
      color: color,
      icon: Icons.groups_outlined,
      chips: [
        if (group.stageName != null) ChatChip(label: group.stageName!, icon: Icons.stairs_outlined, color: color),
        ChatChip(
          label: '${group.doctorsCount} ${t['groupsAdmin.doctorsCountSuffix']}',
          icon: Icons.person_outline,
          color: Colors.blueGrey,
        ),
        ChatChip(
          label: '${group.slots.length} ${t['groupsAdmin.weeklySlotsCountSuffix']}',
          icon: Icons.schedule,
          color: Colors.blueGrey,
        ),
      ],
      onTap: () => context.push('/admin/groups/${group.id}'),
    );
  }
}

/// Rounded, dense "pill" look for the filter dropdowns above a chat list.
ThemeData _pillFilterTheme(BuildContext context) {
  final theme = Theme.of(context);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(30),
    borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
  );
  return theme.copyWith(
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        border: border,
        enabledBorder: border,
        constraints: const BoxConstraints(maxHeight: 44),
        labelStyle: const TextStyle(fontSize: 13),
      ),
      textStyle: const TextStyle(fontSize: 13),
    ),
  );
}
