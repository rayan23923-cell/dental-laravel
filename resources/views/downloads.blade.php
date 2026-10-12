<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>تحميل التطبيق — {{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }}</title>
    <style>
        /*
            Instagram-inspired palette (2026-09-09, by request) — the same
            fixed "ig-*" tokens tailwind.config.js defines and
            GuestLayout.vue/WaitingScreen.vue already use for public pages,
            hand-copied here since this is a plain Blade view with no Vite
            bundle (see routes/web.php's own comment on /download: "a
            one-off content page needs no JS bundle" — same reasoning
            privacy-policy.blade.php follows). Keep these in sync with
            tailwind.config.js's `ig` colors if that palette ever changes.
        */
        :root {
            --ig-blue: #0095F6;
            --ig-red: #ED4956;
            --ig-black: #000000;
            --ig-near-black: #262626;
            --ig-off-white: #FAFAFA;
            --ig-dark-surface: #121212;
            --ig-gray: #8E8E8E;
            --ig-border-light: #DBDBDB;
            --ig-border-dark: #262626;
            --bg: var(--ig-off-white);
            --surface: #FFFFFF;
            --text: var(--ig-near-black);
            --border: var(--ig-border-light);
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: var(--ig-dark-surface);
                --surface: var(--ig-black);
                --text: var(--ig-off-white);
                --border: var(--ig-border-dark);
            }
        }
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, "Segoe UI", Tahoma, Arial, sans-serif;
            background: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 3rem 1.25rem 4rem;
            line-height: 1.9;
        }
        .wrap { max-width: 960px; margin: 0 auto; }
        .head { text-align: center; margin-bottom: 2.5rem; }
        .logo-ring {
            display: inline-flex;
            padding: 4px;
            border-radius: 50%;
            background: linear-gradient(135deg, #FEDA75, #FA7E1E, #D62976, #962FBF, #4F5BD5);
            margin-bottom: 1.25rem;
        }
        .logo {
            display: block;
            width: 92px;
            height: 92px;
            border-radius: 50%;
            object-fit: cover;
            border: 3px solid var(--bg);
            background: var(--surface);
        }
        h1 { font-size: 1.7rem; margin: 0 0 .35rem; font-weight: 800; }
        .sub { color: var(--ig-gray); margin: 0; font-size: .95rem; }

        .platforms {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 1.1rem;
            text-align: start;
        }
        @media (max-width: 760px) {
            .platforms { grid-template-columns: 1fr; }
        }
        .platform-card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 1.1rem;
            padding: 1.5rem;
        }
        .platform-card h2 { font-size: 1.05rem; margin: 0 0 .35rem; display: flex; align-items: center; gap: .5rem; font-weight: 700; }
        .platform-card .platform-sub { color: var(--ig-gray); font-size: .8rem; margin-bottom: 1.1rem; }
        .download-btn {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: .5rem;
            background: var(--ig-blue);
            color: #fff;
            font-weight: 700;
            font-size: .95rem;
            text-decoration: none;
            padding: .8rem 1.25rem;
            border-radius: .75rem;
            transition: filter .15s;
        }
        .download-btn:hover { filter: brightness(1.08); }
        .meta { color: var(--ig-gray); font-size: .8rem; margin-top: .7rem; text-align: center; }

        .card {
            text-align: start;
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 1.1rem;
            padding: 1.5rem 1.75rem;
            margin-top: 1.25rem;
        }
        .card h3 { font-size: .95rem; color: var(--ig-blue); margin: 0 0 1rem; font-weight: 700; display: flex; align-items: center; gap: .5rem; }
        .card h3.warn { color: var(--ig-red); }
        .card ol { padding-inline-start: 1.4rem; margin: 0; }
        .card li { color: var(--text); opacity: .85; margin-bottom: .6rem; font-size: .92rem; }
        .card li:last-child { margin-bottom: 0; }
        .card code {
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: .35rem;
            padding: .1rem .4rem;
            font-size: .85em;
        }
        .icon { width: 22px; height: 22px; flex-shrink: 0; }
        .icon-sm { width: 18px; height: 18px; }
        .warn .icon { color: var(--ig-red); }
    </style>
