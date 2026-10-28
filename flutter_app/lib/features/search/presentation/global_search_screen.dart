import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/staff_access.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_state.dart';
import '../../doctors_admin/data/doctors_admin_repository.dart';
import '../../doctors_admin/domain/doctor_admin.dart';
import '../../patient_registration/data/patient_registration_repository.dart';
import '../../patient_registration/domain/patient_registration.dart';
import '../../records/data/records_repository.dart';
import '../../records/domain/patient.dart';

/// One search box for tickets, patients and students (2026-10-28, by
/// request: "بحث موحّد في الأعلى" — Telegram's top search), instead of
/// opening each list and searching there. Each section uses that list's
/// own `search` API and shows only what the account may open.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _Results {
  const _Results({this.tickets = const [], this.patients = const [], this.students = const []});
  final List<PatientRegistration> tickets;
  final List<Patient> patients;
  final List<DoctorAdmin> students;

  bool get isEmpty => tickets.isEmpty && patients.isEmpty && students.isEmpty;
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  static const _perSection = 8;

  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  _Results _results = const _Results();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool _allowed(String route) {
    final authState = ref.read(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;
    return account is StaffAccount && staffCanOpen(account, route);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _query = query);
    if (query.length < 2) {
      setState(() => _results = const _Results());
      return;
    }
    setState(() => _loading = true);

    // A failing section (no grant, offline) is left empty, not an error
    // for the whole search.
    Future<List<T>> safe<T>(Future<List<T>> Function() load) async {
      try {
        return await load();
      } catch (_) {
        return <T>[];
      }
    }

    final tickets = _allowed('/records/patient-registrations')
        ? safe(() async =>
            (await ref.read(patientRegistrationRepositoryProvider).listPage(search: query)).page.items)
        : Future.value(<PatientRegistration>[]);
    final patients = _allowed('/records/patients')
        ? safe(() async => (await ref.read(recordsRepositoryProvider).listPatients(search: query)).items)
        : Future.value(<Patient>[]);
    final students = _allowed('/admin/doctors')
        ? safe(() async => (await ref.read(doctorsAdminRepositoryProvider).list(search: query)).items)
        : Future.value(<DoctorAdmin>[]);

    final results = _Results(
      tickets: (await tickets).take(_perSection).toList(),
      patients: (await patients).take(_perSection).toList(),
      students: (await students).take(_perSection).toList(),
    );
    // Typed on meanwhile: only the latest query's answer is shown.
    if (!mounted || query != _query) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _openTicket(PatientRegistration registration) async {
    try {
      final state = await ref.read(patientRegistrationRepositoryProvider).status(registration.id);
      if (mounted) context.push('/records/patient-registrations/payment', extra: state);
    } catch (e) {
      if (!mounted) return;
      final t = ref.read(translationsProvider);
      final message = e is ApiException ? e.userMessage : t['patientRegFlutter.openPaymentFailed']!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);

    Widget section(String title, List<Widget> rows) => rows.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                clipBehavior: Clip.antiAlias,
                child: Column(children: rows),
              ),
            ],
          );

    String join(List<String?> parts) => parts.where((p) => p != null && p.isNotEmpty).join(' · ');

    final Widget body;
    if (_query.length < 2) {
      body = _Hint(icon: Icons.search, text: t['search.typeMore']!);
    } else if (_loading && _results.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_results.isEmpty) {
      body = _Hint(icon: Icons.search_off, text: t['search.empty']!);
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          section(t['search.tickets']!, [
            for (final r in _results.tickets)
              ChatListTile(
                title: r.name,
                subtitle: join([r.phone, r.serviceName]),
                icon: Icons.confirmation_number_outlined,
                color: Colors.indigo,
                onTap: () => _openTicket(r),
              ),
          ]),
          section(t['search.patients']!, [
            for (final p in _results.patients)
              ChatListTile(
                title: p.name,
                subtitle: join([p.phone, p.doctorName]),
                icon: Icons.person_outline,
                color: Colors.teal,
                onTap: () => context.push('/records/patients/${p.id}'),
              ),
          ]),
          section(t['search.students']!, [
            for (final d in _results.students)
              ChatListTile(
                title: d.name,
                subtitle: join([d.stageName, d.phone]),
                icon: Icons.school_outlined,
                imageUrl: d.profileImageUrl,
                color: Colors.green,
                onTap: () => context.push('/admin/doctors/${d.id}'),
              ),
          ]),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            _search(v.trim());
          },
          decoration: InputDecoration(
            hintText: t['search.hint'],
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _search('');
              },
            ),
        ],
      ),
      body: body,
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}
