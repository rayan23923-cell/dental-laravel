{{-- One doctor's card; shared by the single card and the cards printout
     ($compact: four to an A4 page, 2026-10-18 by request). --}}
@php($compact = $compact ?? false)
    <div style="{{ $compact
        ? 'height:100%; display:flex; flex-direction:column; border:2px solid #4f46e5; border-radius:10px; padding:10px 12px; font-size:13px;'
        : 'max-width:520px; margin:24px auto; border:2px solid #4f46e5; border-radius:12px; padding:24px;' }}">
        @if ($compact)
            <div style="text-align:center; font-size:13px; font-weight:600; color:#374151;">{{ $settings->university_name ?: $settings->clinic_name }}</div>
        @endif
        <h2 style="text-align:center; margin:{{ $compact ? '2px 0 8px' : '0 0 16px' }}; font-size:{{ $compact ? '16px' : '18px' }}; color:#4f46e5;">بطاقة تعريف الطبيب</h2>

        <div style="display:flex; gap:{{ $compact ? '8px' : '20px' }}; align-items:center;">
            @if ($doctor->profile_image)
                <img src="{{ \Illuminate\Support\Facades\Storage::disk('public')->url($doctor->profile_image) }}"
                     alt="" style="width:{{ $compact ? '70px' : '96px' }}; height:{{ $compact ? '70px' : '96px' }}; object-fit:cover; border-radius:8px; border:1px solid #d1d5db;">
            @endif
            <div style="flex:1">
                <table style="margin:0;{{ $compact ? ' font-size:13px;' : '' }}">
                    <tbody>
                        <tr><th style="width:38%;{{ $compact ? ' padding:5px 6px;' : '' }}">الاسم</th><td style="{{ $compact ? 'padding:5px 6px;' : '' }}">{{ $doctor->name }}</td></tr>
                        <tr><th style="{{ $compact ? 'padding:5px 6px;' : '' }}">اسم المستخدم</th><td style="{{ $compact ? 'padding:5px 6px;' : '' }}">{{ $doctor->username }}</td></tr>
                        <tr><th style="{{ $compact ? 'padding:5px 6px;' : '' }}">البريد الإلكتروني</th><td style="{{ $compact ? 'padding:5px 6px; word-break:break-all;' : '' }}">{{ $doctor->email }}</td></tr>
                        <tr><th style="{{ $compact ? 'padding:5px 6px;' : '' }}">رقم الهاتف</th><td style="{{ $compact ? 'padding:5px 6px;' : '' }}">{{ $doctor->phone ?: '-' }}</td></tr>
                        <tr><th style="{{ $compact ? 'padding:5px 6px;' : '' }}">نوع الدراسة</th><td style="{{ $compact ? 'padding:5px 6px;' : '' }}">{{ $doctor->educationType?->name ?? '-' }}</td></tr>
                        <tr><th style="{{ $compact ? 'padding:5px 6px;' : '' }}">المرحلة</th><td style="{{ $compact ? 'padding:5px 6px;' : '' }}">{{ $doctor->stage?->name ?? '-' }}</td></tr>
                        @if ($groupsEnabled)
                            <tr><th style="{{ $compact ? 'padding:5px 6px;' : '' }}">المجموعة</th><td style="{{ $compact ? 'padding:5px 6px;' : '' }}">{{ $doctor->groups->pluck('name')->implode('، ') ?: '-' }}</td></tr>
                        @endif
                    </tbody>
                </table>
            </div>
        </div>

        <div style="text-align:center; margin-top:{{ $compact ? 'auto' : '20px' }}; padding-top:{{ $compact ? '6px' : '0' }};">
            <img src="{{ $qr }}" alt="QR" style="width:{{ $compact ? '120px' : '140px' }}; height:{{ $compact ? '120px' : '140px' }};">
        </div>

        <div class="signatures" style="margin-top:{{ $compact ? '10px' : '24px' }};{{ $compact ? ' font-size:13px;' : '' }}">
            <div class="signature" style="{{ $compact ? 'min-width:90px;' : '' }}">توقيع الطبيب</div>
            <div class="signature" style="{{ $compact ? 'min-width:90px;' : '' }}">ختم الكلية</div>
        </div>
    </div>
