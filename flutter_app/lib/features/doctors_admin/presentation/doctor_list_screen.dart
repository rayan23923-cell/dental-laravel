import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/nfc/nfc_uid_reader.dart';
import '../../../core/pdf/pdf_letterhead.dart';
import '../../../core/widgets/academic_year_banner.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../domain/doctor_admin.dart';
import '../data/doctors_admin_repository.dart';
import 'doctor_files.dart';
import 'doctor_roster_pdf.dart';
import 'doctors_admin_providers.dart';

class DoctorListScreen extends ConsumerStatefulWidget {
  const DoctorListScreen({super.key});

  @override
  ConsumerState<DoctorListScreen> createState() => _DoctorListScreenState();
}

class _DoctorListScreenState extends ConsumerState<DoctorListScreen> {
  final _searchController = TextEditingController();
  String? _search;
  int? _educationTypeId;
  int? _stageId;
  bool _scanningNfc = false;
  bool _printing = false;

  /// "حذف المحدد" (2026-10-17): picking rows, then archiving them at once.
  bool _selectMode = false;
  final Set<int> _selected = {};
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ({String? search, int? educationTypeId, int? stageId}) get _filter =>
      (search: _search, educationTypeId: _educationTypeId, stageId: _stageId);

  /// Tap-to-scan alternate to typing a name — resolves the card via
  /// `Api\DoctorController::nfcLookup()` and both fills the search box
  /// with the doctor's name *and* jumps the two dropdowns to their
  /// education type/stage, so the match is immediate rather than relying
  /// on the name search alone.
  Future<void> _scanNfc() async {
    setState(() => _scanningNfc = true);
    try {
      final uid = await NfcUidReader.readUid();
      final doctor = await ref.read(lookupRepositoryProvider).doctorByNfcTag(uid);
      if (!mounted) return;
      setState(() {
        _search = doctor.name;
        _searchController.text = doctor.name;
        _educationTypeId = doctor.educationTypeId;
        _stageId = doctor.stageId;
      });
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['doctorsAdmin.nfcScanFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _scanningNfc = false);
    }
  }

  /// Prints exactly the currently filtered/searched list on screen —
  /// mirrors `print_doctors.php`'s "طباعة الفلتر" button rather than
  /// always re-fetching everything.
  Future<void> _printRoster(List<DoctorAdmin> doctors) async {
    setState(() => _printing = true);
    try {
      // .future, not .valueOrNull — this screen is often the first place
      // that ever reads this provider, so a plain `.valueOrNull` read can
      // race it (still `AsyncLoading`, resolves to null) even though the
      // fetch would have succeeded a moment later (found live: the PDF's
      // university/college name lines were silently blank on a fresh
      // login until this fix).
      final settings = await ref.read(clinicSettingsProvider.future);
      final logo = await loadLetterheadLogo(ref, settings);
      final bytes = await buildDoctorRosterPdf(doctors: doctors, settings: settings, logo: logo);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'قائمة الأطباء.pdf');
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trf(t['doctorsAdmin.printFailed']!, {'error': e}))));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggle(int id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  Future<void> _deleteSelected() async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['doctorsAdmin.deleteSelected']!),
        content: Text(trf(t['doctorsAdmin.deleteSelectedConfirm']!, {'n': _selected.length})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t['nav.cancel']!)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t['doctorsAdmin.delete']!)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(doctorsAdminRepositoryProvider).deleteMany(_selected.toList());
      ref.invalidate(doctorAdminListProvider);
      _exitSelect();
      if (!mounted) return;
      if (result.blocked.isEmpty) {
        _snack(trf(t['doctorsAdmin.archivedCount']!, {'n': result.archived}));
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(trf(t['doctorsAdmin.archivedCount']!, {'n': result.archived})),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['doctorsAdmin.skippedLinked']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final b in result.blocked) Text('• $b'),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t['common.ok']!))],
          ),
        );
      }
    } catch (e) {
      _snack(e is ApiException ? e.userMessage : t['doctorsAdmin.deleteFailed']!);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The import template, or the doctors as Excel narrowed to the chosen
  /// education type/stage — saved where the user picks.
  Future<void> _download({required bool export}) async {
    final t = ref.read(translationsProvider);
    setState(() => _busy = true);
    try {
      final repo = ref.read(doctorsAdminRepositoryProvider);
      final bytes = export
          ? await repo.export(educationTypeId: _educationTypeId, stageId: _stageId)
          : await repo.template();
      final path = await saveDownloadedFile(export ? 'doctors.xlsx' : 'doctors_template.xlsx', bytes);
      if (path != null) _snack(trf(t['doctorsAdmin.fileSaved']!, {'path': path}));
    } catch (e) {
      _snack(e is ApiException ? e.userMessage : t['doctorsAdmin.downloadFailed']!);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final educationTypesAsync = ref.watch(doctorEducationTypesProvider);
    final stagesAsync = ref.watch(doctorStagesProvider);
    final doctorsAsync = ref.watch(doctorAdminListProvider(_filter));
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: _selectMode
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelect),
              title: Text(trf(t['doctorsAdmin.selectedCount']!, {'n': _selected.length})),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: t['doctorsAdmin.selectAll'],
                  onPressed: () => setState(() => _selected.addAll([for (final d in doctorsAsync.valueOrNull?.items ?? const <DoctorAdmin>[]) d.id])),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: t['doctorsAdmin.deleteSelected'],
                  onPressed: _busy || _selected.isEmpty ? null : _deleteSelected,
                ),
              ],
            )
          : AppBar(
        title: Text(t['doctorsAdmin.title']!),
        actions: [
          IconButton(
            icon: _printing
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print_outlined),
            tooltip: t['doctorsAdmin.printListTooltip'],
            onPressed: _printing || doctorsAsync.valueOrNull == null
                ? null
                : () => _printRoster(doctorsAsync.valueOrNull!.items),
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (action) async {
              switch (action) {
                case 'import':
                  await context.push('/admin/doctors/import');
                case 'template':
                  await _download(export: false);
                case 'export':
                  await _download(export: true);
                case 'select':
                  setState(() => _selectMode = true);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'import', child: ListTile(leading: const Icon(Icons.upload_file_outlined), title: Text(t['doctorsAdmin.importTitle']!))),
              PopupMenuItem(value: 'template', child: ListTile(leading: const Icon(Icons.download_outlined), title: Text(t['doctorsAdmin.downloadTemplate']!))),
              PopupMenuItem(value: 'export', child: ListTile(leading: const Icon(Icons.table_view_outlined), title: Text(t['doctorsAdmin.exportExcel']!))),
              PopupMenuItem(value: 'select', child: ListTile(leading: const Icon(Icons.checklist), title: Text(t['doctorsAdmin.selectRows']!))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/doctors/new'),
        tooltip: t['doctorsAdmin.newTitle'],
        child: const Icon(Icons.person_add_alt_1),
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
                        hintText: t['doctorsAdmin.searchHint']!,
                        onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : v.trim()),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _scanningNfc
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(icon: const Icon(Icons.nfc), tooltip: t['doctorsAdmin.scanNfcTooltip'], onPressed: _scanNfc),
                  ],
                ),
                const SizedBox(height: 8),
                Theme(
                  data: _pillFilterTheme(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: CascadingDropdown(
                          label: t['doctorsAdmin.educationTypeLabel']!,
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
                          label: t['doctorsAdmin.stageLabel']!,
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
            child: doctorsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(error is ApiException ? error.userMessage : t['doctorsAdmin.loadFailed']!),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return Center(child: Text(t['doctorsAdmin.emptyList']!));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(doctorAdminListProvider(_filter)),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: page.items.length,
                    separatorBuilder: (_, __) => chatDivider,
                    itemBuilder: (context, i) => _DoctorTile(
                      doctor: page.items[i],
                      selecting: _selectMode,
                      selected: _selected.contains(page.items[i].id),
                      onToggle: () => _toggle(page.items[i].id),
                    ),
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

/// Chat-list row (2026-10-13, by request): photo or initial avatar, name,
/// username, and stage/education-type chips.
class _DoctorTile extends StatelessWidget {
  const _DoctorTile({required this.doctor, this.selecting = false, this.selected = false, this.onToggle});
  final DoctorAdmin doctor;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final color = chatToneFor(doctor.id);
    return ChatListTile(
      title: doctor.name,
      color: color,
      imageUrl: doctor.profileImageUrl,
      subtitle: doctor.username,
      chips: [
        if (doctor.stageName != null) ChatChip(label: doctor.stageName!, icon: Icons.stairs_outlined, color: color),
        if (doctor.educationTypeName != null)
          ChatChip(label: doctor.educationTypeName!, icon: Icons.school_outlined, color: Colors.blueGrey),
      ],
      leading: selecting ? Checkbox(value: selected, onChanged: (_) => onToggle?.call()) : null,
      selected: selected,
      onTap: selecting ? onToggle : () => context.push('/admin/doctors/${doctor.id}'),
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
