import '../../task_progress_admin/domain/task_progress_group.dart';

/// Mirrors `Api\TaskProgressController::mine()`/`App\Services\DoctorTaskSummary`
/// — the single-doctor equivalent of the admin `task_progress_admin`
/// feature's `TaskProgressDepartment` (which nests a *list* of doctors,
/// since staff view a whole group). Here there's always exactly one
/// doctor (the authenticated principal), so the backend nests a single
/// `doctor` object instead of a one-item list — reuses
/// `TaskProgressDoctorRow`/`TaskSlotCard` as-is since that inner shape is
/// identical (`App\Services\TaskProgressGroupSummary::buildDoctorRow()` is
/// the shared implementation on the backend).
class MyTaskDepartment {
  const MyTaskDepartment({required this.id, required this.name, required this.doctor});

  factory MyTaskDepartment.fromJson(Map<String, dynamic> json) => MyTaskDepartment(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        doctor: TaskProgressDoctorRow.fromJson(json['doctor'] as Map<String, dynamic>),
      );

  final int id;
  final String name;
  final TaskProgressDoctorRow doctor;
}
