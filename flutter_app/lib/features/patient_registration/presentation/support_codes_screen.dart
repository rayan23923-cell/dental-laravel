import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';

import '../../../core/auth/staff_access.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/pdf/pdf_letterhead.dart';
import '../../../core/widgets/numeric_input.dart';
import '../../../core/widgets/tg_spinner.dart';
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../data/support_codes_repository.dart';
import '../domain/support_code.dart';
import 'support_cards_pdf.dart';

/// "بطاقات الرعاية" (2026-11-01, by request), the web `SupportCodes/Index`
/// page: generate one-time 5-digit codes, print them as cards to cut out
/// and hand out, and stop unused ones. A code typed at registration makes
/// the service and the lab test free.
class SupportCodesScreen extends ConsumerStatefulWidget {
  const SupportCodesScreen({super.key});

  @override
  ConsumerState<SupportCodesScreen> createState() => _SupportCodesScreenState();
}

class _SupportCodesScreenState extends ConsumerState<SupportCodesScreen> {
  String? _status;
  int? _batch;
  String _search = '';
  SupportCodePage? _page;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  final _selected = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await ref.read(supportCodesRepositoryProvider).list(status: _status, search: _search, batch: _batch, perPage: 200);
      if (!mounted) return;
      setState(() {
        _page = page;
        _error = null;
        _selected.removeWhere((id) => !page.codes.any((c) => c.id == id && c.status != 'used'));
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object e) => e is ApiException ? e.userMessage : ref.read(translationsProvider)['common.loadFailed']!;

  Future<void> _generate() async {
    final t = ref.read(translationsProvider);
    final result = await showDialog<({int count, String note})>(context: context, builder: (_) => const _GenerateDialog());
    if (result == null) return;
    setState(() => _busy = true);
    try {
      final codes = await ref.read(supportCodesRepositoryProvider).generate(result.count, note: result.note);
      _batch = codes.isEmpty ? null : codes.first.batch;
      _status = null;
      await _load();
      _snack(t['supportCodes.generated']!.replaceAll('{n}', '${codes.length}'));
    } catch (e) {
      _snack(_errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDisabled(bool disabled, {int? batch}) async {
    final t = ref.read(translationsProvider);
    final ids = batch == null ? _selected.toList() : <int>[];
    if (disabled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(batch != null
              ? t['supportCodes.disableBatchConfirm']!.replaceAll('{batch}', '$batch')
              : t['supportCodes.disableConfirm']!.replaceAll('{n}', '${ids.length}')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['nav.cancel']!)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t['supportCodes.disable']!)),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final message = await ref.read(supportCodesRepositoryProvider).setDisabled(ids: ids, batch: batch, disabled: disabled);
      _selected.clear();
      await _load();
      _snack(message);
    } catch (e) {
      _snack(_errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prints the picked active codes, else the batch's, else every active one.
  Future<void> _print() async {
    final t = ref.read(translationsProvider);
    setState(() => _busy = true);
    try {
      final picked = _page?.codes.where((c) => _selected.contains(c.id) && c.status == 'active').toList() ?? [];
      final codes = picked.isNotEmpty ? picked : await ref.read(supportCodesRepositoryProvider).activeCodes(batch: _batch);
      if (codes.isEmpty) {
        _snack(t['supportCodes.nothingToPrint']!);
        return;
      }
      final settings = await ref.read(clinicSettingsProvider.future);
      final logo = await loadLetterheadLogo(ref, settings);
      final title = settings?.universityName ?? settings?.clinicName ?? '';
      await Printing.layoutPdf(
        name: '${t['supportCodes.title']!}.pdf',
        onLayout: (_) => buildSupportCardsPdf(codes: codes, title: title, logo: logo),
      );
    } catch (e) {
      _snack(_errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final canGenerate = staffCan(ref, 'support_codes', 'generate');
    final canDisable = staffCan(ref, 'support_codes', 'disable');
    final page = _page;
    final batch = page?.batches.where((b) => b.batch == _batch).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(t['supportCodes.title']!),
        actions: [
          if (canGenerate)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: _selected.isNotEmpty
                  ? t['supportCodes.printSelected']!.replaceAll('{n}', '${_selected.length}')
                  : batch != null
                      ? t['supportCodes.printBatch']!
                      : t['supportCodes.printActive']!,
              onPressed: _busy ? null : _print,
            ),
        ],
      ),
      floatingActionButton: canGenerate
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.add),
              label: Text(t['supportCodes.generate']!),
            )
          : null,
      body: page == null
          ? Center(child: _error != null ? Text(_errorText(_error!)) : const TgSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  if (!page.enabled)
                    Card(
                      color: Colors.amber.shade50,
                      child: ListTile(leading: const Icon(Icons.info_outline), title: Text(t['supportCodes.disabledFeature']!)),
                    ),
                  Text(t['supportCodes.intro']!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  // Status tiles, as on the web page.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (key, label, icon, color) in [
                        (null, t['supportCodes.all']!, Icons.style_outlined, Colors.blueGrey),
                        ('active', t['supportCodes.active']!, Icons.verified_outlined, Colors.teal),
                        ('used', t['supportCodes.used']!, Icons.task_alt, Colors.lightBlue),
                        ('disabled', t['supportCodes.disabled']!, Icons.block, Colors.red),
                      ])
                        ChoiceChip(
                          avatar: Icon(icon, size: 18, color: color),
                          label: Text('$label ${page.counts[key ?? 'all'] ?? 0}'),
                          selected: _status == key,
                          onSelected: (_) {
                            setState(() => _status = key);
                            _load();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          inputFormatters: digitsOnly,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search),
                            hintText: t['supportCodes.search']!,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (v) {
                            _search = v.trim();
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: _batch,
                          isExpanded: true,
                          decoration: InputDecoration(isDense: true, labelText: t['supportCodes.batch']!, border: const OutlineInputBorder()),
                          items: [
                            DropdownMenuItem(value: null, child: Text(t['supportCodes.allBatches']!)),
                            for (final b in page.batches)
                              DropdownMenuItem(
                                value: b.batch,
                                child: Text(
                                  t['supportCodes.batchOption']!
                                          .replaceAll('{batch}', '${b.batch}')
                                          .replaceAll('{active}', '${b.active}')
                                          .replaceAll('{total}', '${b.total}') +
                                      (b.note != null ? ' · ${b.note}' : ''),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            setState(() => _batch = v);
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (canDisable && (_selected.isNotEmpty || (batch != null && batch.active > 0))) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_selected.isNotEmpty) ...[
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, minimumSize: const Size(0, 40)),
                            onPressed: _busy ? null : () => _setDisabled(true),
                            icon: const Icon(Icons.block),
                            label: Text(t['supportCodes.disableSelected']!),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: _busy ? null : () => _setDisabled(false),
                            icon: const Icon(Icons.restart_alt),
                            label: Text(t['supportCodes.enableSelected']!),
                          ),
                        ] else
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700, minimumSize: const Size(0, 40)),
                            onPressed: _busy ? null : () => _setDisabled(true, batch: batch!.batch),
                            icon: const Icon(Icons.block),
                            label: Text(t['supportCodes.disableBatch']!),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_loading) const LinearProgressIndicator(),
                  if (page.codes.isEmpty)
                    Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(t['supportCodes.empty']!))),
                  for (final c in page.codes) _CodeTile(
                    code: c,
                    selected: _selected.contains(c.id),
                    onChanged: c.status == 'used' || !(canDisable || canGenerate)
                        ? null
                        : (v) => setState(() => v ? _selected.add(c.id) : _selected.remove(c.id)),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CodeTile extends ConsumerWidget {
  const _CodeTile({required this.code, required this.selected, required this.onChanged});

  final SupportCode code;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final (color, icon) = switch (code.status) {
      'used' => (Colors.lightBlue.shade700, Icons.task_alt),
      'disabled' => (Colors.red.shade600, Icons.block),
      _ => (Colors.teal.shade700, Icons.verified_outlined),
    };
    String date(String? raw) {
      final d = raw == null ? null : DateTime.tryParse(raw);
      return d == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());
    }

    return Card(
      color: selected ? Colors.teal.shade50 : null,
      child: ListTile(
        leading: onChanged == null
            ? Icon(icon, color: color)
            : Checkbox(value: selected, onChanged: (v) => onChanged!(v ?? false)),
        title: Text(
          code.code,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 4),
        ),
        subtitle: Text(
          [
            '${t['supportCodes.batch']!} ${code.batch}${code.note != null ? ' · ${code.note}' : ''}',
            if (code.patientName != null) '${t['supportCodes.patient']!}: ${code.patientName}',
            if (code.usedAt != null) date(code.usedAt) else date(code.createdAt),
          ].join('\n'),
        ),
        isThreeLine: code.patientName != null,
        trailing: Chip(
          avatar: Icon(icon, size: 16, color: color),
          label: Text(t['supportCodes.${code.status}']!, style: TextStyle(color: color, fontSize: 12)),
          visualDensity: VisualDensity.compact,
        ),
        onTap: onChanged == null ? null : () => onChanged!(!selected),
      ),
    );
  }
}

/// How many codes to make (1–500) and an optional note.
class _GenerateDialog extends ConsumerStatefulWidget {
  const _GenerateDialog();

  @override
  ConsumerState<_GenerateDialog> createState() => _GenerateDialogState();
}

class _GenerateDialogState extends ConsumerState<_GenerateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _count = TextEditingController(text: '50');
  final _note = TextEditingController();

  @override
  void dispose() {
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return AlertDialog(
      title: Text(t['supportCodes.generateHeading']!),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _count,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t['supportCodes.count']!, border: const OutlineInputBorder()),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 || n > 500 ? t['supportCodes.countInvalid']! : null;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: t['supportCodes.note']!,
                hintText: t['supportCodes.notePlaceholder']!,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t['nav.cancel']!)),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, (count: int.parse(_count.text), note: _note.text));
          },
          child: Text(t['supportCodes.generate']!),
        ),
      ],
    );
  }
}
