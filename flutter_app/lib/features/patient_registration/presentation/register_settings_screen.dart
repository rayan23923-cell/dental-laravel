import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../records/presentation/records_providers.dart' show tasksLookupProvider;
import '../data/patient_registration_repository.dart';
import '../domain/register_day.dart';
import '../domain/service.dart';
import 'patient_registration_providers.dart';

/// "إعدادات التسجيل: الأيام وأنواع الخدمات" — mirrors
/// `PatientRegistrations/Settings.vue` (itself a port of
/// `admin/register_settings.php`): a day-name field, a service-name field
/// plus a day multi-select, and lists of both with delete. Admin-only —
/// `permission:settings,edit` server-side, same gate the web settings
/// page uses.
class RegisterSettingsScreen extends ConsumerStatefulWidget {
  const RegisterSettingsScreen({super.key});

  @override
  ConsumerState<RegisterSettingsScreen> createState() => _RegisterSettingsScreenState();
}

class _RegisterSettingsScreenState extends ConsumerState<RegisterSettingsScreen> {
  final _dayNameController = TextEditingController();
  final _serviceNameController = TextEditingController();
  final _dayFilterController = TextEditingController();
  final _taskFilterController = TextEditingController();
  final Set<int> _selectedDayIds = {};
  // Day-governed diagnosis ("التشخيص") — per-task editable day set,
  // lazily seeded from `registerDaysProvider`'s nested `taskIds` the
  // first time each task row builds (inverted: day → its tasks becomes
  // task → its days here). Saved individually via a "حفظ" button per
  // row, unlike services (create-time sync only) — tasks already exist.
  final Map<int, Set<int>> _taskDayIds = {};
  final Set<int> _savingTaskDays = {};
  bool _addingDay = false;
  bool _addingService = false;

  @override
  void dispose() {
    _dayNameController.dispose();
    _serviceNameController.dispose();
    _dayFilterController.dispose();
    _taskFilterController.dispose();
    super.dispose();
  }

  Set<int> _dayIdsForTask(int taskId, List<RegisterDay> days) =>
      _taskDayIds[taskId] ??= days.where((d) => d.taskIds.contains(taskId)).map((d) => d.id).toSet();

  Future<void> _saveTaskDays(int taskId) async {
    setState(() => _savingTaskDays.add(taskId));
    try {
      await ref.read(patientRegistrationRepositoryProvider).updateTaskDays(taskId, _taskDayIds[taskId]!.toList());
      ref.invalidate(registerDaysProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ.')));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _savingTaskDays.remove(taskId));
    }
  }

  Future<void> _addDay() async {
    if (_dayNameController.text.trim().isEmpty) return;
    setState(() => _addingDay = true);
    try {
      await ref.read(patientRegistrationRepositoryProvider).createDay(_dayNameController.text.trim());
      _dayNameController.clear();
      ref.invalidate(registerDaysProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة اليوم.')));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _addingDay = false);
    }
  }

  Future<void> _deleteDay(RegisterDay day) async {
    try {
      await ref.read(patientRegistrationRepositoryProvider).deleteDay(day.id);
      ref.invalidate(registerDaysProvider);
      ref.invalidate(servicesProvider);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحذف.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _addService() async {
    if (_serviceNameController.text.trim().isEmpty) return;
    setState(() => _addingService = true);
    try {
      await ref
          .read(patientRegistrationRepositoryProvider)
          .createService(_serviceNameController.text.trim(), _selectedDayIds.toList());
      _serviceNameController.clear();
      setState(() => _selectedDayIds.clear());
      ref.invalidate(servicesProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة الخدمة.')));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _addingService = false);
    }
  }

  Future<void> _deleteService(Service service) async {
    try {
      await ref.read(patientRegistrationRepositoryProvider).deleteService(service.id);
      ref.invalidate(servicesProvider);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحذف.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysAsync = ref.watch(registerDaysProvider);
    final servicesAsync = ref.watch(servicesProvider);
    final tasksAsync = ref.watch(tasksLookupProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات التسجيل')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('الأيام', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dayNameController,
                  decoration: const InputDecoration(labelText: 'اسم اليوم', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              // `Row` hands a non-flexible child an unbounded max width —
              // most widgets tolerate that by sizing to their intrinsic
              // content, but `FilledButton`'s internal layout does not,
              // and throws "BoxConstraints forces an infinite width" when
              // nested inside a ListView/sliver (confirmed live: the exact
              // failure was silent — a blank screen with no error UI, the
              // real assertion only visible in `flutter run`'s console).
              // `Flexible` gives it a bounded max instead.
              Flexible(
                child: FilledButton(
                  onPressed: _addingDay ? null : _addDay,
                  child: const Text('إضافة'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          daysAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (error, _) => Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
            data: (days) => Column(
              children: [
                for (final day in days)
                  Card(
                    child: ListTile(
                      title: Text(day.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteDay(day),
                      ),
                    ),
                  ),
                if (days.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد أيام بعد.')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('الخدمات', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _serviceNameController,
            decoration: const InputDecoration(labelText: 'اسم الخدمة', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          daysAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (days) {
              // Filters which day chips are *shown* — selections already
              // made stay selected even if the chip is filtered out of
              // view, since `_selectedDayIds` isn't touched here.
              final query = _dayFilterController.text.trim();
              final visibleDays =
                  query.isEmpty ? days : days.where((d) => d.name.contains(query)).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (days.length > 6) ...[
                    TextField(
                      controller: _dayFilterController,
                      decoration: const InputDecoration(
                        labelText: 'تصفية الأيام',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final day in visibleDays)
                        FilterChip(
                          label: Text(day.name),
                          selected: _selectedDayIds.contains(day.id),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _selectedDayIds.add(day.id);
                            } else {
                              _selectedDayIds.remove(day.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _addingService ? null : _addService,
            child: const Text('إضافة خدمة'),
          ),
          const SizedBox(height: 16),
          servicesAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (error, _) => Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
            data: (services) => Column(
              children: [
                for (final service in services)
                  Card(
                    child: ListTile(
                      title: Text(service.name),
                      subtitle: Text(service.days.isEmpty ? '—' : service.days.map((d) => d.name).join('، ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteService(service),
                      ),
                    ),
                  ),
                if (services.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد خدمات بعد.')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('التشخيص', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'أيام كل تشخيص تُدار هنا فقط — إضافة التشخيص نفسه من شاشة المهام. تشخيص بلا أيام محددة يبقى متاحاً كل الأيام.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          daysAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (days) => tasksAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              error: (error, _) => Text(error is ApiException ? error.userMessage : 'تعذر التحميل.'),
              data: (allTasks) {
                final query = _taskFilterController.text.trim();
                final tasks = query.isEmpty ? allTasks : allTasks.where((t) => t.name.contains(query)).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (allTasks.length > 6) ...[
                      TextField(
                        controller: _taskFilterController,
                        decoration: const InputDecoration(
                          labelText: 'تصفية التشخيص',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (final task in tasks)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final day in days)
                                    FilterChip(
                                      label: Text(day.name),
                                      selected: _dayIdsForTask(task.id, days).contains(day.id),
                                      onSelected: (selected) => setState(() {
                                        final ids = _dayIdsForTask(task.id, days);
                                        if (selected) {
                                          ids.add(day.id);
                                        } else {
                                          ids.remove(day.id);
                                        }
                                      }),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: FilledButton(
                                  onPressed: _savingTaskDays.contains(task.id) ? null : () => _saveTaskDays(task.id),
                                  child: _savingTaskDays.contains(task.id)
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('حفظ'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (tasks.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد نتائج مطابقة.')),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
