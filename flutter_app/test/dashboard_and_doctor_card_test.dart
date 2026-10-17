import 'package:dental_clinic_app/features/doctors_admin/domain/doctor_admin.dart';
import 'package:dental_clinic_app/features/doctors_admin/presentation/doctor_card_pdf.dart';
import 'package:dental_clinic_app/features/home/domain/dashboard_data.dart';
import 'package:dental_clinic_app/features/tasks_admin/domain/task_instance_admin.dart';
import 'package:dental_clinic_app/features/task_instances/domain/task_instance_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dashboard reads the web figures', () {
    final data = DashboardData.fromJson({
      'stats': {
        'doctors': 4,
        'registrations': 10,
        'registrations_today': 2,
        'tasks': 3,
        'tasks_done': 1,
        'tasks_not_done': 2,
        'instances_completed': 5,
        'instances_assigned': 3,
        'instances_pending': 0,
      },
      'latestDoctors': [
        {'id': 7, 'name': 'د. علي', 'education_type': 'صباحي', 'created_at': '2026-10-17T09:00:00Z'},
      ],
      'income': {
        'today': {'total': 25000.0},
        'month': {'total': '90000'},
      },
      'currency': 'IQD',
      'educationTypes': [
        {'id': 1, 'name': 'صباحي'},
      ],
      'can': {'doctors': true, 'task_progress': false, 'payments': true},
    });

    expect(data.donePercent, 33);
    expect(data.instancesTotal, 8);
    expect(data.todayIncome, 25000);
    expect(data.monthIncome, 90000);
    expect(data.latestDoctors.single.educationType, 'صباحي');
    expect(data.educationTypes.single.name, 'صباحي');
    expect(data.canDoctors, isTrue);
    expect(data.canTaskProgress, isFalse);

    // No payments role: no income, as on the web.
    final noIncome = DashboardData.fromJson({'stats': <String, dynamic>{}, 'income': null});
    expect(noIncome.todayIncome, isNull);
    expect(noIncome.donePercent, 0);
  });

  test('a task instance reads its doctor, status and string grade', () {
    final i = TaskInstanceAdmin.fromJson({
      'id': 3,
      'doctor_id': 7,
      'status': 'completed',
      'assigned_date': '2026-10-01T10:00:00Z',
      'grade': '9.50',
      'doctor': {'id': 7, 'name': 'د. علي'},
    });
    expect(i.doctorName, 'د. علي');
    expect(i.status, TaskInstanceStatus.completed);
    expect(i.grade, 9.5);
  });

  test('the doctor card builds as a PDF', () async {
    const doctor = DoctorAdmin(
      id: 7,
      name: 'د. علي',
      username: 'ali',
      email: 'ali@example.com',
      phone: null,
      profileImageUrl: null,
      educationTypeId: 1,
      stageId: 1,
      educationTypeName: 'صباحي',
      stageName: 'الرابعة',
      academicSessionId: null,
      academicSessionName: null,
      nfcTagId: null,
      groupNames: ['أ'],
    );
    final bytes = await buildDoctorCardPdf(doctor: doctor, settings: null);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
