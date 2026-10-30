import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/i18n/locale_controller.dart';
import '../../core/theme/app_theme.dart';
import '../auth/domain/auth_account.dart';
import '../auth/presentation/auth_controller.dart';
import '../auth/presentation/auth_state.dart';

/// The doctor's own QR (2026-10-30, by request: "استبدل مسح كيو ار باظهار
/// كيو ار كود"): `{"type":"doctor","id":N}`, the same payload printed on
/// their ID card (`DoctorPrintController::qr`). A supervisor scans it from
/// task progress (`QrScanScreen` / the web's scan modal) to open this
/// doctor's tasks. Drawn here, so it shows offline too.
class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final account = authState is Authenticated ? authState.account : null;

    return Scaffold(
      appBar: AppBar(title: Text(t['myQr.title']!)),
      body: account is! DoctorAccount
          ? Center(child: Text(t['myQr.doctorsOnly']!))
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Avatar(account: account),
                        const SizedBox(height: 12),
                        Text(
                          account.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if ((account.stageName ?? account.educationTypeName) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              account.stageName ?? account.educationTypeName!,
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        const SizedBox(height: 20),
                        // Always on white with a quiet zone, so cameras read
                        // it in dark mode too.
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
                            ],
                          ),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: SvgPicture.string(
                              Barcode.qrCode().toSvg(doctorQrPayload(account.id), width: 300, height: 300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t['myQr.hint']!, style: theme.textTheme.bodyMedium)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Same JSON as the server's `QrCodeFactory::payload('doctor', $id)`.
String doctorQrPayload(int id) => '{"type":"doctor","id":$id}';

class _Avatar extends StatelessWidget {
  const _Avatar({required this.account});
  final DoctorAccount account;

  @override
  Widget build(BuildContext context) {
    final url = account.profileImageUrl;
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(gradient: InstagramColors.gradient, shape: BoxShape.circle),
      child: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        backgroundImage: url != null ? NetworkImage(url) : null,
        child: url == null ? Text(account.name.isNotEmpty ? account.name[0] : '?', style: const TextStyle(fontSize: 26)) : null,
      ),
    );
  }
}
