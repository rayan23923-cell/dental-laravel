import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/pdf/pdf_letterhead.dart';
import '../../../clinic_settings/domain/clinic_settings.dart';

/// The payments activity log as a PDF (2026-11-04, by request), the web
/// `print/payments-activity.blade.php`: who added, changed or deleted which
/// payment and when, for the list's date range. Rows come raw from
/// `GET /api/payments/activity`.
Future<Uint8List> buildPaymentsActivityPdf({
  required List<Map<String, dynamic>> rows,
  required ClinicSettings? settings,
  String? currency,
  String? from,
  String? to,
  PdfPageFormat format = PdfPageFormat.a4,
  pw.ImageProvider? logo,
}) async {
  final letterhead = await PdfLetterhead.load();
  final doc = pw.Document(theme: letterhead.theme);
  final money = NumberFormat('#,##0.##', 'en_US');
  String amount(Object? v) {
    final n = v == null ? null : double.tryParse('$v');
    return n == null ? '—' : money.format(n);
  }

  const actions = {'create': 'إضافة', 'update': 'تعديل', 'delete': 'حذف'};
  const actionColors = {'create': PdfColors.green700, 'update': PdfColors.amber800, 'delete': PdfColors.red700};
  const sources = {'registration': 'تسجيل مريض', 'lab': 'أجور المختبر', 'appointment': 'موعد'};
  const roles = {
    'super_admin': 'مدير عام',
    'admin': 'مدير',
    'editor': 'محرر',
    'accountant': 'محاسب',
    'senior': 'مسؤول قسم',
    'hr': 'موارد بشرية',
    'reception': 'موظف التذاكر',
    'lab': 'مختبر',
    'doctor': 'طبيب',
    'teacher': 'تدريسي',
  };
  const fields = {'amount': 'المبلغ', 'full_amount': 'السعر قبل التخفيض', 'paid_by': 'الدافع', 'paid_at': 'تاريخ الدفع', 'type': 'النوع'};

  final range = [if (from != null) 'من $from', if (to != null) 'إلى $to'].join(' ');
  final title = ['سجل حركات المدفوعات', if (range.isNotEmpty) range].join(' ');
  final counts = <String, int>{};
  for (final r in rows) {
    final a = '${r['action']}';
    counts[a] = (counts[a] ?? 0) + 1;
  }

  pw.TextStyle reg(double size, [PdfColor? color]) => pw.TextStyle(font: letterhead.regular, fontSize: size, color: color);
  pw.TextStyle bold(double size, [PdfColor? color]) => pw.TextStyle(font: letterhead.bold, fontSize: size, color: color);
  pw.Widget cell(pw.Widget child) => pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3), child: child);
  pw.Widget text(String s, {pw.TextStyle? style}) => cell(pw.Text(s, style: style ?? reg(8)));

  List<String> details(Map<String, dynamic> r) {
    final s = (r['snapshot'] as Map?)?.cast<String, dynamic>() ?? const {};
    final out = <String>[];
    final full = double.tryParse('${s['full_amount'] ?? ''}');
    final paid = double.tryParse('${s['amount'] ?? ''}');
    if (full != null && paid != null && full > paid) out.add('السعر وقتها: ${amount(full)} (بعد التخفيض ${amount(paid)})');
    if ((s['paid_by'] ?? '').toString().isNotEmpty) out.add('الدافع: ${s['paid_by']}');
    if ((s['paid_at'] ?? '').toString().isNotEmpty) out.add('تاريخ الدفع: ${s['paid_at']}');
    final changes = r['changes'];
    final before = (r['before'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (r['action'] == 'update' && changes is Map) {
      changes.forEach((field, value) {
        if (!fields.containsKey(field)) return;
        out.add('${fields[field]}: ${before[field] ?? '—'} ← ${value ?? '—'}');
      });
    }
    if (s.isEmpty) out.add('لا توجد تفاصيل محفوظة لهذه الحركة');
    return out;
  }

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: format.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => context.pageNumber == 1
          ? letterhead.build(title: title, settings: settings, logo: logo)
          : pw.SizedBox.shrink(),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}', style: reg(8, PdfColors.grey600)),
      ),
      build: (context) => [
        pw.Text(
          [
            'عدد الحركات: ${rows.length}',
            for (final e in actions.entries) '${e.value}: ${counts[e.key] ?? 0}',
          ].join('    '),
          style: bold(10),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(1.5),
            2: pw.FlexColumnWidth(0.8),
            3: pw.FlexColumnWidth(0.8),
            4: pw.FlexColumnWidth(1.8),
            5: pw.FlexColumnWidth(1.1),
            6: pw.FlexColumnWidth(1.1),
            7: pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                for (final h in ['الوقت', 'المستخدم', 'الحركة', 'رقم الدفعة', 'المريض', 'المصدر', 'المبلغ (${currency ?? ''})', 'التفاصيل'])
                  text(h, style: bold(8)),
              ],
            ),
            if (rows.isEmpty)
              pw.TableRow(children: [
                text('لا توجد حركات في هذه الفترة.'),
                for (var i = 0; i < 7; i++) text(''),
              ]),
            for (final r in rows)
              () {
                final s = (r['snapshot'] as Map?)?.cast<String, dynamic>() ?? const {};
                final action = '${r['action']}';
                return pw.TableRow(children: [
                  text('${r['at'] ?? '—'}'),
                  cell(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('${r['user'] ?? '—'}', style: reg(8)),
                    pw.Text(roles[r['role']] ?? '${r['role'] ?? ''}', style: reg(7, PdfColors.grey600)),
                  ])),
                  text(actions[action] ?? action, style: bold(8, actionColors[action])),
                  text('#${r['payment_id'] ?? ''}'),
                  text('${s['patient'] ?? '—'}'),
                  text(sources[s['source']] ?? '${s['source'] ?? '—'}'),
                  text(amount(s['amount'])),
                  cell(pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [for (final d in details(r)) pw.Text(d, style: reg(7))],
                  )),
                ]);
              }(),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
