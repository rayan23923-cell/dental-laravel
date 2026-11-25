@extends('print.layout')

{{-- Payments report (2026-10-12, by request): income for today / this week /
     this month / this year, the daily and monthly charts, totals by source
     and every payment matching the payments page's filters. Printed from
     the browser, whose print dialog also saves it as PDF. --}}

@php
    $money = fn ($v) => rtrim(rtrim(number_format((float) $v, 2, '.', ','), '0'), '.');
    $currency = $settings->clinic_currency;
    $sourceLabels = ['registration' => 'تسجيل مريض', 'lab' => 'أجور المختبر', 'appointment' => 'موعد'];
    // The lab's / the ticket desk's own report (2026-10-26, by request).
    $reportTitle = match ($scope ?? null) {
        ['lab'] => 'تقرير مدفوعات المختبر',
        ['registration'] => 'تقرير واردات التذاكر',
        default => 'تقرير المدفوعات',
    };
    // The date range of the payments page goes in the title (2026-11-01,
    // by request): "تقرير المدفوعات من ... إلى ...".
    $rangeText = trim(($filters['from'] ? 'من ' . $filters['from'] : '') . ' ' . ($filters['to'] ? 'إلى ' . $filters['to'] : ''));
    if ($rangeText !== '') {
        $reportTitle .= ' ' . $rangeText;
    }
    $periodLabels = ['today' => 'اليوم', 'week' => 'هذا الأسبوع', 'month' => 'هذا الشهر', 'year' => 'هذه السنة'];
    $filterBits = array_filter([
        $filters['source'] && count($scope ?? ['', '']) > 1 ? 'المصدر: ' . ($sourceLabels[$filters['source']] ?? $filters['source']) : null,
        $filters['search'] ? 'بحث: ' . $filters['search'] : null,
        // Link to case sheets, stage and department (2026-11-04).
        ! empty($filters['link']) ? 'الربط: ' . (['linked' => 'مربوط بنموذج', 'unlinked' => 'غير مربوط', 'suspicious' => 'محاولات مشبوهة', 'attempts' => 'محاولات مرفوضة'][$filters['link']] ?? $filters['link']) : null,
        ! empty($filters['stage_id']) ? 'المرحلة: ' . (\App\Models\Stage::withTrashed()->whereKey($filters['stage_id'])->value('name') ?? '') : null,
        ! empty($filters['department_id']) ? 'القسم: ' . (\App\Models\Department::withTrashed()->whereKey($filters['department_id'])->value('name') ?? '') : null,
    ]);
@endphp

@section('title', $reportTitle)

@section('back_url', route('payments.index'))

@section('letterhead')
    <h2 style="margin-top:8px">{{ $reportTitle }}</h2>
@endsection

