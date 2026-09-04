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
import '../../clinic_settings/presentation/clinic_settings_providers.dart';
import '../domain/doctor_admin.dart';
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

  @override
  Widget build(BuildContext context) {
    final educationTypesAsync = ref.watch(doctorEducationTypesProvider);
    final stagesAsync = ref.watch(doctorStagesProvider);
    final doctorsAsync = ref.watch(doctorAdminListProvider(_filter));
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/doctors/new'),
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
                    hintText: t['doctorsAdmin.searchHint'],
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _scanningNfc
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(icon: const Icon(Icons.nfc), tooltip: t['doctorsAdmin.scanNfcTooltip'], onPressed: _scanNfc),
                  ),
                  onSubmitted: (v) => setState(() => _search = v.trim().isEmpty ? null : v.trim()),
                ),
                const SizedBox(height: 8),
                CascadingDropdown(
                  label: t['doctorsAdmin.educationTypeLabel']!,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: page.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _DoctorTile(doctor: page.items[i]),
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

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({required this.doctor});
  final DoctorAdmin doctor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: doctor.profileImageUrl != null ? NetworkImage(doctor.profileImageUrl!) : null,
          child: doctor.profileImageUrl == null ? Text(doctor.name.isNotEmpty ? doctor.name[0] : '?') : null,
        ),
        title: Text(doctor.name),
        subtitle: Text([
          doctor.username,
          if (doctor.stageName != null) doctor.stageName!,
          if (doctor.educationTypeName != null) doctor.educationTypeName!,
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => context.push('/admin/doctors/${doctor.id}'),
      ),
    );
  }
}
