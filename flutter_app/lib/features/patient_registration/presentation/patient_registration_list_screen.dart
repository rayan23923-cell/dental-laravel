import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/swipe_actions.dart';
import '../../../core/auth/staff_access.dart';
import '../../../core/platform/platform_support.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../../../core/widgets/qr_image.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../../printing/data/pos_printer_service.dart';
import '../../printing/presentation/printer_error_snackbar.dart';
import '../../printing/presentation/printer_settings_providers.dart';
import '../../printing/presentation/ticket_print_animation.dart';
import '../../printing/presentation/ticket_renderer.dart';
import '../../printing/presentation/ticket_widget.dart';
import '../data/patient_registration_repository.dart';
import '../domain/patient_registration.dart';
import 'live_registrations.dart';
import 'case_link_history_sheet.dart';
import 'patient_registration_providers.dart';
import '../../../core/widgets/tg_spinner.dart';
import '../../../core/widgets/period_chips.dart';

/// "سجل تسجيل المرضى" — mirrors `PatientRegistrations/Index.vue`,
/// including its search + day/service filters (the repository/provider
/// already supported search; this screen just never had UI for it until
/// now). A FAB for a new registration, and a link to the days/services
/// settings screen, same as the web page's header links.
///
/// `pickMode: true` turns a row tap into `Navigator.pop(registration)`
/// instead of the normal QR/print actions, and hides the FAB/scan/settings
/// actions — reused by `PaymentFormScreen`'s and (Phase 2)
/// `AppointmentFormScreen`'s registered-patient picker, mirroring
/// `PatientListScreen(pickMode: true)`'s exact existing pattern so there's
/// one registration list, not two.
class PatientRegistrationListScreen extends ConsumerStatefulWidget {
  const PatientRegistrationListScreen({super.key, this.pickMode = false});
  final bool pickMode;

  @override
  ConsumerState<PatientRegistrationListScreen> createState() => _PatientRegistrationListScreenState();
}

