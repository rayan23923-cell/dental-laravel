import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../data/patient_registration_repository.dart';
import '../domain/lab_registration.dart';
import 'live_registrations.dart';
import 'patient_registration_providers.dart';
import '../../../core/widgets/tg_spinner.dart';

/// "المختبر" (2026-10-17) — the web `Lab/Index.vue` page in the app:
/// registrations by screening status (pending / flagged / clear / all,
/// with counts), name/phone search, each row's result, paid/unpaid lab
/// fee or "earlier valid result" badge, place and date. Tapping a row
/// opens the screening screen (record the result, pay and print, reuse an
/// earlier result, print the result); the ticket scanner stays one tap
/// away in the app bar. Uses the lab-gated `/lab` endpoints, so the
/// `lab` role (screening permission only) gets the whole page.
class LabListScreen extends ConsumerStatefulWidget {
  const LabListScreen({super.key});

  @override
  ConsumerState<LabListScreen> createState() => _LabListScreenState();
}

class _LabListScreenState extends ConsumerState<LabListScreen> with LiveRegistrations<LabListScreen> {
  static const _statuses = ['pending', 'flagged', 'clear', 'all'];

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _status = 'pending';
  String _search = '';
  int _page = 1;
  bool _opening = false;

  LabListQuery get _query => (status: _status, search: _search.isEmpty ? null : _search, page: _page);

  @override
  void onRegistrationsChanged() => ref.invalidate(labListProvider);

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _search = value.trim();
          _page = 1;
        });
      }
    });
  }

  Future<void> _scan() async {
    await context.push('/lab/scan');
    if (mounted) ref.invalidate(labListProvider);
  }

  /// Fresh state (payments, earlier valid result, checker) for the row,
  /// then the screening screen; the list refreshes on the way back.
  Future<void> _open(LabRegistration row) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final state = await ref.read(patientRegistrationRepositoryProvider).labStatus(row.registration.id);
      if (!mounted) return;
      await context.push('/records/patient-registrations/screening', extra: state);
      if (mounted) ref.invalidate(labListProvider);
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.userMessage : t['lab.openFailed']!)),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  static String _date(String? raw) {
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return parsed == null ? '—' : DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
  }

  String _statusLabel(Map<String, String> t, String status) => switch (status) {
        'clear' => t['patientRegFlutter.screeningClear']!,
        'flagged' => t['patientRegFlutter.screeningFlagged']!,
        'all' => t['lab.all']!,
        _ => t['patientRegFlutter.screeningPending']!,
      };

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final pageAsync = ref.watch(labListProvider(_query));
    final counts = pageAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(t['labels.lab']!),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: t['lab.scanTicket']!,
            onPressed: _scan,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(t['lab.scanTicket']!),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: ChatSearchField(
              controller: _searchController,
              hintText: t['patientRegFlutter.searchLabel']!,
              onChanged: _onSearchChanged,
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                for (final status in _statuses)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(counts == null
                          ? _statusLabel(t, status)
                          : '${_statusLabel(t, status)}  ${counts.countFor(status)}'),
                      selected: _status == status,
                      onSelected: (_) => setState(() {
                        _status = status;
                        _page = 1;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          if (_opening) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: pageAsync.when(
              loading: () => const Center(child: TgSpinner()),
              error: (error, _) => Center(child: Text(error is ApiException ? error.userMessage : t['common.loadFailed']!)),
              data: (page) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(labListProvider),
                child: page.items.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text(t['lab.empty']!)),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 4, bottom: 88),
                        itemCount: page.items.length + (page.lastPage > 1 ? 1 : 0),
                        separatorBuilder: (_, __) => chatDivider,
                        itemBuilder: (context, i) {
                          if (i == page.items.length) return _pager(page, t);
                          return _row(page, page.items[i], t);
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(LabPage page, LabRegistration row, Map<String, String> t) {
    final r = row.registration;
    final (color, icon) = switch (r.screeningStatus) {
      'clear' => (Colors.green, Icons.check_circle_outline),
      'flagged' => (Colors.red, Icons.cancel_outlined),
      _ => (Colors.amber.shade800, Icons.hourglass_top),
    };
    final place = [r.serviceName ?? '—', if (r.registerDayName != null) r.registerDayName!].join(' · ');
    return ChatListTile(
      title: r.name,
      color: color,
      icon: icon,
      subtitle: '\u2066${r.phone}\u2069',
      chips: [
        ChatChip(label: _statusLabel(t, r.screeningStatus), icon: icon, color: color),
        if (row.canReuse)
          ChatChip(label: t['lab.previousValidBadge']!, icon: Icons.verified_outlined, color: Colors.green.shade700)
        else
          ChatChip(
            label: row.labPaid ? t['lab.paid']! : t['lab.unpaid']!,
            icon: row.labPaid ? Icons.paid_outlined : Icons.money_off,
            color: row.labPaid ? Colors.lightBlue.shade700 : Colors.blueGrey,
          ),
        // "ادفع واطبع" (pay and print): the fee is taken with the result.
        if (!row.canReuse && !row.labPaid && (page.labFee ?? 0) > 0 && r.screeningStatus == 'pending')
          ChatChip(label: t['lab.payAndPrint']!, icon: Icons.print_outlined, color: Colors.orange.shade800),
        ChatChip(label: place, icon: Icons.location_on_outlined, color: Colors.indigo),
        ChatChip(label: _date(r.createdAt), icon: Icons.schedule, color: Colors.blueGrey),
      ],
      onTap: () => _open(row),
    );
  }

  Widget _pager(LabPage page, Map<String, String> t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: t['lab.previousPage']!,
            onPressed: page.currentPage > 1 ? () => setState(() => _page = page.currentPage - 1) : null,
          ),
          Text('${page.currentPage} / ${page.lastPage}'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: t['lab.nextPage']!,
            onPressed: page.currentPage < page.lastPage ? () => setState(() => _page = page.currentPage + 1) : null,
          ),
        ],
      ),
    );
  }
}
