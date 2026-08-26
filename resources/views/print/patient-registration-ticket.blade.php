@extends('print.layout')

@section('title', 'تكت تسجيل — ' . $registration->name)

@section('back_url', route('patient-registrations.index'))

@section('content')
    {{-- Scoped to this ticket only — the shared table/font-size rules in
         print.layout.blade.php stay as-is for the doctor roster/card, which
         weren't asked to change; a bigger QR/text was specific to this
         desk-facing ticket. --}}
    <style>
        .reg-ticket table { font-size: 16px; }
        .reg-ticket th, .reg-ticket td { padding: 10px 12px; }
        .reg-ticket .muted { font-size: 15px; }
    </style>
    <div class="reg-ticket" style="max-width:420px; margin:24px auto; border:1px solid #9ca3af; border-radius:8px; padding:20px;">
        <table style="margin:0 0 16px">
            <tbody>
                <tr><th style="width:38%">اسم المريض</th><td>{{ $registration->name }}</td></tr>
                <tr><th>الهاتف</th><td dir="ltr" style="text-align:left">{{ $registration->phone }}</td></tr>
                <tr><th>الخدمة</th><td>{{ $registration->service?->name ?? '—' }}</td></tr>
                <tr><th>اليوم</th><td>{{ $registration->registerDay?->name ?? '—' }}</td></tr>
            </tbody>
        </table>

        <div style="text-align:center;">
            <img src="{{ route('patient-registrations.qr', $registration) }}" alt="رمز الدفع" style="width:240px; height:240px;">
            <p class="muted" style="margin-top:4px">يُمسح هذا الرمز عند الدفع</p>
        </div>
    </div>
@endsection