@section('content')
    <style>
        .cards { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-bottom: 16px; }
        .card { border: 1px solid #9ca3af; border-radius: 6px; padding: 8px 10px; }
        .card .k { font-size: 12px; color: #4b5563; }
        .card .v { font-size: 18px; font-weight: 700; margin-top: 2px; }
        .card .n { font-size: 11px; color: #6b7280; }
        .charts { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 8px; }
        .chart h3 { font-size: 13px; margin: 0 0 4px; }
        .sources td, .sources th { font-size: 13px; }
        .report-table td, .report-table th { font-size: 12px; padding: 4px 6px; }
        /* Missing numbers in the payments' ids (2026-11-25, by request). */
        .report-table tr.gap td { background: #fff7ed; color: #9a3412; font-size: 11px; padding: 3px 6px; }
        .report-table tr.gap.outside td { background: #f9fafb; color: #4b5563; }
        @media print {
            @page { size: A4; margin: 10mm; }
            .chart, .card, tr { break-inside: avoid; page-break-inside: avoid; }
            /* No row split across two pages (2026-11-25, by request). Safari
               (every browser on iPhone/iPad) ignores break-inside on table
               rows, so in print each row of the payments table is its own
               block-level table with fixed column widths: blocks are never
               split, and the columns still line up. */
            .payments-table, .payments-table thead, .payments-table tbody, .payments-table tfoot { display: block; width: 100%; }
            .payments-table tr { display: table; width: 100%; table-layout: fixed; border-collapse: collapse; border-spacing: 0; }
            .payments-table tbody tr td, .payments-table tfoot tr th { border-top: 0; }
            .payments-table .w-n { width: 5%; }
            .payments-table .w-id { width: 6%; }
            .payments-table .w-who { width: 15%; }
            .payments-table .w-src { width: 10%; }
            .payments-table .w-svc { width: 11%; }
            .payments-table .w-amt { width: 8%; }
            .payments-table .w-disc { width: 12%; }
            .payments-table .w-net { width: 9%; }
            .payments-table .w-by { width: 10%; }
            .payments-table .w-at { width: 14%; }
            .payments-table .w-sum { width: 67%; }
            .payments-table .w-rest { width: 24%; }
            .payments-table td, .payments-table th { overflow-wrap: anywhere; }
        }
    </style>

    @if ($filterBits)
        <p class="muted" style="text-align:center; margin:0 0 12px">{{ implode(' · ', $filterBits) }}</p>
    @endif

    {{-- With a date filter (2026-11-04, by request) the cards and charts
         cover the filtered period only (PaymentStats::range()). --}}
    <div class="cards">
        @if ($range ?? null)
            <div class="card">
                <div class="k">مجموع الفترة</div>
                <div class="v">{{ $money($range['total']) }}</div>
                <div class="n">{{ $currency }} · {{ $range['count'] }} دفعة</div>
            </div>
            <div class="card">
                <div class="k">المعدل اليومي</div>
                <div class="v">{{ $money($range['average']) }}</div>
                <div class="n">{{ $currency }}</div>
            </div>
            <div class="card">
                <div class="k">أعلى يوم</div>
                <div class="v">{{ $range['best'] ? $money($range['best']['total']) : 'لا يوجد' }}</div>
                <div class="n" dir="ltr" style="text-align:right">{{ $range['best']['date'] ?? '—' }}</div>
            </div>
            <div class="card">
                <div class="k">أيام فيها دفعات</div>
                <div class="v">{{ $range['paid_days'] }}</div>
                <div class="n">من {{ $range['days'] }} يوم</div>
            </div>
        @else
            @foreach ($periodLabels as $key => $label)
                <div class="card">
                    <div class="k">{{ $label }}</div>
                    <div class="v">{{ $money($periods[$key]['total']) }}</div>
                    <div class="n">{{ $currency }} · {{ $periods[$key]['count'] }} دفعة</div>
                </div>
            @endforeach
        @endif
    </div>

    @php
        $dailyTitle = ($range ?? null) ? 'الوارد اليومي من ' . $range['from'] . ' إلى ' . $range['to'] : 'الوارد اليومي (آخر 30 يومًا)';
        $monthlyTitle = ($range ?? null) ? 'الوارد الشهري للفترة' : 'الوارد الشهري (هذه السنة)';
        $charts = array_filter([
            $daily !== [] ? ['title' => $dailyTitle, 'data' => $daily, 'short' => 'الوارد اليومي'] : null,
            $monthly !== [] ? ['title' => $monthlyTitle, 'data' => $monthly, 'short' => 'الوارد الشهري'] : null,
        ]);
    @endphp
    @if ($charts)
        <div class="charts" @if (count($charts) === 1) style="grid-template-columns: 1fr" @endif>
            @foreach ($charts as $chart)
                <div class="chart">
                    <h3><span dir="rtl">{{ $chart['title'] }}</span></h3>
                    @include('print.partials.bar-chart', ['data' => $chart['data'], 'title' => $chart['short']])
                </div>
            @endforeach
        </div>
    @endif

    <h3 class="section">{{ ($filterBits || ($range ?? null)) ? 'مجموع نتائج البحث' : 'مجموع كل المدفوعات' }}: {{ $money($filteredTotal) }} {{ $currency }}</h3>
    <table class="sources">
        <thead><tr><th>المصدر</th><th>عدد الدفعات</th><th>المبلغ</th></tr></thead>
        <tbody>
            @foreach ($bySource as $s)
                <tr><td>{{ $sourceLabels[$s['source']] }}</td><td>{{ $s['count'] }}</td><td>{{ $money($s['total']) }} {{ $currency }}</td></tr>
            @endforeach
        </tbody>
    </table>

    @if (! empty($byDepartment))
        {{-- By department: the department of the case sheet the patient was linked to (2026-11-04). --}}
        <h3 class="section">المدفوعات حسب الأقسام</h3>
        <table class="sources">
            <thead><tr><th>القسم</th><th>عدد الدفعات</th><th>المبلغ</th></tr></thead>
            <tbody>
                @foreach ($byDepartment as $d)
                    <tr><td>{{ $d['name'] }}</td><td>{{ $d['count'] }}</td><td>{{ $money($d['total']) }} {{ $currency }}</td></tr>
                @endforeach
            </tbody>
        </table>
    @endif

    @php
        $gapAfter = $gaps['after'] ?? [];
        // One line on a missing id: what it is and what is known of it.
        $gapText = function (array $g) use ($sourceLabels, $money) {
            $d = $g['details'];
            $bits = $d ? array_filter([
                $d['patient'] ?? null,
                isset($d['amount']) ? $money($d['amount']) : null,
                $d['paid_by'] ?? null,
                $d['paid_at'] ?? null,
            ]) : [];
            $src = $g['source'] ? ($sourceLabels[$g['source']] ?? $g['source']) : null;
            $what = match ($g['status']) {
                'outside' => 'ليست ضمن هذا التقرير' . ($src ? ' — ' . $src : ''),
                'deleted' => 'محذوفة' . ($g['by'] ? ' من ' . $g['by'] : '') . ($g['at'] ? ' بتاريخ ' . $g['at'] : '') . ($src ? ' — كانت ' . $src : ''),
                default => 'لا يوجد لها سجل (محذوفة قبل تفعيل سجل النشاط أو رقم لم يُستخدم)',
            };

            return $what . ($bits ? ' · ' . implode(' · ', $bits) : '');
        };
        $gapRow = fn (array $g) => '<tr class="gap ' . e($g['status']) . '"><td class="w-all" colspan="10">رقم ناقص <strong dir="ltr">' . e($g['id']) . '</strong>: ' . e($gapText($g)) . '</td></tr>';
    @endphp

    <h3 class="section">المدفوعات ({{ $payments->count() }})</h3>
    @if (($gaps['count'] ?? 0) > 0)
        {{-- Missing numbers (2026-11-25, by request): ids between the
             first and the last listed payment that this report doesn't list. --}}
        <p class="muted" style="margin:0 0 6px">
            أرقام ناقصة في التسلسل: {{ $gaps['count'] }}
            @if (! empty($gaps['counts']))
                ({{ implode('، ', array_filter([
                    isset($gaps['counts']['outside']) ? $gaps['counts']['outside'] . ' خارج هذا التقرير' : null,
                    isset($gaps['counts']['deleted']) ? $gaps['counts']['deleted'] . ' محذوفة' : null,
                    isset($gaps['counts']['unknown']) ? $gaps['counts']['unknown'] . ' بلا سجل' : null,
                ])) }})
            @endif
            @if ($gaps['truncated']) — أكثر من أن تُعرض هنا؛ ضيّق الفترة أو الفلتر لعرضها. @else — مبيّنة في الجدول بلون مختلف. @endif
        </p>
    @endif
    <table class="report-table payments-table">
        <thead>
            <tr><th class="w-n">ت</th><th class="w-id">#</th><th class="w-who">الشخص</th><th class="w-src">المصدر</th><th class="w-svc">الخدمة</th><th class="w-amt">المبلغ</th><th class="w-disc">التخفيض</th><th class="w-net">المبلغ بعد التخفيض</th><th class="w-by">الدافع</th><th class="w-at">التاريخ</th></tr>
        </thead>
        <tbody>
            @forelse ($payments as $i => $p)
                @php
                    $source = $p->type === \App\Models\Payment::TYPE_LAB ? 'lab' : ($p->appointment_id ? 'appointment' : 'registration');
                    // Student/employee discount (2026-10-25, by request): the
                    // amount, the discount and the amount after it.
                    $discount = $p->patient_registration_id
                        ? \App\Support\StudentDiscount::breakdown($p->patientRegistration, (float) $p->amount, \App\Support\StudentDiscount::fullAmountFor($p, $settings ?? null))
                        : null;
                @endphp
                <tr>
                    {{-- Serial number from 1 (2026-11-25, by request), beside the id. --}}
                    <td class="w-n" style="text-align:center">{{ $loop->iteration }}</td>
                    <td class="w-id" dir="ltr" style="text-align:left">{{ $p->id }}</td>
                    <td class="w-who">
                        {{ $p->patientRegistration?->name ?? $p->appointment?->full_name ?? '—' }}
                        @if ($p->patientRegistration?->trashed()) <span class="muted">(مؤرشف)</span> @endif
                    </td>
                    <td class="w-src">
                        {{ $sourceLabels[$source] }}
                        {{-- "غير سليم" diagnosis: B / C / HIV (2026-11-03, by request). --}}
                        @if ($source === 'lab' && $p->patientRegistration && ($diagnosis = \App\Support\ScreeningDiagnosis::text($p->patientRegistration)))
                            <div class="muted">غير سليم — {{ $diagnosis }}</div>
                        @endif
                    </td>
                    <td class="w-svc">{{ $p->patientRegistration?->serviceLabel() ?? '—' }}</td>
                    <td class="w-amt">{{ $money($discount['full'] ?? $p->amount) }}</td>
                    <td class="w-disc">{{ $discount ? trim(($discount['percent'] !== null ? $discount['percent'].'% · ' : '').$discount['who']) : '—' }}</td>
                    <td class="w-net"><strong>{{ $money($p->amount) }}</strong></td>
                    <td class="w-by">{{ $p->paid_by ?? '—' }}</td>
                    <td class="w-at" dir="ltr" style="text-align:left">{{ $p->paid_at?->setTimezone(\App\Support\PaymentStats::TIMEZONE)->format('Y-m-d H:i') ?? '—' }}</td>
                </tr>
                @foreach ($gapAfter[$i] ?? [] as $g)
                    {!! $gapRow($g) !!}
                @endforeach
            @empty
                <tr><td colspan="10" style="text-align:center">لا توجد مدفوعات.</td></tr>
            @endforelse
        </tbody>
        @if ($payments->count())
            <tfoot>
                <tr><th class="w-sum" colspan="7">المجموع</th><th class="w-net">{{ $money($filteredTotal) }} {{ $currency }}</th><th class="w-rest" colspan="2"></th></tr>
            </tfoot>
        @endif
    </table>

    {{-- Last page (2026-11-01, by request): the patients treated free with a
         care code (not in the totals above) and the student/employee
         discount's beneficiaries. --}}
    @if (($supported ?? []) !== [] || ($discounted ?? []) !== [])
        <div style="break-before: page; page-break-before: always;"></div>
        @if (($supported ?? []) !== [])
            @php($waivedTotal = array_sum(array_column($supported, 'waived_total')))
            <h3 class="section">المستفيدون من الرعاية ({{ count($supported) }})</h3>
            <p class="muted" style="margin:0 0 6px">بلا أجور عبر بطاقات الرعاية — غير محسوبة في مجموع المدفوعات.</p>
            <table class="report-table">
                <thead>
                    <tr><th>#</th><th>المريض</th><th>الهاتف</th><th>الخدمة</th><th>رمز الرعاية</th><th>أجور الخدمة</th><th>أجور المختبر</th><th>المجموع غير المستوفى</th><th>التاريخ</th></tr>
                </thead>
                <tbody>
                    @foreach ($supported as $i => $r)
                        <tr>
                            <td>{{ $i + 1 }}</td>
                            <td>{{ $r['name'] ?? '—' }}</td>
                            <td dir="ltr" style="text-align:left">{{ $r['phone'] ?? '—' }}</td>
                            <td>{{ $r['service'] ?? '—' }}</td>
                            <td dir="ltr" style="text-align:center">{{ $r['code'] }}</td>
                            <td>{{ $r['waived_service'] !== null ? $money($r['waived_service']) : '—' }}</td>
                            <td>{{ $r['waived_lab'] !== null ? $money($r['waived_lab']) : '—' }}</td>
                            <td><strong>{{ $money($r['waived_total']) }}</strong></td>
                            <td dir="ltr" style="text-align:left">{{ $r['used_at'] }}</td>
                        </tr>
                    @endforeach
                </tbody>
                <tfoot>
                    <tr><th colspan="7">المجموع</th><th>{{ $money($waivedTotal) }} {{ $currency }}</th><th></th></tr>
                </tfoot>
            </table>
        @endif

        @if (($discounted ?? []) !== [])
            @php($savedTotal = array_sum(array_map(fn ($r) => (float) ($r['saved'] ?? 0), $discounted)))
            <h3 class="section">المشمولون بالتخفيض ({{ count($discounted) }})</h3>
            <table class="report-table">
                <thead>
                    <tr><th>#</th><th>المريض</th><th>المشمول</th><th>المصدر</th><th>المبلغ</th><th>التخفيض</th><th>المبلغ بعد التخفيض</th><th>مقدار التخفيض</th><th>التاريخ</th></tr>
                </thead>
                <tbody>
                    @foreach ($discounted as $i => $r)
                        <tr>
                            <td>{{ $i + 1 }}</td>
                            <td>{{ $r['name'] }}</td>
                            <td>{{ $r['who'] }}</td>
                            <td>{{ $sourceLabels[$r['source']] }}</td>
                            <td>{{ $r['full'] !== null ? $money($r['full']) : '—' }}</td>
                            <td>{{ $r['percent'] !== null ? $r['percent'].'%' : '—' }}</td>
                            <td><strong>{{ $money($r['paid']) }}</strong></td>
                            <td>{{ $r['saved'] !== null ? $money($r['saved']) : '—' }}</td>
                            <td dir="ltr" style="text-align:left">{{ $r['paid_at'] }}</td>
                        </tr>
                    @endforeach
                </tbody>
                <tfoot>
                    <tr><th colspan="7">مجموع التخفيض</th><th>{{ $money($savedTotal) }} {{ $currency }}</th><th></th></tr>
                </tfoot>
            </table>
        @endif
    @endif

    @if ($autoprint)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
@endsection
