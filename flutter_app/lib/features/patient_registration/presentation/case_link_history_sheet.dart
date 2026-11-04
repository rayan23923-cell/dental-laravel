import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/tg_spinner.dart';
import '../data/patient_registration_repository.dart';
import '../domain/patient_registration.dart';

/// "سجل الربط" (2026-11-04, by request, against stolen or forged
/// receipts): who the patient was linked to (doctor, task such as قلع,
/// department, when, QR or code) and every refused attempt, e.g. another
/// doctor entering the same receipt. Same data as the web registry's
/// link history (`CasePatientLinks::history()`).
Future<void> showCaseLinkHistory(BuildContext context, WidgetRef ref, PatientRegistration registration) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CaseLinkHistorySheet(registration: registration),
  );
}

class _CaseLinkHistorySheet extends ConsumerStatefulWidget {
  const _CaseLinkHistorySheet({required this.registration});

  final PatientRegistration registration;

  @override
  ConsumerState<_CaseLinkHistorySheet> createState() => _CaseLinkHistorySheetState();
}

class _CaseLinkHistorySheetState extends ConsumerState<_CaseLinkHistorySheet> {
  late final Future<Map<String, dynamic>> _future =
      ref.read(patientRegistrationRepositoryProvider).caseLinkHistory(widget.registration.id);

  static String _when(Object? iso) {
    final parsed = iso is String ? DateTime.tryParse(iso) : null;
    if (parsed == null) return '';
    // Baghdad time, as the rest of the clinic.
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toUtc().add(const Duration(hours: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final r = widget.registration;
    String method(Object? m) => t[m == 'code' ? 'patientRegFlutter.linkMethodCode' : 'patientRegFlutter.linkMethodQr']!;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final e = snapshot.error;
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(e is ApiException ? e.userMessage : t['common.loadFailed']!),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(padding: EdgeInsets.all(32), child: Center(child: TgSpinner()));
            }
            final data = snapshot.data!;
            final link = data['link'] as Map<String, dynamic>?;
            final attempts = ((data['attempts'] as List?) ?? const []).cast<Map<String, dynamic>>();
            final linkDoctor = link?['doctor'] as Map<String, dynamic>?;

            Widget row(String label, String value) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 110, child: Text(label, style: TextStyle(color: Colors.green.shade800))),
                      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                );

            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(t['patientRegFlutter.linkHistoryTitle']!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text([r.name, if (r.patientCode != null) '⁦${r.patientCode}⁩'].join(' · ')),
                const SizedBox(height: 12),
                if (link == null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Text(t['patientRegFlutter.linkNone']!),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.link, size: 18, color: Colors.green.shade800),
                          const SizedBox(width: 4),
                          Text(t['patientRegFlutter.linkCurrent']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 6),
                        row(
                          t['patientRegFlutter.linkDoctor']!,
                          [linkDoctor?['name'], if (linkDoctor?['username'] != null) '(⁦${linkDoctor!['username']}⁩)']
                              .whereType<String>()
                              .join(' '),
                        ),
                        row(
                          t['patientRegFlutter.linkTask']!,
                          '${link['task'] ?? '—'} (${t[link['started'] == true ? 'patientRegFlutter.linkStarted' : 'patientRegFlutter.linkDraft']!})',
                        ),
                        row(t['patientRegFlutter.linkDepartment']!, (link['department'] as String?) ?? '—'),
                        row(t['patientRegFlutter.linkAt']!, _when(link['linked_at'])),
                        row(t['patientRegFlutter.linkMethod']!, method(link['method'])),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(t['patientRegFlutter.linkAttempts']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (attempts.isEmpty) Text(t['patientRegFlutter.linkAttemptsNone']!),
                for (final a in attempts)
                  Builder(builder: (context) {
                    final suspicious = a['reason'] == 'already_used';
                    final color = suspicious ? Colors.red : Colors.orange;
                    final doctor = a['doctor'] as Map<String, dynamic>?;
                    final linked = [a['linked_task'], a['linked_doctor']].whereType<String>().join(' · ');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(suspicious ? Icons.gpp_maybe_outlined : Icons.block, size: 18, color: color.shade800),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                t['patientRegFlutter.attemptReason.${a['reason']}'] ?? '${a['reason']}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: color.shade900),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text([
                            [doctor?['name'], if (doctor?['username'] != null) '(⁦${doctor!['username']}⁩)'].whereType<String>().join(' '),
                            if (a['task'] != null) a['task'] as String,
                            method(a['method']),
                          ].where((s) => s.isNotEmpty).join(' · ')),
                          if (linked.isNotEmpty)
                            Text(trf(t['patientRegFlutter.attemptLinkedTo']!, {'doctor': linked}), style: const TextStyle(fontSize: 12)),
                          Text(_when(a['at']), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}
