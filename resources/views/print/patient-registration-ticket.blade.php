@extends('print.layout')

@section('title', 'تكت تسجيل — ' . $registration->name)

@section('back_url', route('patient-registrations.index'))

@section('content')
    {{-- Scoped to this ticket only — the shared table/font-size rules in
         print.layout.blade.php stay as-is for the doctor roster/card, which
         weren't asked to change; a bigger QR/text was specific to this
         desk-facing ticket. Same reasoning for the logo override below
         (2026-08-29, matching the Flutter thermal ticket's identical fix):
         the shared `.letterhead img { height: 80px }` stays untouched for
         everything else, this ticket alone spans the logo to match its own
         420px box width instead. --}}
    <style>
        .letterhead img { width: 100%; max-width: 420px; height: auto; }
        .reg-ticket table { font-size: 19px; }
        .reg-ticket th, .reg-ticket td { padding: 10px 12px; }
        .reg-ticket .muted { font-size: 16px; }

        /* 80mm thermal printer, same rules as print/lab-result.blade.php:
           roll-width page, black-and-white logo, no watermark or fills. */
        @media print {
            @page { size: 80mm auto; margin: 2mm; }
            .watermark { display: none !important; }
            .letterhead { border-bottom-width: 1px; margin-bottom: 8px; padding-bottom: 6px; }
            .letterhead img { max-width: 60%; filter: grayscale(100%) contrast(1.2); }
            .letterhead h1 { font-size: 18px; }
            .letterhead h2 { font-size: 15px; }
            .letterhead p, .muted { color: #000 !important; }
            .reg-ticket { max-width: none !important; margin: 0 !important; border: 0 !important; padding: 0 !important; color: #000; }
            .reg-ticket table { font-size: 15px; }
            .reg-ticket th, .reg-ticket td { padding: 5px 6px; border-color: #000; background: #fff !important; }
            .reg-ticket .qr { width: 200px !important; height: 200px !important; }
        }
    </style>
    <div class="reg-ticket" style="max-width:420px; margin:24px auto; border:1px solid #9ca3af; border-radius:8px; padding:20px;">
        <table style="margin:0 0 16px">
            <tbody>
                <tr><th style="width:38%">اسم المريض</th><td>{{ $registration->name }}</td></tr>
                <tr><th>الهاتف</th><td dir="ltr" style="text-align:left">{{ $registration->phone }}</td></tr>
                <tr><th>الخدمة</th><td>{{ $registration->service?->name ?? '—' }}</td></tr>
                {{-- Printed only after payment, which registration now
                     takes in full at the service's price (2026-10-12), so
                     this is the paid receipt. Older registrations without a
                     recorded payment fall back to the service's price. --}}
                @php($paid = (float) ($registration->service_paid ?: $registration->service?->price))
                @if ($paid > 0)
                    <tr><th>المبلغ المدفوع</th><td>{{ number_format($paid) }} {{ $settings->clinic_currency }}</td></tr>
                    {{-- Student/employee discount (2026-10-25, by request). --}}
                    @php($discountLine = \App\Support\StudentDiscount::printLine($registration, $paid, $registration->service?->price !== null ? (float) $registration->service->price : null, (string) $settings->clinic_currency))
                    @if ($discountLine)
                        <tr><th>التخفيض</th><td>{{ $discountLine }}</td></tr>
                    @endif
                    <tr><th>الحالة</th><td><strong>مدفوع</strong></td></tr>
                @endif
                @if ($registration->registerDay)
                    <tr><th>اليوم</th><td>{{ $registration->registerDay->name }}</td></tr>
                @endif
            </tbody>
        </table>

        <div style="text-align:center;">
            <img src="{{ route('patient-registrations.qr', $registration) }}" alt="رمز الدفع" class="qr" style="width:240px; height:240px;">
            <p class="muted" style="margin-top:4px">رمز المريض</p>
        </div>
    </div>

    @if ($autoprint ?? false)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
@endsection
