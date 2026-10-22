import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';

final formSettingsRepositoryProvider = Provider<FormSettingsRepository>((ref) {
  return FormSettingsRepository(ref.watch(apiClientProvider));
});

/// What a student's screens follow (`GET /my-form-settings`). An older
/// server without it answers 404, read as everything on and no code.
/// The system-wide switches for staff screens (`GET /form-settings`); all
/// on when it can't be read (an older server or no access).
final taskSwitchesProvider = FutureProvider.autoDispose<FormSettings>((ref) async {
  try {
    return (await ref.watch(formSettingsRepositoryProvider).get()).settings;
  } catch (_) {
    return const FormSettings();
  }
});

Map<String, bool> _switches(Map<String, dynamic> json) => {
      for (final key in const ['task_start_enabled', 'task_finish_enabled', 'task_lists_enabled', 'grade_entry_enabled', 'step_add_enabled', 'steps_enabled'])
        if (json[key] is bool) key: json[key] as bool,
    };

final myFormSettingsProvider = FutureProvider.autoDispose<DoctorFormSettings>((ref) async {
  try {
    return await ref.watch(formSettingsRepositoryProvider).mine();
  } catch (_) {
    return const DoctorFormSettings();
  }
});

/// "إعدادات النماذج" (2026-10-22, by request): paper or electronic forms,
/// grades shown to students and the supervisor code, the same
/// `FormSettingsController`/`SupervisorCodeController` the web uses.
class FormSettingsRepository {
  FormSettingsRepository(this._client);
  final ApiClient _client;

  Future<FormSettingsPage> get() async => FormSettingsPage.fromJson(await _client.getJson('/form-settings') as Map<String, dynamic>);

  Future<FormSettings> save(FormSettings settings) async {
    final data = await _client.putJson('/form-settings', body: settings.toJson()) as Map<String, dynamic>;
    return FormSettings.fromJson(data['settings'] as Map<String, dynamic>);
  }

  Future<SupervisorCodeNow> myCode() async => SupervisorCodeNow.fromJson(await _client.getJson('/task-progress/my-code') as Map<String, dynamic>);

  Future<DoctorFormSettings> mine() async => DoctorFormSettings.fromJson(await _client.getJson('/my-form-settings') as Map<String, dynamic>);

  /// The case's steps in order, with what is signed (`TaskWorkController::show`).
  Future<List<CaseStep>> steps(int instanceId) async {
    final data = await _client.getJson('/case-sheets/instances/$instanceId/work') as Map<String, dynamic>;
    return [for (final s in (data['steps'] as List<dynamic>? ?? const [])) CaseStep.fromJson(s as Map<String, dynamic>)];
  }

  /// Each returns the supervisor's name.
  Future<String> start({required int taskId, required String code, required String formType, XFile? photo, String? notes}) async {
    final formData = FormData.fromMap({
      'task_id': taskId,
      'code': code,
      'form_type': formType,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (photo != null) 'photo': MultipartFile.fromBytes(await photo.readAsBytes(), filename: photo.name),
    });
    final data = await _client.postFile('/my-supervisor-code/start', formData: formData) as Map<String, dynamic>;
    return data['supervisor'] as String? ?? '';
  }

  Future<String> signStep(int instanceId, {required String code, required String step, double? grade}) async {
    final data = await _client.postJson('/my-supervisor-code/instances/$instanceId/step', body: {'code': code, 'step': step, 'grade': grade}) as Map<String, dynamic>;
    return data['supervisor'] as String? ?? '';
  }

  Future<String> complete(int instanceId, {required String code, double? grade, String? notes}) async {
    final data = await _client.postJson('/my-supervisor-code/instances/$instanceId/complete', body: {
      'code': code,
      'grade': grade,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    }) as Map<String, dynamic>;
    return data['supervisor'] as String? ?? '';
  }
}

class FormSettings {
  const FormSettings({
    this.electronic = true,
    this.paper = true,
    this.showGrades = true,
    this.codeEnabled = false,
    this.period = 'daily',
    this.actions = const ['start', 'step', 'finish'],
    this.switches = const {},
  });

