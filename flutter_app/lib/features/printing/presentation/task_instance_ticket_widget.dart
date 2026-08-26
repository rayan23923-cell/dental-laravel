import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ticket_row.dart';

/// The printed receipt handed to a student when staff start a task for
/// them in "تقدم المهام" — so they have something physical to keep,
/// with a QR code that reopens this exact task instance later for
/// review/status updates (see `Api\TaskInstanceQrController`/
/// `qr_scan_screen.dart`'s existing `QrScanMode.taskInstance` — that
/// scan-to-review loop already exists end to end; this widget only adds
/// the print trigger and layout). Sibling to `TicketWidget`
/// (patient-registration ticket), copying its exact structure, but takes
/// primitives instead of a typed domain object so `printing/` doesn't
/// gain a dependency on `task_progress_admin/domain/`.
class TaskInstanceTicketWidget extends StatelessWidget {
  const TaskInstanceTicketWidget({
    super.key,
    required this.doctorName,
    required this.taskTitle,
    this.departmentName,
    this.educationTypeName,
    this.stageName,
    this.groupName,
    this.notes,
    required this.startedAt,
    this.startedByName,
    this.qrBytes,
    this.logoBytes,
    this.widthDots = 384,
  });

  final String doctorName;
  final String taskTitle;
  final String? departmentName;

  /// The doctor/student's own education type, stage, and group — the same
  /// "Fourth Stage · primary Education" / "Group A" context already shown
  /// on the Task Progress screen, added to the receipt on request so it's
  /// on the paper too, not just on screen.
  final String? educationTypeName;
  final String? stageName;
  final String? groupName;

  final String? notes;

  /// The staff member who started this task, if known.
  final String? startedByName;

  /// Pre-formatted by the caller (same as `TicketWidget`'s internal
  /// `dateStr`), so this widget stays free of date-parsing concerns.
  final String startedAt;

  /// The task-instance QR (`GET /task-instances/{id}/qr`), fetched by the
  /// caller as raw PNG bytes — same fail-open contract as `TicketWidget`:
  /// null just omits the QR, never blocks printing.
  final Uint8List? qrBytes;

  /// The teaching hospital's logo, fetched the same way `TicketWidget`'s
  /// own [logoBytes] already is.
  final Uint8List? logoBytes;

  final double widthDots;

  @override
  Widget build(BuildContext context) {
    // Explicitly larger than TicketWidget's `widthDots * 0.55` — this
    // ticket's QR was specifically requested "large" (it's the student's
    // only way back into the app to update/complete this task later,
    // unlike the registration ticket's QR which desk staff also has a
    // fallback path for via search).
    final qrSize = widthDots * 0.75;

    return Container(
      width: widthDots,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (logoBytes != null) ...[
              Image.memory(logoBytes!, width: 72, height: 72),
              const SizedBox(height: 8),
            ],
            const Text(
              'المستشفى التعليمي لكلية طب الأسنان',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'جامعة تكريت',
              style: TextStyle(color: Colors.black, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.black, thickness: 1),
            const SizedBox(height: 8),
            ticketRow('الطالب/الطبيب', doctorName),
            if (educationTypeName != null) ticketRow('نوع الدراسة', educationTypeName!),
            if (stageName != null) ticketRow('المرحلة', stageName!),
            if (groupName != null) ticketRow('المجموعة', groupName!),
            ticketRow('المهمة', taskTitle),
            if (departmentName != null) ticketRow('القسم', departmentName!),
            if (notes != null && notes!.isNotEmpty) ticketRow('ملاحظات', notes!),
            ticketRow('وقت البدء', startedAt),
            if (startedByName != null && startedByName!.isNotEmpty) ticketRow('بدأ بواسطة', startedByName!),
            const SizedBox(height: 8),
            const Divider(color: Colors.black, thickness: 1),
            if (qrBytes != null) ...[
              const SizedBox(height: 12),
              Image.memory(qrBytes!, width: qrSize, height: qrSize),
              const Text(
                'يُمسح هذا الرمز لعرض حالة المهمة وتحديثها',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