</head>
<body>
<div class="wrap">
    <div class="head">
        <span class="logo-ring">
            @if($clinic->logoUrl())
                <img src="{{ $clinic->logoUrl() }}" alt="" class="logo">
            @else
                <span class="logo"></span>
            @endif
        </span>
        <h1>تحميل التطبيق</h1>
        <p class="sub">{{ $clinic->clinic_name ?: 'عيادة الأسنان التعليمية' }} — {{ $clinic->college_name ?: 'كلية طب الأسنان' }}</p>
    </div>

    <div class="platforms">
        <div class="platform-card">
            <h2>
                <svg class="icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M21 2H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h7l-2 3v1h8v-1l-2-3h7c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H3V4h18v12z"/></svg>
                ويندوز
            </h2>
            <p class="platform-sub">ويندوز 8 فأحدث (64-bit)</p>
            <a href="{{ $windows['url'] }}" class="download-btn">
                <svg class="icon icon-sm" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>
                تحميل للويندوز
            </a>
            <p class="meta">الإصدار {{ $windows['version'] }}</p>
        </div>
        <div class="platform-card">
            <h2>
                <svg class="icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.6 9.48l1.84-3.18c.16-.31.04-.69-.26-.85a.637.637 0 0 0-.83.22l-1.88 3.24a11.463 11.463 0 0 0-8.94 0L5.65 5.67a.643.643 0 0 0-.87-.2c-.28.18-.37.54-.22.83L6.4 9.48C3.3 11.25 1.28 14.44 1 18h22c-.28-3.56-2.3-6.75-5.4-8.52zM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5z"/></svg>
                أندرويد
            </h2>
            <p class="platform-sub">أندرويد 8 فأحدث</p>
            <a href="{{ $android['url'] }}" class="download-btn">
                <svg class="icon icon-sm" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>
                تحميل للأندرويد
            </a>
            <p class="meta">الإصدار {{ $android['version'] }}</p>
        </div>
        <div class="platform-card">
            <h2>
                <svg class="icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.87-.76-1.47.02-2.83.86-3.59 2.18-1.53 2.66-.39 6.6 1.1 8.75.73 1.05 1.6 2.24 2.73 2.2 1.1-.05 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.13.84-1.22 1.18-2.4 1.2-2.46-.03-.01-2.3-.88-2.32-3.52zM14.2 6.13c.6-.73 1.01-1.75.9-2.76-.87.04-1.92.58-2.54 1.31-.56.65-1.05 1.68-.92 2.67.97.08 1.96-.49 2.56-1.22z"/></svg>
                آيفون
            </h2>
            <p class="platform-sub">iOS 15.5 فأحدث</p>
            <a href="{{ $ios['url'] }}" class="download-btn">
                <svg class="icon icon-sm" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>
                تحميل للآيفون
            </a>
            <p class="meta">الإصدار {{ $ios['version'] }}</p>
        </div>
    </div>

    <div class="card">
        <h3 class="warn">
            <svg class="icon icon-sm" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>
            إذا التنزيل ما بدأ أو المتصفح ما رد أي شي
        </h3>
        <ol>
            <li>Chrome/Edge أحيانًا يحجبون تنزيل الملف بصمت (بدون رسالة واضحة) لأنه ملف جديد غير معروف السمعة. تحقق من أيقونة/شريط التنزيلات بأعلى المتصفح، أو افتح <code>chrome://downloads</code>.</li>
            <li>لو لقيت إدخال مكتوب عليه <strong>"Blocked"</strong> أو <strong>"Dangerous file blocked"</strong>، اضغط السهم ⌄ جنبه واختر <strong>"Keep"</strong> أو <strong>"Keep anyway"</strong>.</li>
            <li>إذا استمرت المشكلة، جرّب متصفح ثاني (Firefox مثلاً) أو تواصل معنا.</li>
        </ol>
    </div>

    <div class="card">
        <h3>خطوات التثبيت — ويندوز</h3>
        <ol>
            <li>شغّل الملف الذي حمّلته (<code>DentalClinicSetup-{{ $windows['version'] }}.exe</code>) من مجلد التنزيلات.</li>
            <li>إذا ظهرت رسالة "Windows protected your PC" (SmartScreen)، اضغط <strong>More info</strong> ثم <strong>Run anyway</strong> — طبيعي لأن التطبيق غير موقّع بشهادة تجارية بعد.</li>
            <li>أكمل خطوات التثبيت (Next → Install → Finish).</li>
            <li>بعد أول تشغيل، التطبيق يتحقق من التحديثات تلقائيًا ويحدّث نفسه بصمت عند توفر إصدار جديد — لا حاجة لزيارة هذه الصفحة مرة أخرى.</li>
        </ol>
    </div>

    <div class="card">
        <h3>خطوات التثبيت — أندرويد</h3>
        <ol>
            <li>افتح ملف <code>DentalClinicApp-{{ $android['version'] }}.apk</code> الذي حمّلته.</li>
            <li>إذا ظهرت رسالة تحذير "قد يكون هذا التطبيق ضارًا" أو ما شابه، اسمح بالتثبيت من هذا المصدر (قد يطلب منك تفعيل "Install unknown apps" للمتصفح أو تطبيق الملفات) — طبيعي لأن التطبيق غير منشور على متجر Google Play بعد.</li>
            <li>اضغط تثبيت (Install) وانتظر انتهاء العملية.</li>
            <li>لتحديث التطبيق لاحقًا، نزّل أحدث نسخة من هذه الصفحة وثبّتها فوق النسخة الحالية (لا يوجد تحديث تلقائي على أندرويد بعد).</li>
        </ol>
    </div>

    <div class="card">
        <h3>خطوات التثبيت — آيفون</h3>
        <ol>
            <li>ملف <code>DentalClinicApp-{{ $ios['version'] }}.ipa</code> غير موقّع وغير منشور على App Store، لذلك لا يُثبَّت بفتحه مباشرة من الآيفون — حمّله على جهاز كمبيوتر (ويندوز أو ماك).</li>
            <li>ثبّت برنامج <strong>Sideloadly</strong> أو <strong>AltStore</strong> على الكمبيوتر، ثم وصّل الآيفون بكابل USB.</li>
            <li>اسحب ملف الـ ipa إلى البرنامج، وسجّل الدخول بحساب Apple ID الخاص بك، ثم ابدأ التثبيت.</li>
            <li>على الآيفون افتح <strong>الإعدادات ← عام ← VPN وإدارة الجهاز</strong> واضغط "ثقة" (Trust) على حسابك، ومن iOS 16 فأحدث فعّل <strong>وضع المطوّر</strong> (Developer Mode) من الإعدادات ← الخصوصية والأمان.</li>
            <li>مع حساب Apple ID مجاني يتوقف التطبيق بعد <strong>7 أيام</strong> ويجب تحديثه (Refresh) من Sideloadly/AltStore كل 7 أيام.</li>
            <li>ميزة NFC غير متاحة في هذه النسخة.</li>
        </ol>
    </div>
</div>
</body>
</html>
