@extends('print.layout')

@section('title', 'نتيجة فحص المختبر — ' . $registration->name)

@section('back_url', route('lab.index'))

@section('content')
    @php
        $result = match ($registration->screening_status) {
            'clear' => ['label' => 'سليم', 'color' => '#15803d', 'bg' => '#dcfce7'],
            'flagged' => ['label' => 'غير سليم', 'color' => '#b91c1c', 'bg' => '#fee2e2'],
            default => ['label' => 'بانتظار الفحص', 'color' => '#b45309', 'bg' => '#fef3c7'],
        };
    @endphp
    {{-- Same box/sizes as print/patient-registration-ticket.blade.php so it
         prints the same way on the desk printers. --}}
    <style>
        .letterhead img { width: 100%; max-width: 420px; height: auto; }
        .lab-slip table { font-size: 19px; }
        .lab-slip th, .lab-slip td { padding: 10px 12px; }
        .lab-slip .muted { font-size: 16px; }
    </style>
    <div class="lab-slip" style="max-width:420px; margin:24px auto; border:1px solid #9ca3af; border-radius:8px; padding:20px;">
        <h3 style="text-align:center; margin:0 0 12px; font-size:22px;">نتيجة فحص المختبر</h3>

        <div style="text-align:center; font-size:28px; font-weight:700; padding:14px; border-radius:8px; margin-bottom:16px; color:{{ $result['color'] }}; background:{{ $result['bg'] }}; border:2px solid {{ $result['color'] }};">
            {{ $result['label'] }}
        </div>

        <table style="margin:0 0 16px">
            <tbody>
                <tr><th style="width:38%">اسم المريض</th><td>{{ $registration->name }}</td></tr>
                <tr><th>الهاتف</th><td dir="ltr" style="text-align:left">{{ $registration->phone }}</td></tr>
                <tr><th>الخدمة</th><td>{{ $registration->service?->name ?? '—' }}</td></tr>
                @if ($registration->registerDay)
                    <tr><th>اليوم</th><td>{{ $registration->registerDay->name }}</td></tr>
                @endif
                @if ($registration->screeningReusedFrom)
                    <tr><th>أجور المختبر</th><td>معفى — فحص سابق صالح</td></tr>
                    <tr><th>تاريخ الفحص السابق</th><td dir="ltr" style="text-align:left">{{ \Illuminate\Support\Carbon::parse($registration->screeningReusedFrom->screening_checked_at)->format('Y-m-d') }}</td></tr>
                @else
                    <tr><th>أجور المختبر</th><td>{{ $registration->lab_paid ? 'مدفوعة' : 'غير مدفوعة' }}</td></tr>
                @endif
                <tr><th>تاريخ الفحص</th><td dir="ltr" style="text-align:left">{{ $registration->screening_checked_at ? \Illuminate\Support\Carbon::parse($registration->screening_checked_at)->format('Y-m-d H:i') : '—' }}</td></tr>
                <tr><th>الفاحص</th><td>{{ $registration->screeningCheckedBy?->full_name ?? '—' }}</td></tr>
            </tbody>
        </table>

        <div style="text-align:center;">
            <img src="{{ $qrDataUri }}" alt="رمز المريض" style="width:240px; height:240px;">
            <p class="muted" style="margin-top:4px">رمز المريض</p>
        </div>
    </div>

    @if ($autoprint)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
@endsection
