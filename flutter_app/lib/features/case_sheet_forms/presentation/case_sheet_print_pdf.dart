import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_letterhead.dart';
import '../../clinic_settings/domain/clinic_settings.dart';

/// Builds a printable case-sheet PDF from
/// `Api\CaseSheetPrintController::show()`'s JSON — the *rendered document
/// model* that controller's own docblock describes (letterhead fields,
/// sections already resolved to label/value cells, chart grids, stage
/// rows), walked here the same way
/// `resources/views/print/case-sheet.blade.php` walks it for the web
/// printout, so both surfaces print the same document from the same
/// source of truth rather than two independently-drifting layouts. Same
/// structure/order as that Blade view: letterhead, identification strip,
/// sections, perio chart grids, odontogram, stages, footer signature
/// strip, QR back-link.
Future<Uint8List> buildCaseSheetPrintPdf({
  required Map<String, dynamic> doc,
  required ClinicSettings? settings,
  pw.ImageProvider? logo,
  pw.ImageProvider? qr,
}) async {
  final letterhead = await PdfLetterhead.load();
  final pdfDoc = pw.Document(theme: letterhead.theme);

  final header = (doc['header'] as Map<String, dynamic>?) ?? const {};
  final sections = (doc['sections'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  final charts = (doc['charts'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  final dentalChart = (doc['dental_chart'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  final stages = (doc['stages'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  final department = header['department'] as String?;
  final headerDepartment = header['header_department'] as String?;
  final title = (doc['title'] as String?) ?? '';
  final doctorName = doc['doctor_name'] as String?;
  final studentName = doctorName ?? (doc['student_name'] as String?) ?? '';
  final gradeGroup = (doc['grade_group'] as String?) ?? '';
  final printedAt = (doc['printed_at'] as String?) ?? '';

  pdfDoc.addPage(
    pw.MultiPage(
      // The sheet's own content is English, matching the web printout's
      // `dir="ltr"` — only this app's chrome (buttons, snack bars) is
      // Arabic, not the document itself.
      textDirection: pw.TextDirection.ltr,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => context.pageNumber == 1
          ? letterhead.build(
              title: title,
              settings: settings,
              subtitle: [
                if (department != null && department.isNotEmpty) department,
                if (headerDepartment != null && headerDepartment.isNotEmpty) headerDepartment,
              ].join(' · '),
              logo: logo,
            )
          : pw.SizedBox.shrink(),
      build: (context) => [
        _rowTable(letterhead, [
          {'label': "Student's Name", 'value': studentName},
          {'label': 'Grade/Group', 'value': gradeGroup},
          {'label': 'Date', 'value': printedAt},
        ]),
        for (final section in sections) _sectionBlock(letterhead, section),
        for (final chartGroup in charts) _chartBlock(letterhead, chartGroup),
        if (dentalChart.isNotEmpty) _dentalChartBlock(letterhead, dentalChart),
        if (stages.isNotEmpty) _stagesBlock(letterhead, stages),
        pw.SizedBox(height: 8),
        _rowTable(letterhead, [
          {'label': 'Supervisor', 'value': '_____________'},
          {'label': 'Approval Date', 'value': '_____________'},
          {'label': 'Staff Signature', 'value': '_____________'},
        ]),
        if (qr != null) _qrBlock(qr),
      ],
    ),
  );

  return pdfDoc.save();
}

pw.Widget _sectionTitle(PdfLetterhead lh, String title) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 6, bottom: 2),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: pw.BoxDecoration(color: PdfColors.grey200, border: pw.Border.all(color: PdfColors.black, width: 0.5)),
      child: pw.Text(title, style: pw.TextStyle(font: lh.bold, fontSize: 10)),
    );

/// One row of 1-3 label/value cells, each its own bordered `pw.Table` cell
/// — a fresh table per row (rather than one table for a whole section)
/// since rows in the same section can have a different cell count (a
/// full-width narrative row next to two-per-row short fields), and the
/// `pdf` package's `pw.Table` has no colspan to mix those in one table.
pw.Widget _rowTable(PdfLetterhead lh, List<Map<String, dynamic>> cells) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
    columnWidths: {for (var i = 0; i < cells.length; i++) i: const pw.FlexColumnWidth(1)},
    children: [pw.TableRow(children: [for (final cell in cells) _cellContent(lh, cell)])],
  );
}

pw.Widget _cellContent(PdfLetterhead lh, Map<String, dynamic> cell) {
  final label = (cell['label'] as String?) ?? '';
  final value = (cell['value'] as String?) ?? '';
  final isBlock = cell['block'] == true;
  final isTeeth = cell['teeth'] == true;

  if (isBlock) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(font: lh.bold, fontSize: 8)),
          pw.SizedBox(height: 2),
          pw.Container(
            width: double.infinity,
            constraints: const pw.BoxConstraints(minHeight: 30),
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.5)),
            child: pw.Text(value, style: pw.TextStyle(font: lh.regular, fontSize: 8)),
          ),
        ],
      ),
    );
  }

  return pw.Padding(
    padding: const pw.EdgeInsets.all(3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label: ', style: pw.TextStyle(font: lh.bold, fontSize: 8)),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(font: lh.regular, fontSize: 8, fontWeight: isTeeth ? pw.FontWeight.bold : null),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _sectionBlock(PdfLetterhead lh, Map<String, dynamic> section) {
  final rows = (section['rows'] as List<dynamic>? ?? const [])
      .map((row) => (row as List<dynamic>).cast<Map<String, dynamic>>())
      .toList();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle(lh, (section['title'] as String?) ?? ''),
      for (final row in rows) _rowTable(lh, row),
    ],
  );
}

