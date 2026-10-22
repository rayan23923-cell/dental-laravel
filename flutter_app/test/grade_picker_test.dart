import 'package:dental_clinic_app/features/form_settings/presentation/grade_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('grades are picked with a tap, a half and full marks', (tester) async {
    double? value;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: GradePicker(
              max: 10,
              value: value,
              onChanged: (v) => setState(() => value = v),
              labels: const {'outOf': 'من {max}', 'full': 'كاملة', 'half': '+ نصف', 'clear': 'مسح'},
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(ChoiceChip, '7'));
    await tester.pumpAndSettle();
    expect(value, 7);

    await tester.tap(find.text('+ نصف'));
    await tester.pumpAndSettle();
    expect(value, 7.5);

    await tester.tap(find.textContaining('كاملة'));
    await tester.pumpAndSettle();
    expect(value, 10);

    await tester.tap(find.text('مسح'));
    await tester.pump();
    expect(value, isNull);
  });
}