class _PatientRegistrationListScreenState extends ConsumerState<PatientRegistrationListScreen>
    with LiveRegistrations<PatientRegistrationListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  DateTimeRange? _range;
  int? _serviceId;
  // Linked to a case sheet / refused attempts (2026-11-04, by request).
  String? _link;
  int? _stageId;
  int? _departmentId;
  Timer? _debounce;

  // Archive tab and bulk archive / restore (2026-10-17), as the web
  // registry: archiving is a soft delete (payments are kept), archived
  // registrations are listed on their own tab and can be restored.
  bool _archived = false;
  bool _selecting = false;
  final Set<int> _selected = {};
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _search = value));
  }

  static final _ymd = DateFormat('yyyy-MM-dd');

  PatientRegistrationFilter get _filter => (
        search: _search.isEmpty ? null : _search,
        from: _range == null ? null : _ymd.format(_range!.start),
        to: _range == null ? null : _ymd.format(_range!.end),
        serviceId: _serviceId,
      );

  bool get _hasFilters =>
      _search.isNotEmpty || _range != null || _serviceId != null || _link != null || _stageId != null || _departmentId != null;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _range = picked);
  }

  PatientRegistrationPageQuery get _pageQuery => (
        filter: _filter,
        archived: !widget.pickMode && _archived,
        link: widget.pickMode ? null : _link,
        stageId: widget.pickMode ? null : _stageId,
        departmentId: widget.pickMode ? null : _departmentId,
      );

  static const _linkStatuses = [
    ('', 'patientRegFlutter.linkFilterAll', Icons.select_all),
    ('linked', 'patientRegFlutter.linkFilterLinked', Icons.link),
    ('unlinked', 'patientRegFlutter.linkFilterUnlinked', Icons.link_off),
    ('suspicious', 'patientRegFlutter.linkFilterSuspicious', Icons.gpp_maybe_outlined),
    ('attempts', 'patientRegFlutter.linkFilterAttempts', Icons.block),
  ];

  /// What the link filter button says, e.g. "مربوط بنموذج · المرحلة الرابعة · الحشوات".
  String _linkSummary(Map<String, String> t, LinkFacets? facets) {
    final parts = <String>[
      if (_link != null) t[_linkStatuses.firstWhere((s) => s.$1 == _link).$2]!,
      if (_stageId != null) facets?.stages.where((s) => s.id == _stageId).firstOrNull?.name ?? '…',
      if (_departmentId != null) facets?.departments.where((d) => d.id == _departmentId).firstOrNull?.name ?? '…',
    ];
    return parts.isEmpty ? t['patientRegFlutter.linkFilterAll']! : parts.join(' · ');
  }

  /// Link to case sheets: status, the linked case's stage and department,
  /// each with its count (2026-11-04, by request). A tap applies it.
  Future<void> _openLinkFilter(LinkFacets facets) async {
    final t = ref.read(translationsProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        void apply(VoidCallback change) {
          setState(change);
          Navigator.of(sheetContext).pop();
        }

        Widget section(String title, List<Widget> chips) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(sheetContext).textTheme.labelLarge?.copyWith(color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: chips),
                ],
              ),
            );

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(t['patientRegFlutter.linkFilter']!, style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 16),
                section(t['patientRegFlutter.linkStatus']!, [
                  for (final (key, label, icon) in _linkStatuses)
                    ChoiceChip(
                      avatar: Icon(icon, size: 16, color: key == 'suspicious' ? Colors.red.shade700 : null),
                      label: Text('${t[label]!} (${facets.statuses[key.isEmpty ? 'all' : key] ?? 0})'),
                      selected: (_link ?? '') == key,
                      onSelected: (_) => apply(() {
                        _link = key.isEmpty ? null : key;
                        if (key == 'unlinked') {
                          _stageId = null;
                          _departmentId = null;
                        }
                      }),
                    ),
                ]),
                if (facets.stages.isNotEmpty)
                  section(t['patientRegFlutter.linkStage']!, [
                    for (final st in facets.stages)
                      ChoiceChip(
                        avatar: const Icon(Icons.school_outlined, size: 16),
                        selectedColor: Colors.green.shade100,
                        label: Text('${st.name} (${st.count})'),
                        selected: _stageId == st.id,
                        onSelected: (_) => apply(() {
                          _stageId = _stageId == st.id ? null : st.id;
                          if (_link == 'unlinked') _link = null;
                        }),
                      ),
                  ]),
                if (facets.departments.isNotEmpty)
                  section(t['patientRegFlutter.linkDepartment']!, [
                    for (final d in facets.departments)
                      ChoiceChip(
                        avatar: const Icon(Icons.apartment, size: 16),
                        selectedColor: Colors.blue.shade100,
                        label: Text('${d.name} (${d.count})'),
                        selected: _departmentId == d.id,
                        onSelected: (_) => apply(() {
                          _departmentId = _departmentId == d.id ? null : d.id;
                          if (_link == 'unlinked') _link = null;
                        }),
                      ),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }

  void _refresh() {
    ref.invalidate(patientRegistrationPageProvider);
    ref.invalidate(patientRegistrationListProvider);
  }

  @override
  void onRegistrationsChanged() => _refresh();

  void _showArchive(bool archived) {
    setState(() {
      _archived = archived;
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      _selecting = true;
    });
  }

  Future<void> _run(Future<void> Function() action, String doneMessage, String failedKey) async {
    final t = ref.read(translationsProvider);
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selecting = false;
      });
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneMessage)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.userMessage : t[failedKey]!)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveSelected() async {
    final t = ref.read(translationsProvider);
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    if (!await _confirmArchive(trf(t['patientRegFlutter.archiveSelectedConfirm']!, {'n': ids.length}))) return;
    await _run(
      () => ref.read(patientRegistrationRepositoryProvider).archiveMany(ids),
      trf(t['patientRegFlutter.archivedDone']!, {'n': ids.length}),
      'patientRegFlutter.archiveFailed',
    );
  }

  /// Archiving is the plain archive again (2026-11-04, by request): payments
  /// kept, restorable from the archive tab; "from where" moved to the
  /// permanent delete there. False when cancelled.
  Future<bool> _confirmArchive(String message) async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t['patientRegFlutter.archiveConfirmButton']!),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Permanent delete from the archive (2026-11-02, by request), behind
  /// the user's own password.
  Future<void> _purgeSelected() async {
    final t = ref.read(translationsProvider);
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final controller = TextEditingController();
    // From the patients list, the lab list, or both (2026-11-04, by request).
    var scope = 'both';
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget option(String key, IconData icon, Color color) {
            final selected = scope == key;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: selected ? color.withValues(alpha: 0.10) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: selected ? color : Colors.grey.shade300, width: selected ? 2 : 1),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(icon, color: color),
                title: Text(t['patientRegFlutter.purgeFrom.$key']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(t['patientRegFlutter.purgeFromDesc.$key']!),
                trailing: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? color : Colors.grey),
                onTap: () => setDialogState(() => scope = key),
              ),
            );
          }

          return AlertDialog(
            title: Text(trf(t['patientRegFlutter.purgeTitle']!, {'n': ids.length})),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t['patientRegFlutter.purgeFromHint']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  option('patients', Icons.groups_outlined, Colors.blue.shade700),
                  option('lab', Icons.science_outlined, Colors.green.shade700),
                  option('both', Icons.delete_forever_outlined, Colors.red.shade700),
                  const SizedBox(height: 6),
                  Text(t['patientRegFlutter.purgeWarningFrom.$scope']!, style: TextStyle(color: Colors.red.shade800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: InputDecoration(labelText: t['patientRegFlutter.purgePassword']!),
                    onSubmitted: (v) => Navigator.of(ctx).pop(v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: Text(t['patientRegFlutter.purgeSelected']!),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty) return;
    await _run(
      () => ref.read(patientRegistrationRepositoryProvider).purgeMany(ids, password, scope: scope),
      trf(t['patientRegFlutter.purgedDone']!, {'n': ids.length}),
      'patientRegFlutter.purgeFailed',
    );
  }

  Future<void> _restoreSelected() async {
    final t = ref.read(translationsProvider);
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    await _run(
      () => ref.read(patientRegistrationRepositoryProvider).restoreMany(ids),
      trf(t['patientRegFlutter.restoredDone']!, {'n': ids.length}),
      'patientRegFlutter.restoreFailed',
    );
  }

  /// "أرشفة الكل": every registration matching the filters, across pages.
  Future<void> _archiveAll(int total) async {
    final t = ref.read(translationsProvider);
    if (total == 0) return;
    if (!await _confirmArchive(trf(t['patientRegFlutter.archiveAllConfirm']!, {'n': total}))) return;
    final f = _filter;
    await _run(
      () => ref.read(patientRegistrationRepositoryProvider).archiveAll(
            search: f.search,
            from: f.from,
            to: f.to,
            serviceId: f.serviceId,
          ),
      trf(t['patientRegFlutter.archivedDone']!, {'n': total}),
      'patientRegFlutter.archiveFailed',
    );
  }

  void _clearFilters() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _search = '';
      _range = null;
      _serviceId = null;
      _link = null;
      _stageId = null;
      _departmentId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(patientRegistrationPageProvider(_pageQuery));
    final registrationsAsync = pageAsync.whenData((p) => p.page.items);
    final canArchive = !widget.pickMode && (pageAsync.valueOrNull?.canArchive ?? false);
    final total = pageAsync.valueOrNull?.page.total ?? 0;
    final servicesAsync = ref.watch(servicesProvider);
    final servicesForFilter = servicesAsync.valueOrNull ?? const [];
    final t = ref.watch(translationsProvider);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    // Only for accounts the lab would let in (2026-10-18, by request).
    final canOpenLab = account is! StaffAccount || staffCanOpen(account, '/lab');
    final canOpenSettings = account is! StaffAccount || staffCanOpen(account, '/records/patient-registrations/settings');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? t['patientRegFlutter.choosePatient']! : t['patientRegFlutter.title']!),
        actions: widget.pickMode
            ? null
            : [
                // Staff had no scanner entry point before Phase 5 — `/scan` was
                // doctor-only and hardcoded to task instances. This is the desk
                // clerk's way in to the scan-to-pay flow (Phase 5, Step 5).
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: t['patientRegFlutter.scanPaymentCode']!,
                  onPressed: () => context.push('/records/patient-registrations/scan'),
                ),
                // Infectious-disease screening gate (2026-08-26) — the
                // lab/reception entry point, same shared ticket QR.
                if (canOpenLab)
                  IconButton(
                    icon: const Icon(Icons.coronavirus_outlined),
                    tooltip: t['patientRegFlutter.screeningTooltip']!,
                    onPressed: () => context.push('/lab'),
                  ),
                if (canOpenSettings)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: t['patientRegFlutter.settingsTooltip']!,
                    onPressed: () => context.push('/records/patient-registrations/settings'),
                  ),
                if (canArchive)
                  IconButton(
                    icon: Icon(_selecting ? Icons.checklist_rtl : Icons.checklist),
                    tooltip: t['patientRegFlutter.select']!,
                    onPressed: () => setState(() {
                      _selecting = !_selecting;
                      if (!_selecting) _selected.clear();
                    }),
                  ),
                if (canArchive && !_archived && total > 0)
                  PopupMenuButton<String>(
                    onSelected: (_) => _archiveAll(total),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'archive-all',
                        child: Text(_hasFilters
                            ? t['patientRegFlutter.archiveAllFiltered']!
                            : t['patientRegFlutter.archiveAll']!),
                      ),
                    ],
                  ),
              ],
      ),
      bottomNavigationBar: _selecting && canArchive
          ? SafeArea(
              child: Material(
                elevation: 8,
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: t['common.close']!,
                        onPressed: () => setState(() {
                          _selecting = false;
                          _selected.clear();
                        }),
                      ),
                      Expanded(
                        child: Text(
                          trf(t['patientRegFlutter.selectedCount']!, {'n': _selected.length}),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          final ids = (registrationsAsync.valueOrNull ?? const <PatientRegistration>[]).map((r) => r.id);
                          if (ids.every(_selected.contains)) {
                            _selected.removeAll(ids);
                          } else {
                            _selected.addAll(ids);
                          }
                        }),
                        child: Text(t['patientRegFlutter.selectAllPage']!),
                      ),
                      const SizedBox(width: 4),
                      if (_archived)
                        FilledButton.icon(
                          // In a Row: the theme's full-width minimum would
                          // make it vanish (see app_theme.dart).
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                          onPressed: _busy || _selected.isEmpty ? null : _restoreSelected,
                          icon: const Icon(Icons.unarchive_outlined),
                          label: Text(t['patientRegFlutter.restoreSelected']!),
                        ),
                      if (_archived) ...[
                        const SizedBox(width: 4),
                        IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: Colors.red.shade700),
                          tooltip: t['patientRegFlutter.purgeSelected']!,
                          onPressed: _busy || _selected.isEmpty ? null : _purgeSelected,
                          icon: const Icon(Icons.delete_forever_outlined),
                        ),
                      ] else
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, minimumSize: const Size(64, 40)),
                          onPressed: _busy || _selected.isEmpty ? null : _archiveSelected,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text(t['patientRegFlutter.archiveSelected']!),
                        ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: widget.pickMode || _archived || _selecting
          ? null
          : FloatingActionButton(
              onPressed: () async {
                await context.push('/records/patient-registrations/new');
                _refresh();
              },
              tooltip: t['patientRegFlutter.newRegistration']!,
              child: const Icon(Icons.person_add_alt_1),
            ),
      body: Column(
        children: [
          // Chat-list style (2026-10-13, by request): search pill + compact
          // rounded filter row.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              children: [
                if (!widget.pickMode) ...[
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.people_outline),
                          label: Text(t['patientRegFlutter.currentTab']!),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text(t['patientRegFlutter.archiveTab']!),
                        ),
                      ],
                      selected: {_archived},
                      onSelectionChanged: (v) => _showArchive(v.first),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ChatSearchField(
                        controller: _searchController,
                        hintText: t['patientRegFlutter.searchLabel']!,
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    if (_hasFilters)
                      IconButton(icon: const Icon(Icons.filter_alt_off_outlined), tooltip: t['patientRegFlutter.clearFilters']!, onPressed: _clearFilters),
                  ],
                ),
                const SizedBox(height: 8),
                // Today / this week / this month (2026-11-01, by request).
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PeriodChips(
                    from: _range?.start,
                    to: _range?.end,
                    onChanged: (r) => setState(() => _range = r),
                  ),
                ),
                const SizedBox(height: 8),
                Theme(
                  data: _pillFilterTheme(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickRange,
                          icon: const Icon(Icons.date_range_outlined, size: 18),
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          label: Text(
                            _range == null
                                ? t['patientRegFlutter.dateRange']!
                                : '${_ymd.format(_range!.start)} ← ${_ymd.format(_range!.end)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownMenu<int>(
                          key: const ValueKey('filter-service'),
                          enableFilter: true,
                          requestFocusOnTap: true,
                          expandedInsets: EdgeInsets.zero,
                          label: Text(t['patientRegFlutter.serviceLabel']!),
                          initialSelection: servicesForFilter.any((s) => s.id == _serviceId) ? _serviceId : null,
                          dropdownMenuEntries: [
                            for (final s in servicesForFilter) DropdownMenuEntry(value: s.id, label: s.name),
                          ],
                          onSelected: (v) => setState(() => _serviceId = v),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.pickMode) ...[
                  const SizedBox(height: 8),
                  _LinkFilterButton(
                    summary: _linkSummary(t, pageAsync.valueOrNull?.facets),
                    active: _link != null || _stageId != null || _departmentId != null,
                    suspicious: pageAsync.valueOrNull?.facets.statuses['suspicious'] ?? 0,
                    onPressed: () => _openLinkFilter(pageAsync.valueOrNull?.facets ?? const LinkFacets()),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: registrationsAsync.when(
              loading: () => const Center(child: TgSpinner()),
              error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : t['common.loadFailed']!)),
              data: (registrations) {
                if (registrations.isEmpty) {
                  return Center(
                    child: Text(_archived && !_hasFilters
                        ? t['patientRegFlutter.emptyArchive']!
                        : t['patientRegFlutter.emptyMatching']!),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: registrations.length,
                    separatorBuilder: (_, __) => chatDivider,
                    itemBuilder: (context, i) {
                      final r = registrations[i];
                      // Chat-list row (2026-10-13, by request): name, phone,
                      // service/day chips and the screening status chip.
                      final selectable = _selecting && canArchive;
                      final swipable = !widget.pickMode && !_archived && !selectable;
                      // Swipe for the row's actions (2026-10-28, by request).
                      return SwipeActions(
                        rowKey: ValueKey('registration-${r.id}'),
                        start: swipable && canPrintTickets
                            ? SwipeAction(
                                icon: Icons.print_outlined,
                                label: t['patientRegFlutter.reprintTicket']!,
                                color: Colors.indigo,
                                onTriggered: () => _reprintTicket(context, r),
                              )
                            : null,
                        end: swipable
                            ? SwipeAction(
                                icon: Icons.qr_code_2,
                                label: t['patientRegFlutter.paymentCodeTooltip']!,
                                color: Colors.teal,
                                onTriggered: () => _showQrDialog(context, r),
                              )
                            : null,
                        child: ChatListTile(
                        title: r.name,
                        color: chatToneFor(r.id),
                        icon: Icons.person_outline,
                        selected: selectable && _selected.contains(r.id),
                        leading: selectable
                            ? Checkbox(value: _selected.contains(r.id), onChanged: (_) => _toggle(r.id))
                            : null,
                        // LTR isolate: a lone phone number has no strong-
                        // direction anchor inside RTL text (same bidi class
                        // fixed in academic_session_list_screen.dart).
                        subtitle: '\u2066${r.phone}\u2069',
                        chips: [
                          _ScreeningBadge(status: r.screeningStatus, diagnosis: r.screeningDiagnosisText),
                          if (r.serviceName != null)
                            ChatChip(label: r.serviceName!, icon: Icons.medical_services_outlined, color: Colors.indigo),
                          if (r.caseLink != null)
                            ChatChip(
                              label: '${t['patientRegFlutter.linkedTo']!}: ${r.caseLink!.label}',
                              icon: Icons.link,
                              color: Colors.green.shade700,
                            ),
                          if (r.suspiciousAttemptsCount > 0)
                            ChatChip(
                              label: trf(t['patientRegFlutter.suspiciousChip']!, {'n': r.suspiciousAttemptsCount}),
                              icon: Icons.gpp_maybe_outlined,
                              color: Colors.red.shade700,
                            )
                          else if (r.linkAttemptsCount > 0)
                            ChatChip(
                              label: trf(t['patientRegFlutter.attemptsChip']!, {'n': r.linkAttemptsCount}),
                              icon: Icons.block,
                              color: Colors.orange.shade800,
                            ),
                        ],
                        // Archived rows can't be opened (the payment
                        // screen is for current registrations); a tap
                        // selects them for restoring instead.
                        onTap: widget.pickMode
                            ? () => Navigator.of(context).pop(r)
                            : selectable || (_archived && canArchive)
                                ? () => _toggle(r.id)
                                : _archived
                                    ? null
                                    : () => _openPayment(context, r),
                        actions: widget.pickMode || _archived || selectable
                            ? const []
                            : [
                                if (canPrintTickets)
                                  ChatAction(
                                    icon: Icons.print_outlined,
                                    tooltip: t['patientRegFlutter.reprintTicket']!,
                                    onPressed: () => _reprintTicket(context, r),
                                  ),
                                ChatAction(
                                  icon: Icons.qr_code_2,
                                  tooltip: t['patientRegFlutter.paymentCodeTooltip']!,
                                  onPressed: () => _showQrDialog(context, r),
                                ),
                                ChatAction(
                                  icon: r.suspiciousAttemptsCount > 0 ? Icons.gpp_maybe_outlined : Icons.manage_search,
                                  tooltip: t['patientRegFlutter.linkHistory']!,
                                  onPressed: () => showCaseLinkHistory(context, ref, r),
                                ),
                              ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Search-as-an-alternative-to-scanning (2026-08-26) — this list
  /// already had the search bar the user asked for; tapping a found row
  /// now opens the exact same payment screen the QR scan flow does,
  /// instead of doing nothing (this list's `onTap` previously only did
  /// anything in `pickMode`). Fetches fresh state (`status()`, not the
  /// list row's own possibly-stale `screeningStatus`) so the payment
  /// screen's gate reflects the latest lab result.
  Future<void> _openPayment(BuildContext context, PatientRegistration registration) async {
    try {
      final state = await ref.read(patientRegistrationRepositoryProvider).status(registration.id);
      if (context.mounted) context.push('/records/patient-registrations/payment', extra: state);
    } catch (e) {
      if (context.mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['patientRegFlutter.openPaymentFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  /// The same desk-payment QR printed on the ticket (Phase 4D/5), viewable
  /// on screen too — the plan explicitly calls for both, since a ticket
  /// can be lost or the printer can fail (already observed once this
  /// project, see `PosPrinterService`'s doc comment).
  void _showQrDialog(BuildContext context, PatientRegistration registration) {
    final t = ref.read(translationsProvider);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(registration.name),
        content: SizedBox(
          width: 240,
          child: QrImage(path: '/patient-registrations/${registration.id}/qr', size: 220),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['common.close']!)),
        ],
      ),
    );
  }

  /// Reprints an already-registered patient's ticket — today printing
  /// only ever happened once, immediately after creating a new
  /// registration (`patient_registration_form_screen.dart::_submit()`);
  /// this is the same best-effort sequence, triggered from the list
  /// instead. Android-POS-only, same constraint as the original print.
  Future<void> _reprintTicket(BuildContext context, PatientRegistration registration) async {
    final t = ref.read(translationsProvider);
    Uint8List? qrBytes;
    try {
      final bytes = await ref.read(apiClientProvider).getBytes('/patient-registrations/${registration.id}/qr');
      qrBytes = Uint8List.fromList(bytes);
    } catch (_) {
      qrBytes = null;
    }
    Uint8List? logoBytes;
    try {
      final settings = await ref.read(clinicSettingsProvider.future);
      final logoUrl = settings?.ticketLogoUrl;
      if (logoUrl != null) {
        final bytes = await ref.read(apiClientProvider).getBytes(logoUrl);
        logoBytes = Uint8List.fromList(bytes);
      }
    } catch (_) {
      logoBytes = null;
    }
    if (!context.mounted) return;

    try {
      await precacheTicketImages(context, [qrBytes, logoBytes]);
      if (!context.mounted) return;
      final printerSettings = await ref.read(printerSettingsProvider.future);
      if (!context.mounted) return;
      final pngBytes = await renderWidgetToPng(
        context,
        TicketWidget(
          registration: registration,
          showPaid: true,
          qrBytes: qrBytes,
          logoBytes: logoBytes,
          widthDots: printerSettings.dotsPerLine,
        ),
      );
      if (!context.mounted) return;
      await showTicketPrintAnimation<void>(
        context: context,
        ticketPngBytes: pngBytes,
        task: () => ref.read(posPrinterServiceProvider).printTicket(pngBytes),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['patientRegFlutter.reprintSuccess']!)));
      }
    } catch (e) {
      if (context.mounted) {
        showPrinterErrorSnackBar(context, t['patientRegFlutter.printFailed']!, error: e);
      }
    }
  }
}

/// Small at-a-glance indicator of the infectious-disease screening result
/// (2026-08-26) — pure display; the actual gate is server-side
/// (`PatientScreeningGate`).
class _ScreeningBadge extends ConsumerWidget {
  const _ScreeningBadge({required this.status, this.diagnosis});

  final String status;

  /// "التهاب الكبد B، HIV" for a flagged result (2026-11-03).
  final String? diagnosis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    // Status carried by the chip tone (2026-10-13, chat-list style).
    final (color, icon, label) = switch (status) {
      'clear' => (Colors.green, Icons.verified_outlined, t['patientRegFlutter.screeningClear']!),
      'flagged' => (Colors.red, Icons.coronavirus_outlined, t['patientRegFlutter.screeningFlagged']!),
      _ => (Colors.orange, Icons.hourglass_empty, t['patientRegFlutter.screeningPending']!),
    };
    return ChatChip(
      label: status == 'flagged' && diagnosis != null ? '$label — $diagnosis' : label,
      icon: icon,
      color: color.shade700,
    );
  }
}

/// Rounded, dense "pill" look for the filter dropdowns above a chat list
/// (same as doctor_list_screen.dart's).
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

/// The patients list's "الربط بالنماذج" button (2026-11-04): what is
/// chosen now, and a red dot when other doctors tried linked receipts.
class _LinkFilterButton extends StatelessWidget {
  const _LinkFilterButton({required this.summary, required this.active, required this.suspicious, required this.onPressed});

  final String summary;
  final bool active;
  final int suspicious;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size.fromHeight(44),
        backgroundColor: active ? scheme.primaryContainer : null,
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(summary, overflow: TextOverflow.ellipsis)),
          if (suspicious > 0) ...[
            Icon(Icons.gpp_maybe_outlined, size: 18, color: Colors.red.shade700),
            Text(' $suspicious', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
          ],
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}
