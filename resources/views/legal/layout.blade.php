<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title') — {{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }}</title>
    <style>
        body {
            font-family: -apple-system, "Segoe UI", Tahoma, Arial, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            margin: 0;
            padding: 2rem 1.25rem 4rem;
            line-height: 1.9;
        }
        .wrap { max-width: 760px; margin: 0 auto; }
        h1 { font-size: 1.6rem; margin-bottom: .25rem; }
        .sub { color: #94a3b8; margin-bottom: 2.5rem; font-size: .95rem; }
        h2 { font-size: 1.15rem; margin-top: 2.25rem; color: #38bdf8; }
        p, li { color: #cbd5e1; }
        ul { padding-inline-start: 1.4rem; }
        a { color: #38bdf8; }
        .updated { color: #64748b; font-size: .85rem; margin-top: 3rem; border-top: 1px solid #1e293b; padding-top: 1rem; }
            nav.legal { margin-top: 1.25rem; display: flex; flex-wrap: wrap; gap: .5rem 1.25rem; font-size: .9rem; }
        form label { display: block; margin-top: 1rem; color: #cbd5e1; }
        form input, form textarea { width: 100%; box-sizing: border-box; margin-top: .35rem; padding: .7rem .8rem; border-radius: .6rem; border: 1px solid #334155; background: #1e293b; color: #e2e8f0; font: inherit; }
        form button { margin-top: 1.25rem; padding: .75rem 1.5rem; border: 0; border-radius: .6rem; background: #ef4444; color: #fff; font: inherit; font-weight: 600; cursor: pointer; }
        .notice { padding: 1rem 1.25rem; border-radius: .75rem; background: #064e3b; color: #d1fae5; }
        .error { color: #fca5a5; font-size: .9rem; }
    </style>
</head>
<body>
{{-- The public pages the app stores link to (2026-10-28): privacy, account
     deletion, support and terms share this frame and its footer links. --}}
<div class="wrap">
    <h1>@yield('title')</h1>
    <p class="sub">{{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }} — {{ $clinic->college_name ?: 'كلية طب الأسنان' }}@if($clinic->university_name)، {{ $clinic->university_name }}@endif</p>

    @yield('content')

    <div class="updated">
        <nav class="legal">
            <a href="{{ route('privacy-policy') }}">سياسة الخصوصية</a>
            <a href="{{ route('terms') }}">شروط الاستخدام</a>
            <a href="{{ route('support') }}">الدعم والتواصل</a>
            <a href="{{ route('account-deletion.show') }}">طلب حذف الحساب</a>
            <a href="/download">تحميل التطبيقات</a>
        </nav>
    </div>
</div>
</body>
</html>
