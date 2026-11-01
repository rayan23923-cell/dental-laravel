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
        @media print {
            @page { size: A4; margin: 10mm; }
            .chart, .card, tr { break-inside: avoid; }
        }
    </style>

    @if ($filterBits)
        <p class="muted" style="text-align:center; margin:0 0 12px">{{ implode(' · ', $filterBits) }}</p>
    @endif

    <div class="cards">
        @foreach ($periodLabels as $key => $label)
            <div class="card">
                <div class="k">{{ $label }}</div>
                <div class="v">{{ $money($periods[$key]['total']) }}</div>
                <div class="n">{{ $currency }} · {{ $periods[$key]['count'] }} دفعة</div>
            </div>
        @endforeach
    </div>

    <div class="charts">
        <div class="chart">
            <h3>الوارد اليومي (آخر 30 يومًا)</h3>
            @include('print.partials.bar-chart', ['data' => $daily, 'title' => 'الوارد اليومي'])
        </div>
        <div class="chart">
            <h3>الوارد الشهري (هذه السنة)</h3>
            @include('print.partials.bar-chart', ['data' => $monthly, 'title' => 'الوارد الشهري'])
        </div>
    </div>

    <h3 class="section">{{ $filterBits ? 'مجموع نتائج البحث' : 'مجموع كل المدفوعات' }}: {{ $money($filteredTotal) }} {{ $currency }}</h3>
    <table class="sources">
        <thead><tr><th>المصدر</th><th>عدد الدفعات</th><th>المبلغ</th></tr></thead>
        <tbody>
            @foreach ($bySource as $s)
                <tr><td>{{ $sourceLabels[$s['source']] }}</td><td>{{ $s['count'] }}</td><td>{{ $money($s['total']) }} {{ $currency }}</td></tr>
            @endforeach
        </tbody>
    </table>

    <h3 class="section">المدفوعات ({{ $payments->count() }})</h3>
    <table class="report-table">
        <thead>
            <tr><th>#</th><th>الشخص</th><th>المصدر</th><th>الخدمة</th><th>المبلغ</th><th>التخفيض</th><th>المبلغ بعد التخفيض</th><th>الدافع</th><th>التاريخ</th></tr>
        </thead>
        <tbody>
            @forelse ($payments as $p)
                @php
                    $source = $p->type === \App\Models\Payment::TYPE_LAB ? 'lab' : ($p->appointment_id ? 'appointment' : 'registration');
                    // Student/employee discount (2026-10-25, by request): the
                    // amount, the discount and the amount after it.
                    $discount = $p->patient_registration_id
                        ? \App\Support\StudentDiscount::breakdown($p->patientRegistration, (float) $p->amount, \App\Support\StudentDiscount::fullAmountFor($p, $settings ?? null))
                        : null;
                @endphp
                <tr>
                    <td dir="ltr" style="text-align:left">{{ $p->id }}</td>
                    <td>
                        {{ $p->patientRegistration?->name ?? $p->appointment?->full_name ?? '—' }}
                        @if ($p->patientRegistration?->trashed()) <span class="muted">(مؤرشف)</span> @endif
                    </td>
                    <td>{{ $sourceLabels[$source] }}</td>
                    <td>{{ $p->patientRegistration?->service?->name ?? '—' }}</td>
                    <td>{{ $money($discount['full'] ?? $p->amount) }}</td>
                    <td>{{ $discount ? trim(($discount['percent'] !== null ? $discount['percent'].'% · ' : '').$discount['who']) : '—' }}</td>
                    <td><strong>{{ $money($p->amount) }}</strong></td>
                    <td>{{ $p->paid_by ?? '—' }}</td>
                    <td dir="ltr" style="text-align:left">{{ $p->paid_at?->setTimezone(\App\Support\PaymentStats::TIMEZONE)->format('Y-m-d H:i') ?? '—' }}</td>
                </tr>
            @empty
                <tr><td colspan="9" style="text-align:center">لا توجد مدفوعات.</td></tr>
            @endforelse
        </tbody>
        @if ($payments->count())
            <tfoot>
                <tr><th colspan="6">المجموع</th><th>{{ $money($filteredTotal) }} {{ $currency }}</th><th colspan="2"></th></tr>
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
