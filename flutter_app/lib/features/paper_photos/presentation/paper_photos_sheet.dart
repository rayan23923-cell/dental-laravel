import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/paper_photos_repository.dart';

/// Opens the paper case-sheet photos of one task instance (2026-10-13, the
/// same feature as the web's PaperPhotos.vue): take a photo with the camera
/// or pick from the gallery, see them, delete one. Resolves to the photo
/// count once closed, so the caller can refresh its badge.
Future<int?> showPaperPhotosSheet(
  BuildContext context, {
  required int instanceId,
  required String title,
  bool doctor = false,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PaperPhotosSheet(instanceId: instanceId, title: title, doctor: doctor),
  );
}

class _PaperPhotosSheet extends ConsumerStatefulWidget {
  const _PaperPhotosSheet({required this.instanceId, required this.title, required this.doctor});

  final int instanceId;
  final String title;
  final bool doctor;

  @override
  ConsumerState<_PaperPhotosSheet> createState() => _PaperPhotosSheetState();
}

class _PaperPhotosSheetState extends ConsumerState<_PaperPhotosSheet> {
  List<PaperPhoto>? _photos;
  int _uploading = 0;
  String? _error;

  PaperPhotosRepository get _repository => ref.read(paperPhotosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _failed(Object e) {
    final t = ref.read(translationsProvider);
    setState(() => _error = e is ApiException ? e.userMessage : t['paperPhotos.failed']!);
  }

  Future<void> _load() async {
    try {
      final photos = await _repository.list(doctor: widget.doctor, instanceId: widget.instanceId);
      if (mounted) setState(() => _photos = photos);
    } catch (e) {
      if (mounted) _failed(e);
    }
  }

  Future<void> _add(ImageSource source) async {
    final picker = ImagePicker();
    final files = source == ImageSource.camera
        ? [if (await picker.pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 82) case final f?) f]
        : await picker.pickMultiImage(maxWidth: 2000, maxHeight: 2000, imageQuality: 82);
    for (final file in files) {
      if (!mounted) return;
      setState(() {
        _uploading++;
        _error = null;
      });
      try {
        final photos = await _repository.upload(doctor: widget.doctor, instanceId: widget.instanceId, photo: file);
        if (mounted) setState(() => _photos = photos);
      } catch (e) {
        if (mounted) _failed(e);
      } finally {
        if (mounted) setState(() => _uploading--);
      }
    }
  }

  Future<void> _delete(PaperPhoto photo) async {
    final t = ref.read(translationsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t['paperPhotos.confirmDelete']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t['paperPhotos.cancel']!)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t['paperPhotos.delete']!)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repository.delete(doctor: widget.doctor, photoId: photo.id);
      await _load();
    } catch (e) {
      if (mounted) _failed(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final photos = _photos;
    final canUseCamera = ImagePicker().supportsImageSource(ImageSource.camera);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _photos?.length);
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t['paperPhotos.title']!, style: Theme.of(context).textTheme.titleMedium),
              Text(widget.title, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canUseCamera)
                    FilledButton.icon(
                      onPressed: () => _add(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(t['paperPhotos.takePhoto']!),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _add(ImageSource.gallery),
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(t['paperPhotos.upload']!),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              if (photos == null && _error == null)
                const Center(child: CircularProgressIndicator())
              else if ((photos ?? []).isEmpty && _uploading == 0)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t['paperPhotos.none']!, textAlign: TextAlign.center),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                  child: GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final photo in photos ?? <PaperPhoto>[])
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            GestureDetector(
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(photo.url))),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(photo.url, fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              left: 2,
                              child: IconButton.filledTonal(
                                iconSize: 18,
                                tooltip: t['paperPhotos.delete'],
                                onPressed: () => _delete(photo),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ],
                        ),
                      for (var i = 0; i < _uploading; i++)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
