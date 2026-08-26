import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../domain/patient.dart';
import '../records_providers.dart';

/// `GET /patients` — staff-only. `pickMode: true` turns taps into
/// `Navigator.pop(patient)` instead of pushing the edit screen, reused by
/// `AppointmentFormScreen`'s patient picker so there's one patient list,
/// not two.
class PatientListScreen extends ConsumerStatefulWidget {
  const PatientListScreen({super.key, this.pickMode = false});
  final bool pickMode;

  @override
  ConsumerState<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends ConsumerState<PatientListScreen> {
  final _searchController = TextEditingController();
  String? _search;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientListProvider(_search));

    return Scaffold(
      appBar: AppBar(title: Text(widget.pickMode ? 'اختر مريضًا' : 'المرضى')),
      floatingActionButton: widget.pickMode
          ? null
          : FloatingActionButton(
              onPressed: () => context.push('/records/patients/new'),
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ابحث بالاسم أو الهاتف',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : v.trim()),
            ),
          ),
          Expanded(
            child: patientsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return const Center(child: Text('لا يوجد مرضى بعد.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(patientListProvider(_search)),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: page.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _PatientTile(patient: page.items[i], pickMode: widget.pickMode),
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

class _PatientTile extends StatelessWidget {
  const _PatientTile({required this.patient, required this.pickMode});
  final Patient patient;
  final bool pickMode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(patient.name),
        subtitle: Text([
          if (patient.phone != null && patient.phone!.isNotEmpty) patient.phone!,
          if (patient.stageName != null) patient.stageName!,
        ].join(' · ').ifEmpty('—')),
        trailing: const Icon(Icons.chevron_left),
        onTap: () {
          if (pickMode) {
            Navigator.of(context).pop(patient);
          } else {
            context.push('/records/patients/${patient.id}');
          }
        },
      ),
    );
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