/// Per-tooth measurement grid (periodontal BOP/PPD/CAL) — one column per
/// tooth (16 per arch, FDI order), three sites packed into each cell.
/// Mirrors `.perio-table` in the web printout exactly, including its very
/// small font (there's no way to fit 16 tooth columns on an A4 page
/// otherwise) and the `·` placeholder for an unmeasured site.
pw.Widget _chartBlock(PdfLetterhead lh, Map<String, dynamic> group) {
  final tables = (group['tables'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle(lh, (group['title'] as String?) ?? ''),
      for (final table in tables)
        for (final archJson in (table['arches'] as List<dynamic>? ?? const []))
          _archTable(lh, (table['label'] as String?) ?? '', archJson as Map<String, dynamic>),
    ],
  );
}

pw.Widget _archTable(PdfLetterhead lh, String tableLabel, Map<String, dynamic> arch) {
  final teeth = (arch['teeth'] as List<dynamic>? ?? const []).map((t) => t.toString()).toList();
  final buccal = (arch['buccal'] as List<dynamic>? ?? const []).cast<List<dynamic>>();
  final lingual = (arch['lingual'] as List<dynamic>? ?? const []).cast<List<dynamic>>();
  final name = (arch['name'] as String?) ?? '';
  final innerLabel = (arch['innerLabel'] as String?) ?? '';

  String sitesText(List<dynamic> sites) =>
      sites.map((s) => (s as String).isEmpty ? '·' : s).join(' ');

  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$tableLabel — $name', style: pw.TextStyle(font: lh.bold, fontSize: 8)),
        pw.SizedBox(height: 2),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            for (var i = 1; i <= teeth.length; i++) i: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _archCell('Tooth', lh.bold, header: true),
                for (final tooth in teeth) _archCell(tooth, lh.bold, header: true),
              ],
            ),
            pw.TableRow(children: [
              _archCell('Buccal', lh.bold),
              for (var i = 0; i < teeth.length; i++) _archCell(sitesText(i < buccal.length ? buccal[i] : const []), lh.regular),
            ]),
            pw.TableRow(children: [
              _archCell(innerLabel, lh.bold),
              for (var i = 0; i < teeth.length; i++) _archCell(sitesText(i < lingual.length ? lingual[i] : const []), lh.regular),
            ]),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _archCell(String text, pw.Font font, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(1.5),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: font, fontSize: 6.5),
      ),
    );

/// The odontogram, printed as a compact table of only the marked teeth —
/// see `App\Support\CaseSheetPrintRenderer::dentalChart()`'s doc comment
/// for why a text table stands in for a second SVG renderer here.
pw.Widget _dentalChartBlock(PdfLetterhead lh, List<Map<String, dynamic>> teeth) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle(lh, 'المخطط السني'),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(0.8),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(3),
          3: pw.FlexColumnWidth(2.2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (final h in ['السن', 'الحالة', 'الأسطح', 'ملاحظات'])
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(h, style: pw.TextStyle(font: lh.bold, fontSize: 8))),
            ],
          ),
          for (final tooth in teeth)
            pw.TableRow(children: [
              _cell('${tooth['number'] ?? ''}', lh.bold),
              _cell('${tooth['status'] ?? ''}', lh.regular),
              _cell(((tooth['surfaces'] as String?)?.isNotEmpty ?? false) ? tooth['surfaces'] as String : '—', lh.regular),
              _cell('${tooth['notes'] ?? ''}', lh.regular),
            ]),
        ],
      ),
    ],
  );
}

pw.Widget _stagesBlock(PdfLetterhead lh, List<Map<String, dynamic>> stages) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle(lh, 'Stages and evaluation'),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.2),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(1.2),
          3: pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (final h in ['Stage', 'Signature of instructor', 'Date', 'Grade'])
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(h, style: pw.TextStyle(font: lh.bold, fontSize: 8))),
            ],
          ),
          for (final stage in stages)
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${stage['label'] ?? ''}', style: pw.TextStyle(font: lh.regular, fontSize: 8)),
                    if ((stage['note'] as String?)?.isNotEmpty ?? false)
                      pw.Text(stage['note'] as String, style: pw.TextStyle(font: lh.regular, fontSize: 7, color: PdfColors.grey700)),
                  ],
                ),
              ),
              _cell('${stage['signature'] ?? ''}', lh.regular),
              _cell('${stage['date'] ?? ''}', lh.regular),
              _cell('${stage['grade'] ?? ''}', lh.regular),
            ]),
        ],
      ),
    ],
  );
}

pw.Widget _cell(String text, pw.Font font) =>
    pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8)));

/// The web printout's "Scan the QR code to reopen this case sheet." block
/// — only shown when the caller has a task-instance QR to embed (see
/// `case_sheet_form_screen.dart`'s print action), since a standalone
/// record with no task-instance linkage has no equivalent web QR either.
pw.Widget _qrBlock(pw.ImageProvider qr) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('Scan the QR code to reopen this case sheet.', style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(width: 8),
          pw.Image(qr, width: 50, height: 50),
        ],
      ),
    );
