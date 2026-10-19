import 'package:dental_clinic_app/core/i18n/locale_controller.dart';
import 'package:dental_clinic_app/core/network/api_client.dart';
import 'package:dental_clinic_app/features/case_sheet_forms/presentation/task_work_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the panel's two calls; everything else is unused here.
class _FakeApi implements ApiClient {
  _FakeApi(this.response);

  final Map<String, dynamic> response;
  String? putPath;
  Object? putBody;

  @override
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async => response;

  @override
  Future<dynamic> putJson(String path, {Object? body}) async {
    putPath = path;
    putBody = body;
    return {'work_items': response['work_items'], 'points': 7};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _work({required bool canEdit}) => {
      'title': 'Composite',
      'scoring': {
        'options': [
          {'label': 'Class I', 'points': 2, 'enabled': true},
          {'label': 'Class II', 'points': 3, 'enabled': true},
        ],
        'modifiers': [
          {'label': 'GIC', 'factor': 1.5},
        ],
        'checklist': [
          {'label': 'Isolation'},
        ],
        'min_points': 10,
      },
      'status': 'in_progress',
      'work_items': [
        {'option': 'Class II', 'qty': 2, 'modifiers': <String>[], 'points': 6},
      ],
      'points': 6,
      'from_sheet': false,
      'can_edit': canEdit,
    };

Future<_FakeApi> _pump(WidgetTester tester, Map<String, dynamic> response) async {
  final api = _FakeApi(response);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      localeProvider.overrideWithValue('en'),
    ],
    child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TaskWorkPanel(taskInstanceId: 5)))),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('staff record work and save it to the task instance', (tester) async {
    final api = await _pump(tester, _work(canEdit: true));

    expect(find.text('Task points'), findsOneWidget);
    expect(find.text('6 pts / 10'), findsOneWidget);
    expect(find.text('Class II (3)'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Save points'));
    await tester.pumpAndSettle();

    expect(api.putPath, '/case-sheets/instances/5/work');
    expect(api.putBody, {
      'work_items': [
        {'option': 1, 'qty': 2, 'grade': null, 'modifiers': <int>[]},
        {'check': 0, 'grade': null},
      ],
    });
    expect(find.text('7 pts / 10'), findsOneWidget);
  });

  testWidgets('a doctor sees the points read-only', (tester) async {
    await _pump(tester, _work(canEdit: false));

    expect(find.text('Save points'), findsNothing);
    expect(find.text('The supervisor enters the points.'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
  });

  testWidgets('a sheet-graded task grades only hand-added steps', (tester) async {
    final api = await _pump(tester, {
      'title': 'Crown',
      'scoring': {
        'steps': [
          {'key': 'prep', 'label': 'Preparation', 'max': 5},
          {'key': 'c1', 'label': 'Polish', 'max': 3, 'custom': true},
        ],
      },
      'work_items': [
        {'option': 'Preparation', 'step': 'prep', 'points': 4, 'max': 5},
        {'option': 'Polish', 'step': 'c1', 'points': 1, 'max': 3, 'custom': true},
      ],
      'points': 5,
      'from_sheet': true,
      'can_edit': true,
    });

    // The sheet's own stage is graded in the sheet's stages section (2026-10-19).
    expect(find.text('4 / 5'), findsNothing);
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Save points'));
    await tester.pumpAndSettle();

    expect(api.putBody, {
      'step_grades': {'c1': 2.0},
    });
  });
}
