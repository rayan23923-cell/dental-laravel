@extends('print.layout')

@section('title', 'بطاقة الطبيب — ' . $doctor->name)

@section('content')
    <div style="max-width:520px; margin:24px auto; border:2px solid #4f46e5; border-radius:12px; padding:24px;">
        <h2 style="text-align:center; margin:0 0 16px; font-size:18px; color:#4f46e5;">بطاقة تعريف الطبيب</h2>

        <div style="display:flex; gap:20px; align-items:center;">
            @if ($doctor->profile_image)
                <img src="{{ \Illuminate\Support\Facades\Storage::disk('public')->url($doctor->profile_image) }}"
                     alt="" style="width:96px; height:96px; object-fit:cover; border-radius:8px; border:1px solid #d1d5db;">
            @endif
            <div style="flex:1">
                <table style="margin:0">
                    <tbody>
                        <tr><th style="width:38%">الاسم</th><td>{{ $doctor->name }}</td></tr>
                        <tr><th>اسم المستخدم</th><td>{{ $doctor->username }}</td></tr>
                        <tr><th>البريد الإلكتروني</th><td>{{ $doctor->email }}</td></tr>
                        <tr><th>رقم الهاتف</th><td>{{ $doctor->phone ?: '-' }}</td></tr>
                        <tr><th>نوع الدراسة</th><td>{{ $doctor->educationType?->name ?? '-' }}</td></tr>
                        <tr><th>المرحلة</th><td>{{ $doctor->stage?->name ?? '-' }}</td></tr>
                        @if ($groupsEnabled)
                            <tr><th>المجموعة</th><td>{{ $doctor->groups->pluck('name')->implode('، ') ?: '-' }}</td></tr>
                        @endif
                    </tbody>
                </table>
            </div>
        </div>

        <div class="signatures" style="margin-top:32px">
            <div class="signature">توقيع الطبيب</div>
            <div class="signature">ختم الكلية</div>
        </div>
    </div>
@endsection
