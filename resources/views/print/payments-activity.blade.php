@extends('print.layout')

{{-- Payments activity log (2026-11-01, by request): every payment added,
     changed or deleted, by whom and when, for the chosen date range.
     Printed from the browser, whose print dialog also saves it as PDF. --}}

@php
    $money = fn ($v) => $v === null || $v === '' ? '—' : rtrim(rtrim(number_format((float) $v, 2, '.', ','), '0'), '.');
    $currency = $settings->clinic_currency;
    $actions = ['create' => 'إضافة', 'update' => 'تعديل', 'delete' => 'حذف'];
    $actionColors = ['create' => '#15803d', 'update' => '#b45309', 'delete' => '#b91c1c'];
    $sources = ['registration' => 'تسجيل مريض', 'lab' => 'أجور المختبر', 'appointment' => 'موعد'];
    $roles = ['super_admin' => 'مدير عام', 'admin' => 'مدير', 'editor' => 'محرر', 'accountant' => 'محاسب', 'senior' => 'مسؤول قسم', 'hr' => 'موارد بشرية', 'reception' => 'موظف التذاكر', 'lab' => 'مختبر', 'doctor' => 'طبيب', 'teacher' => 'تدريسي'];
    $fields = ['amount' => 'المبلغ', 'full_amount' => 'السعر قبل التخفيض', 'paid_by' => 'الدافع', 'paid_at' => 'تاريخ الدفع', 'type' => 'النوع'];
    $counts = collect($rows)->countBy('action');
    $range = trim(($from ? 'من ' . $from : '') . ' ' . ($to ? 'إلى ' . $to : ''));
    // The payments page's date range goes in the title (2026-11-01, by request).
    $title = trim('سجل حركات المدفوعات ' . $range);
@endphp

@section('title', $title)

@section('back_url', route('payments.index'))

@section('content')
    <style>
        .activity table { font-size: 13px; }
        .activity th, .activity td { padding: 6px 8px; vertical-align: top; }
        .activity .action { font-weight: 700; }
        .activity .muted { color: #6b7280; font-size: 12px; }
        .activity .summary span { display: inline-block; margin-left: 18px; }
        @media print { @page { size: A4 landscape; margin: 10mm; } }
    </style>
    <div class="activity">
        <h3 style="text-align:center; margin:0 0 6px;">{{ $title }}</h3>
        <p class="muted" style="text-align:center; margin:0 0 12px;">{{ $range === '' ? 'كل الفترات · ' : '' }}طُبع {{ now()->format('Y-m-d H:i') }}</p>

        <p class="summary" style="margin:0 0 12px;">
            <span>عدد الحركات: <strong>{{ count($rows) }}</strong></span>
            @foreach ($actions as $key => $label)
                <span>{{ $label }}: <strong>{{ $counts[$key] ?? 0 }}</strong></span>
            @endforeach
        </p>

        <table>
            <thead>
                <tr>
                    <th style="width:12%">الوقت</th>
                    <th style="width:13%">المستخدم</th>
                    <th style="width:7%">الحركة</th>
                    <th style="width:7%">رقم الدفعة</th>
                    <th style="width:17%">المريض</th>
                    <th style="width:10%">المصدر</th>
                    <th style="width:10%">المبلغ ({{ $currency }})</th>
                    <th>التفاصيل</th>
                </tr>
            </thead>
            <tbody>
                @forelse ($rows as $row)
                    @php($s = $row['snapshot'] ?? [])
                    <tr>
                        <td dir="ltr" style="text-align:right">{{ $row['at']?->format('Y-m-d H:i') }}</td>
                        <td>{{ $row['user'] }}<div class="muted">{{ $roles[$row['role']] ?? $row['role'] }}</div></td>
                        <td class="action" style="color:{{ $actionColors[$row['action']] ?? '#111' }}">{{ $actions[$row['action']] ?? $row['action'] }}</td>
                        <td>#{{ $row['payment_id'] }}</td>
                        <td>{{ $s['patient'] ?? '—' }}</td>
                        <td>{{ isset($s['source']) ? ($sources[$s['source']] ?? $s['source']) : '—' }}</td>
                        <td dir="ltr" style="text-align:right">{{ $money($s['amount'] ?? null) }}</td>
                        <td>
                            @if (! empty($s['full_amount']) && isset($s['amount']) && (float) $s['full_amount'] > (float) $s['amount'])
                                <div>السعر وقتها: {{ $money($s['full_amount']) }} (بعد التخفيض {{ $money($s['amount']) }})</div>
                            @endif
                            @if (! empty($s['paid_by']))
                                <div>الدافع: {{ $s['paid_by'] }}</div>
                            @endif
                            @if (! empty($s['paid_at']))
                                <div class="muted">تاريخ الدفع: {{ $s['paid_at'] }}</div>
                            @endif
                            @if ($row['action'] === 'update' && is_array($row['changes']))
                                @foreach ($row['changes'] as $field => $new)
                                    @continue(! isset($fields[$field]))
                                    <div>{{ $fields[$field] }}: {{ is_scalar($row['before'][$field] ?? null) ? $row['before'][$field] : '—' }} ← {{ is_scalar($new) ? $new : '—' }}</div>
                                @endforeach
                            @endif
                            @if (! $s)
                                <div class="muted">لا توجد تفاصيل محفوظة لهذه الحركة (قبل تفعيل السجل المفصّل)</div>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr><td colspan="8" style="text-align:center">لا توجد حركات في هذه الفترة.</td></tr>
                @endforelse
            </tbody>
        </table>
    </div>

    @if ($autoprint)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
@endsection