  factory FormSettings.fromJson(Map<String, dynamic> json) => FormSettings(
        electronic: json['electronic_forms_enabled'] as bool? ?? true,
        paper: json['paper_forms_enabled'] as bool? ?? true,
        showGrades: json['show_grades_to_doctors'] as bool? ?? true,
        codeEnabled: json['supervisor_code_enabled'] as bool? ?? false,
        period: json['supervisor_code_period'] as String? ?? 'daily',
        actions: [for (final a in (json['supervisor_code_actions'] as List<dynamic>? ?? const [])) a as String],
        switches: _switches(json),
      );

  /// Task progress switched on/off for the whole system (2026-10-22).
  final Map<String, bool> switches;
  bool on(String key) => switches[key] ?? true;

  final bool electronic;
  final bool paper;
  final bool showGrades;
  final bool codeEnabled;
  final String period;
  final List<String> actions;

  Map<String, dynamic> toJson() => {
        'electronic_forms_enabled': electronic,
        'paper_forms_enabled': paper,
        'supervisor_code_enabled': codeEnabled,
        'supervisor_code_period': period,
        'supervisor_code_actions': actions,
      };

  FormSettings copyWith({bool? electronic, bool? paper, bool? showGrades, bool? codeEnabled, String? period, List<String>? actions}) => FormSettings(
        electronic: electronic ?? this.electronic,
        paper: paper ?? this.paper,
        showGrades: showGrades ?? this.showGrades,
        codeEnabled: codeEnabled ?? this.codeEnabled,
        period: period ?? this.period,
        actions: actions ?? this.actions,
        switches: switches,
      );
}

class FormSettingsPage {
  const FormSettingsPage({required this.settings, required this.canEdit, this.myCode});

  factory FormSettingsPage.fromJson(Map<String, dynamic> json) => FormSettingsPage(
        settings: FormSettings.fromJson(json['settings'] as Map<String, dynamic>),
        canEdit: json['canEdit'] as bool? ?? false,
        myCode: json['myCode'] != null ? SupervisorCodeNow.fromJson(json['myCode'] as Map<String, dynamic>) : null,
      );

  final FormSettings settings;
  final bool canEdit;
  final SupervisorCodeNow? myCode;
}

class SupervisorCodeNow {
  const SupervisorCodeNow({required this.code, required this.period, required this.expiresAt});

  factory SupervisorCodeNow.fromJson(Map<String, dynamic> json) => SupervisorCodeNow(
        code: json['code'] as String? ?? '',
        period: json['period'] as String? ?? 'daily',
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ?? DateTime.now().add(const Duration(hours: 1)),
      );

  final String code;
  final String period;
  final DateTime expiresAt;
}

class DoctorFormSettings {
  const DoctorFormSettings({this.electronic = true, this.paper = true, this.showGrades = true, this.codeActions = const [], this.switches = const {}});

  factory DoctorFormSettings.fromJson(Map<String, dynamic> json) => DoctorFormSettings(
        electronic: json['electronic_forms_enabled'] as bool? ?? true,
        paper: json['paper_forms_enabled'] as bool? ?? true,
        showGrades: json['show_grades'] as bool? ?? true,
        codeActions: [for (final a in (json['supervisor_code_actions'] as List<dynamic>? ?? const [])) a as String],
        switches: _switches(json),
      );

  final bool electronic;
  final bool paper;
  final bool showGrades;
  final List<String> codeActions;
  final Map<String, bool> switches;
  bool on(String key) => switches[key] ?? true;

  bool get codeCanStart => codeActions.contains('start');
  bool get codeCanProgress => codeActions.contains('step') || codeActions.contains('finish');
}

class CaseStep {
  const CaseStep({required this.key, required this.label, this.max, required this.signed});

  factory CaseStep.fromJson(Map<String, dynamic> json) => CaseStep(
        key: json['key'] as String,
        label: json['label'] as String? ?? '',
        max: double.tryParse(json['max']?.toString() ?? ''),
        signed: json['signed'] as bool? ?? false,
      );

  final String key;
  final String label;
  final double? max;
  final bool signed;
}
