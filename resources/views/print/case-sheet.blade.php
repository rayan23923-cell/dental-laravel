{{--
    Printable case sheet — a faithful port of the design shared by the
    original's doctor/*_print_html.php pages.

    Deliberately NOT built on print/layout.blade.php: that shell is the RTL
    Arabic roster design used by print_doctors.php. The case sheets use a
    different document entirely — LTR, A4, ~9pt, black hairline borders,
    grey section bars, two corner logos — and mixing the two would make both
    wrong. Every rule below is copied from the original's own <style> block
    (surgery_print_html.php is the reference; the other eight repeat it with
    minor drift, which is normalised here on purpose).
--}}
<!DOCTYPE html>
<html lang="en" dir="ltr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ $title }} - Print</title>
    <style>
        @page {
            size: A4;
            margin: 10mm;
        }

        body {
            font-family: "DejaVu Sans", Arial, sans-serif;
            font-size: 9pt;
            line-height: 1.3;
            color: #000;
            background: #fff;
            margin: 0;
        }

        .no-print { display: block; }

        @media print {
            .no-print { display: none !important; }
            body { background: #fff; }
            /* The grey section bars and table headings are the document's
               structure, not decoration — browsers drop backgrounds when
               printing unless this is forced. */
            * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        }

        .print-controls {
            text-align: center;
            padding: 20px;
            background: #f8f9fa;
            margin-bottom: 20px;
            border-bottom: 2px solid #dee2e6;
            position: sticky;
            top: 0;
            z-index: 1000;
        }

        .print-controls button {
            padding: 12px 24px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            color: #fff;
            border: none;
            border-radius: 6px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, .2);
            transition: all .3s;
        }

        .print-controls .btn-print { background: #007bff; }
        .print-controls .btn-back { background: #6c757d; margin-left: 10px; }
        .print-controls button:hover { transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0, 0, 0, .3); }
        .print-controls button:active { transform: translateY(0); }

        .sheet {
            width: 100%;
            max-width: 210mm;
            margin: 0 auto;
        }

        .header {
            text-align: center;
            font-weight: bold;
            font-size: 13pt;
            line-height: 1.4;
            margin-bottom: 6px;
            position: relative;
            min-height: 80px;
        }

        .header-logo { max-width: 80px; max-height: 80px; position: absolute; top: 0; display: block; }
        .header-logo-left { left: 0; }
        .header-logo-right { right: 0; }
        .header-content { text-align: center; }

        .sub-header { text-align: center; font-size: 10pt; margin-bottom: 10px; }

        .section-title {
            font-weight: bold;
            font-size: 10pt;
            background-color: #f0f0f0;
            padding: 4px 6px;
            border: 1px solid #000;
            margin-top: 6px;
            /* A section heading stranded at the foot of a page is the most
               common defect in the original's printouts. */
            page-break-after: avoid;
        }

        .table-bordered {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 4px;
        }

        .table-bordered td, .table-bordered th {
            border: 1px solid #000;
            padding: 3px 4px;
            vertical-align: top;
        }

        .table-heading th {
            background-color: #eaeaea;
            font-weight: bold;
            text-align: center;
        }

        .mini { font-size: 8pt; }
        .text-bold { font-weight: bold; }

        /* A field cell: bold label then its value, as every original page
           renders it (`<span class="text-bold">Label:</span> value`). */
        .field-label { font-weight: bold; }
        .field-value { }
        .field-empty { color: #000; }

        .notes-box {
            border: 1px solid #000;
            padding: 4px;
            min-height: 40px;
            margin-bottom: 4px;
            white-space: pre-wrap;
        }

        .teeth-list { font-weight: bold; letter-spacing: .5px; }

        /* Per-tooth measurement grid (BOP/PPD/CAL). One column per tooth,
           three sites per surface — the layout of the original's chart. */
        .perio-table {
            width: 100%;
            border-collapse: collapse;
            table-layout: fixed;
            margin-bottom: 6px;
        }

        .perio-table th, .perio-table td {
            border: 1px solid #000;
            padding: 1px;
            text-align: center;
            font-size: 6.5pt;
            line-height: 1.1;
        }

        .perio-table th { background-color: #eaeaea; font-weight: bold; }
        .perio-table .surface-label { width: 46px; font-weight: bold; text-align: left; padding-left: 3px; }
        .perio-table .site { width: 33.33%; display: inline-block; }
        .perio-arch-title { font-weight: bold; font-size: 8pt; margin: 4px 0 2px; }

        .footer-signature { margin-top: 8px; font-size: 9pt; }
        .footer-signature td { padding-top: 12px; }

        .qr-wrapper {
            margin-top: 28px;
            padding: 6px 12px;
            text-align: right;
            font-size: 8pt;
            font-style: italic;
            display: inline-block;
            float: right;
        }

        .qr-wrapper img {
            display: inline-block;
            width: 60px;
            height: 60px;
            margin-left: 8px;
            vertical-align: middle;
        }

        /* Keep a table's rows together with its heading where the page
           break would otherwise split a two-row block. */
        table, tr, td, th { page-break-inside: avoid; }
    </style>
</head>
<body>
    <div class="print-controls no-print">
        <button type="button" class="btn-print" onclick="window.print()">طباعة</button>
        <button type="button" class="btn-back" onclick="goBack()">رجوع</button>
    </div>

    <script>
        // Matches the original's goBack(): close the tab when the sheet was
        // opened with window.open, otherwise navigate back to the record.
        function goBack() {
            if (window.opener) {
                window.close();
            } else {
                window.location.href = @json($backUrl);
            }
        }
    </script>

    <div class="sheet">
        <div class="header">
            @if ($settings->logoUrl())
                <img src="{{ $settings->logoUrl() }}" alt="Clinic Logo" class="header-logo header-logo-left" onerror="this.style.display='none';">
            @endif

            @if ($settings->universityLogoUrl())
                <img src="{{ $settings->universityLogoUrl() }}" alt="University Logo" class="header-logo header-logo-right" onerror="this.style.display='none';">
            @endif

            <div class="header-content">
                {{ $settings->university_name ?: 'University of Baghdad' }}<br>
                {{ $settings->college_name ?: 'College of Dentistry' }}
                @if ($headerDepartment)
                    <br>{{ $headerDepartment }}
                @endif
            </div>
        </div>

        @if ($department)
            <div class="sub-header">{{ $department }}</div>
        @endif

        {{-- The identification strip every original print page opens with,
             above the specialty's own sections. --}}
        <table class="table-bordered mini">
            <tr>
                <td><span class="field-label">Student's Name:</span> {{ $doctorName ?? ($sheet->student_name ?? '') }}</td>
                <td><span class="field-label">Grade/Group:</span> {{ $sheet->grade_group ?? '' }}</td>
                <td><span class="field-label">Date:</span> {{ now()->format('Y-m-d') }}</td>
            </tr>
        </table>

        @foreach ($sections as $section)
            <div class="section-title">{{ $section['title'] }}</div>

            {{-- Narratives and tooth selections take a full row; short
                 fields pack two per row, as the original does. --}}
            <table class="table-bordered mini">
                @foreach ($section['rows'] as $row)
                    <tr>
                        @foreach ($row as $cell)
                            <td colspan="{{ $cell['span'] }}">
                                <span class="field-label">{{ $cell['label'] }}:</span>
                                @if ($cell['block'])
                                    <div class="notes-box">{{ $cell['value'] }}</div>
                                @elseif ($cell['teeth'])
                                    <span class="teeth-list">{{ $cell['value'] }}</span>
                                @else
                                    <span class="field-value">{{ $cell['value'] }}</span>
                                @endif
                            </td>
                        @endforeach
                    </tr>
                @endforeach
            </table>
        @endforeach

        @foreach ($charts as $group)
            <div class="section-title">{{ $group['title'] }}</div>

            @foreach ($group['tables'] as $table)
                @foreach ($table['arches'] as $arch)
                    <div class="perio-arch-title">{{ $table['label'] }} — {{ $arch['name'] }}</div>
                    <table class="perio-table">
                        <tr>
                            <th class="surface-label">Tooth</th>
                            @foreach ($arch['teeth'] as $tooth)
                                <th>{{ $tooth }}</th>
                            @endforeach
                        </tr>
                        <tr>
                            <td class="surface-label">Buccal</td>
                            @foreach ($arch['buccal'] as $sites)
                                <td>@foreach ($sites as $s)<span class="site">{{ $s !== '' ? $s : '·' }}</span>@endforeach</td>
                            @endforeach
                        </tr>
                        <tr>
                            <td class="surface-label">{{ $arch['innerLabel'] }}</td>
                            @foreach ($arch['lingual'] as $sites)
                                <td>@foreach ($sites as $s)<span class="site">{{ $s !== '' ? $s : '·' }}</span>@endforeach</td>
                            @endforeach
                        </tr>
                    </table>
                @endforeach
            @endforeach
        @endforeach

        @if (! empty($dentalChart))
            {{-- Odontogram, printed as a compact table of only the marked
                 teeth — see App\Support\CaseSheetPrintRenderer::dentalChart(). --}}
            <div class="section-title">المخطط السني</div>
            <table class="table-bordered mini">
                <tr class="table-heading">
                    <th style="width:8%">السن</th>
                    <th style="width:20%">الحالة</th>
                    <th>الأسطح</th>
                    <th style="width:22%">ملاحظات</th>
                </tr>
                @foreach ($dentalChart as $tooth)
                    <tr>
                        <td class="text-bold">{{ $tooth['number'] }}</td>
                        <td>{{ $tooth['status'] }}</td>
                        <td>{{ $tooth['surfaces'] ?: '—' }}</td>
                        <td>{{ $tooth['notes'] ?: '' }}</td>
                    </tr>
                @endforeach
            </table>
        @endif

        @if (! empty($stages))
            {{-- Per-stage signature/date/grade table, as printed by the
                 prosthodontics and complete-denture sheets. --}}
            <div class="section-title">Stages and evaluation</div>
            <table class="table-bordered mini">
                <tr class="table-heading">
                    <th>Stage</th>
                    <th>Signature of instructor</th>
                    <th>Date</th>
                    <th>Grade</th>
                </tr>
                @foreach ($stages as $stage)
                    <tr>
                        <td>
                            {{ $stage['label'] }}
                            @if ($stage['note'])
                                <div class="mini">{{ $stage['note'] }}</div>
                            @endif
                        </td>
                        <td>{{ $stage['signature'] }}</td>
                        <td>{{ $stage['date'] }}</td>
                        <td>{{ $stage['grade'] }}</td>
                    </tr>
                @endforeach
            </table>
        @endif

        <table class="table-bordered mini footer-signature">
            <tr>
                <td><span class="field-label">Supervisor:</span> _____________</td>
                <td><span class="field-label">Approval Date:</span> _____________</td>
                <td><span class="field-label">Staff Signature:</span> _____________</td>
            </tr>
        </table>

        @if ($qrDataUri)
            <div class="qr-wrapper">
                Scan the QR code to reopen this case sheet.
                <img src="{{ $qrDataUri }}" alt="QR Code">
            </div>
        @endif
    </div>
</body>
</html>
