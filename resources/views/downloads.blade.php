<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>تحميل التطبيق — {{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }}</title>
    <style>
        body {
            font-family: -apple-system, "Segoe UI", Tahoma, Arial, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            margin: 0;
            padding: 3rem 1.25rem 4rem;
            line-height: 1.9;
        }
        .wrap { max-width: 720px; margin: 0 auto; text-align: center; }
        .logo { width: 96px; height: 96px; border-radius: 50%; object-fit: cover; margin-bottom: 1.25rem; }
        h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
        .sub { color: #94a3b8; margin-bottom: 2.5rem; font-size: .95rem; }
        .platforms {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 1.25rem;
            text-align: start;
        }
        @media (max-width: 760px) {
            .platforms { grid-template-columns: 1fr; }
        }
        .platform-card {
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: .75rem;
            padding: 1.5rem;
        }
        .platform-card h2 { font-size: 1.05rem; margin: 0 0 .35rem; display: flex; align-items: center; gap: .5rem; }
        .platform-card .platform-sub { color: #64748b; font-size: .8rem; margin-bottom: 1.1rem; }
        .download-btn {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: .5rem;
            background: #38bdf8;
            color: #0f172a;
            font-weight: 700;
            font-size: .95rem;
            text-decoration: none;
            padding: .75rem 1.25rem;
            border-radius: .6rem;
            transition: background .15s;
        }
        .download-btn:hover { background: #7dd3fc; }
        .meta { color: #64748b; font-size: .8rem; margin-top: .7rem; text-align: center; }
        .card {
            text-align: start;
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: .75rem;
            padding: 1.5rem 1.75rem;
            margin-top: 2rem;
        }
        .card h3 { font-size: .95rem; color: #38bdf8; margin: 0 0 1rem; }
        .card ol { padding-inline-start: 1.4rem; margin: 0; }
        .card li { color: #cbd5e1; margin-bottom: .6rem; font-size: .92rem; }
        .card li:last-child { margin-bottom: 0; }
    </style>
</head>
<body>
<div class="wrap">
    @if($clinic->logoUrl())
        <img src="{{ $clinic->logoUrl() }}" alt="" class="logo">
    @endif
    <h1>تحميل التطبيق</h1>
    <p class="sub">{{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }} — {{ $clinic->college_name ?: 'كلية طب الأسنان' }}</p>

    <div class="platforms">
        <div class="platform-card">
            <h2>🪟 ويندوز</h2>
            <p class="platform-sub">ويندوز 8 فأحدث (64-bit)</p>
            <a href="{{ $windows['zip_url'] }}" class="download-btn">⬇ تحميل للويندوز (ZIP)</a>
            <p class="meta">الإصدار {{ $windows['version'] }}</p>
        </div>
        <div class="platform-card">
            <h2>🤖 أندرويد</h2>
            <p class="platform-sub">أندرويد 8 فأحدث</p>
            <a href="{{ $android['zip_url'] }}" class="download-btn">⬇ تحميل للأندرويد (ZIP)</a>
            <p class="meta">الإصدار {{ $android['version'] }}</p>
        </div>
        <div class="platform-card">
            <h2>🍎 آيفون</h2>
            <p class="platform-sub">iOS 15.5 فأحدث</p>
            <a href="{{ $ios['url'] }}" class="download-btn">⬇ تحميل للآيفون (IPA)</a>
            <p class="meta">الإصدار {{ $ios['version'] }}</p>
        </div>
    </div>

    <div class="card">
        <h3 style="color:#fbbf24">⚠️ إذا التنزيل ما بدأ أو المتصفح ما رد أي شي</h3>
        <ol>
            <li>Chrome/Edge أحيانًا يحجبون تنزيل الملف بصمت (بدون رسالة واضحة) لأنه ملف جديد غير معروف السمعة. تحقق من أيقونة/شريط التنزيلات بأعلى المتصفح، أو افتح <code>chrome://downloads</code>.</li>
            <li>لو لقيت إدخال مكتوب عليه <strong>"Blocked"</strong> أو <strong>"Dangerous file blocked"</strong>، اضغط السهم ⌄ جنبه واختر <strong>"Keep"</strong> أو <strong>"Keep anyway"</strong>.</li>
            <li>حمّلنا الملفات بصيغة ZIP خصيصًا لتقليل احتمال هذا الحجب — لو استمرت المشكلة، جرّب متصفح ثاني (Firefox مثلاً) أو تواصل معنا.</li>
        </ol>
    </div>

    <div class="card">
        <h3>خطوات التثبيت — ويندوز</h3>
        <ol>
            <li>فك ضغط الملف بعد التحميل (<code>DentalClinicSetup-{{ $windows['version'] }}.zip</code>) — زر يمين ← Extract All، أو دبل كليك يفتحه مباشرة بويندوز 11.</li>
            <li>شغّل <code>DentalClinicSetup-{{ $windows['version'] }}.exe</code> من داخل المجلد المستخرج.</li>
            <li>إذا ظهرت رسالة "Windows protected your PC" (SmartScreen)، اضغط <strong>More info</strong> ثم <strong>Run anyway</strong> — طبيعي لأن التطبيق غير موقّع بشهادة تجارية بعد.</li>
            <li>أكمل خطوات التثبيت (Next → Install → Finish).</li>
            <li>بعد أول تشغيل، التطبيق يتحقق من التحديثات تلقائيًا ويحدّث نفسه بصمت عند توفر إصدار جديد — لا حاجة لزيارة هذه الصفحة مرة أخرى.</li>
        </ol>
    </div>

    <div class="card">
        <h3>خطوات التثبيت — أندرويد</h3>
        <ol>
            <li>فك ضغط الملف بعد التحميل (<code>DentalClinicApp-{{ $android['version'] }}.zip</code>) — بأي تطبيق مدير ملفات (Files by Google مدمج بمعظم أجهزة أندرويد).</li>
            <li>افتح ملف <code>DentalClinicApp-{{ $android['version'] }}.apk</code> الناتج.</li>
            <li>إذا ظهرت رسالة تحذير "قد يكون هذا التطبيق ضارًا" أو ما شابه، اسمح بالتثبيت من هذا المصدر (قد يطلب منك تفعيل "Install unknown apps" لتطبيق مدير الملفات) — طبيعي لأن التطبيق غير منشور على متجر Google Play بعد.</li>
            <li>اضغط تثبيت (Install) وانتظر انتهاء العملية.</li>
            <li>لتحديث التطبيق لاحقًا، نزّل أحدث نسخة من هذه الصفحة وثبّتها فوق النسخة الحالية (لا يوجد تحديث تلقائي على أندرويد بعد).</li>
        </ol>
    </div>

    <div class="card">
        <h3>خطوات التثبيت — آيفون</h3>
        <ol>
            <li>الملف غير موقّع من Apple، لذلك يُثبَّت من الكمبيوتر وليس من المتصفح مباشرة.</li>
            <li>نزّل <code>DentalClinicApp-{{ $ios['version'] }}.ipa</code> على الكمبيوتر، وثبّت برنامج <strong>Sideloadly</strong> أو <strong>AltStore</strong>.</li>
            <li>وصّل الآيفون بالكابل، اسحب ملف IPA إلى البرنامج وسجّل بحساب Apple ID الخاص بك ثم اضغط Start.</li>
            <li>على الآيفون: الإعدادات ← عام ← إدارة الأجهزة (VPN & Device Management) ← وثّق حسابك.</li>
            <li>مع حساب Apple ID مجاني يجب إعادة التثبيت أو التحديث كل 7 أيام. ميزة NFC غير متوفرة في هذه النسخة.</li>
        </ol>
    </div>
</div>
</body>
</html>
