import 'package:dental_clinic_app/core/i18n/app_translations.dart';
import 'package:dental_clinic_app/core/i18n/locale_controller.dart';
import 'package:dental_clinic_app/core/network/server_status.dart';
import 'package:dental_clinic_app/core/widgets/server_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStatus extends ServerStatusController {
  int checks = 0;

  @override
  ServerStatus build() => const ServerStatus(link: ServerLink.online);

  void set(ServerStatus next) => state = next;

  @override
  Future<void> check() async => checks++;
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(onPressed: () => setState(() => taps++), child: Text('taps $taps'));
}

void main() {
  testWidgets('offline strip shows, keeps the app state, and reconnects', (tester) async {
    final fake = _FakeStatus();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverStatusProvider.overrideWith(() => fake),
          translationsProvider.overrideWithValue(kTranslationsAr),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          home: ServerStatusFrame(
            child: Scaffold(body: Center(child: _Counter())),
          ),
        ),
      ),
    );

    await tester.tap(find.text('taps 0'));
    await tester.pump();
    expect(find.text('انقطع الاتصال بالسيرفر، وتتم إعادة المحاولة تلقائياً'), findsNothing);

    fake.set(const ServerStatus(link: ServerLink.offline, reason: ServerDownReason.unreachable, failures: 1));
    await tester.pump();
    expect(find.text('انقطع الاتصال بالسيرفر، وتتم إعادة المحاولة تلقائياً'), findsOneWidget);
    // The routed app underneath was not rebuilt from scratch.
    expect(find.text('taps 1'), findsOneWidget);

    await tester.tap(find.text('إعادة الاتصال'));
    expect(fake.checks, 1);

    fake.set(const ServerStatus(link: ServerLink.online));
    await tester.pump();
    expect(find.text('عاد الاتصال بالسيرفر'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('عاد الاتصال بالسيرفر'), findsNothing);
    expect(find.text('taps 1'), findsOneWidget);
  });
}
