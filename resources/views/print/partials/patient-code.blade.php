{{-- The patient's code under the QR (2026-11-04, by request): typed by
     the doctor when the camera can't be used. --}}
@if (filled($code ?? null))
    <p style="margin:4px 0 0; font-size:13px">رمز المريض للإدخال اليدوي</p>
    <p dir="ltr" style="margin:0; font-size:26px; font-weight:800; letter-spacing:4px; font-family:monospace">{{ $code }}</p>
@else
    <p class="muted" style="margin-top:4px">رمز المريض</p>
@endif
