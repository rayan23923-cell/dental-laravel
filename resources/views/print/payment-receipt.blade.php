@extends('print.layout')

@php
    $isLab = $payment->type === \App\Models\Payment::TYPE_LAB;
    $registration = $payment->patientRegistration;
    $amount = rtrim(rtrim(number_format((float) $payment->amount, 2, '.', ','), '0'), '.');
@endphp

@section('title', ($isLab ? 'وصل أجور المختبر' : 'وصل دفع') . ' — ' . ($registration?->name ?? $payment->appointment?->full_name ?? ''))

@section('back_url', route('payments.index'))

@section('content')
    {{-- Same box/sizes as print/patient-registration-ticket.blade.php. --}}
    <style>
        .letterhead img { width: 100%; max-width: 420px; height: auto; }
        .receipt table { font-size: 19px; }
        .receipt th, .receipt td { padding: 10px 12px; }
    </style>
    <div class="receipt" style="max-width:420px; margin:24px auto; border:1px solid #9ca3af; border-radius:8px; padding:20px;">
        <h3 style="text-align:center; margin:0 0 12px; font-size:22px;">{{ $isLab ? 'وصل دفع أجور المختبر' : 'وصل دفع' }}</h3>

        <div style="text-align:center; font-size:24px; font-weight:700; padding:12px; border:2px solid #111827; border-radius:8px; margin-bottom:16px;">
            {{ $isLab ? 'تم دفع أجور المختبر' : 'تم الدفع' }}
        </div>

        <table style="margin:0">
            <tbody>
                <tr><th style="width:38%">رقم الوصل</th><td dir="ltr" style="text-align:left">#{{ $payment->id }}</td></tr>
                <tr><th>اسم المريض</th><td>{{ $registration?->name ?? $payment->appointment?->full_name ?? '—' }}</td></tr>
                @if ($registration)
                    <tr><th>الهاتف</th><td dir="ltr" style="text-align:left">{{ $registration->phone }}</td></tr>
                @endif
                <tr><th>المبلغ</th><td>{{ $amount }} {{ $settings->clinic_currency }}</td></tr>
                {{-- Student/employee discount (2026-10-25, by request). --}}
                @php($discountLine = \App\Support\StudentDiscount::printLine($registration, (float) $payment->amount, \App\Support\StudentDiscount::fullAmountFor($payment, $settings), (string) $settings->clinic_currency))
                @if ($discountLine)
                    <tr><th>التخفيض</th><td>{{ $discountLine }}</td></tr>
                @endif
                @if ($payment->paid_by)
                    <tr><th>الدافع</th><td>{{ $payment->paid_by }}</td></tr>
                @endif
                <tr><th>التاريخ</th><td dir="ltr" style="text-align:left">{{ $payment->paid_at?->format('Y-m-d H:i') ?? '—' }}</td></tr>
            </tbody>
        </table>
    </div>

    @if ($autoprint)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
@endsection
