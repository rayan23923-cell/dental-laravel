import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

/// A bearer-token-gated QR PNG, fetched as bytes through [ApiClient] (a
/// plain `Image.network` has no clean way to attach the auth header).
/// Generalized from `TaskInstanceQrImage` — every QR endpoint in this app
/// (task instances, patient registrations, ...) returns the same kind of
/// PNG response, so one widget keyed by `path` replaces a second
/// near-duplicate per feature.
class QrImage extends ConsumerWidget {
  const QrImage({super.key, required this.path, this.size = 240});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytesAsync = ref.watch(_qrBytesProvider(path));

    return SizedBox(
      width: size,
      height: size,
      child: bytesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Icon(Icons.qr_code_2, size: 48)),
        data: (bytes) => Image.memory(Uint8List.fromList(bytes)),
      ),
    );
  }
}

final _qrBytesProvider = FutureProvider.autoDispose.family<List<int>, String>((ref, path) {
  return ref.watch(apiClientProvider).getBytes(path);
});
