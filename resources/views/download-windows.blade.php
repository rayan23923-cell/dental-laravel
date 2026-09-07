<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>تحميل تطبيق سطح المكتب — {{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }}</title>
    <style>
        body {
            font-family: -apple-system, "Segoe UI", Tahoma, Arial, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            margin: 0;
            padding: 3rem 1.25rem 4rem;
            line-height: 1.9;
        }
        .wrap { max-width: 640px; margin: 0 auto; text-align: center; }
        .logo { width: 96px; height: 96px; border-radius: 50%; object-fit: cover; margin-bottom: 1.25rem; }
        h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
        .sub { color: #94a3b8; margin-bottom: 2.5rem; font-size: .95rem; }
        .download-btn {
            display: inline-flex;
            align-items: center;
            gap: .6rem;
            background: #38bdf8;
            color: #0f172a;
            font-weight: 700;
            font-size: 1.05rem;
            text-decoration: none;
            padding: .9rem 2.2rem;
            border-radius: .75rem;
            transition: background .15s;
        }
        .download-btn:hover { background: #7dd3fc; }
        .meta { color: #64748b; font-size: .85rem; margin-top: .9rem; }
        .card {
            text-align: start;
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: .75rem;
            padding: 1.5rem 1.75rem;
            margin-top: 3rem;
        }
        .card h2 { font-size: 1rem; color: #38bdf8; margin: 0 0 1rem; }
        .card ol { padding-inline-start: 1.4rem; margin: 0; }
        .card li { color: #cbd5e1; margin-bottom: .6rem; }
        .card li:last-child { margin-bottom: 0; }
    </style>
</head>
<body>
<div class="wrap">
    @if($clinic->logoUrl())
        <img src="{{ $clinic->logoUrl() }}" alt="" class="logo">
    @endif
    <h1>تطبيق سطح المكتب لويندوز</h1>
    <p class="sub">{{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }} — {{ $clinic->college_name ?: 'كلية طب الأسنان' }}</p>

    <a href="{{ $release['url'] }}" class="download-btn">
        ⬇ تحميل للويندوز
    </a>
    <p class="meta">
        الإصدار {{ $release['version'] }} · ويندوز 8 فأحدث (64-bit)
    </p>

    <div class="card">
        <h2>خطوات التثبيت</h2>
        <ol>
            <li>افتح الملف بعد التحميل (<code>DentalClinicSetup-{{ $release['version'] }}.exe</code>).</li>
            <li>إذا ظهرت رسالة "Windows protected your PC" (SmartScreen)، اضغط <strong>More info</strong> ثم <strong>Run anyway</strong> — طبيعي لأن التطبيق غير موقّع بشهادة تجارية بعد.</li>
            <li>أكمل خطوات التثبيت (Next → Install → Finish).</li>
            <li>بعد أول تشغيل، التطبيق يتحقق من التحديثات تلقائيًا ويحدّث نفسه بصمت عند توفر إصدار جديد — لا حاجة لزيارة هذه الصفحة مرة أخرى.</li>
        </ol>
    </div>
</div>
</body>
</html>
