@php
    /*
        Google Play–style layout (2026-10-18, by request): the app's header
        with an install button, then each download as a store row with its
        install steps folded underneath. Plain Blade with inline CSS, like
        privacy-policy.blade.php: a one-off public page needs no Vite bundle.

        $apps rows: the online apps, then the "offline" builds that start on
        the clinic's own server (see .github/workflows/flutter-apps.yml),
        then the offline server package itself.
    */
    $clinicName = $clinic->clinic_name ?: 'عيادة الأسنان التعليمية';
    $college = $clinic->college_name ?: 'كلية طب الأسنان';
    $logo = $clinic->logoUrl();

    $icons = [
        'windows' => '<path d="M3 5.5 10.5 4.5v7H3zm0 13 7.5 1v-7H3zm8.5 1.1L21 21v-8.5h-9.5zm0-15.2v7.1H21V3z"/>',
        'android' => '<path d="M17.6 9.48l1.84-3.18c.16-.31.04-.69-.26-.85a.637.637 0 0 0-.83.22l-1.88 3.24a11.463 11.463 0 0 0-8.94 0L5.65 5.67a.643.643 0 0 0-.87-.2c-.28.18-.37.54-.22.83L6.4 9.48C3.3 11.25 1.28 14.44 1 18h22c-.28-3.56-2.3-6.75-5.4-8.52zM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5z"/>',
        'ios' => '<path d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.87-.76-1.47.02-2.83.86-3.59 2.18-1.53 2.66-.39 6.6 1.1 8.75.73 1.05 1.6 2.24 2.73 2.2 1.1-.05 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.13.84-1.22 1.18-2.4 1.2-2.46-.03-.01-2.3-.88-2.32-3.52zM14.2 6.13c.6-.73 1.01-1.75.9-2.76-.87.04-1.92.58-2.54 1.31-.56.65-1.05 1.68-.92 2.67.97.08 1.96-.49 2.56-1.22z"/>',
        'server' => '<path d="M20 3H4c-1.1 0-2 .9-2 2v4c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-1 5H5V6h14v2zm1 5H4c-1.1 0-2 .9-2 2v4c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2v-4c0-1.1-.9-2-2-2zm-1 5H5v-2h14v2z"/>',
        'client' => '<path d="M21 2H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h7l-2 3v1h8v-1l-2-3h7c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H3V4h18v12z"/>',
    ];

    $windowsSteps = [
        'شغّل الملف الذي نزّلته من مجلد التنزيلات.',
        'إذا ظهرت رسالة «Windows protected your PC» اضغط <b>More info</b> ثم <b>Run anyway</b>، فالتطبيق غير موقّع بشهادة تجارية بعد.',
        'أكمل التثبيت (Next ← Install ← Finish). التطبيق يحدّث نفسه تلقائيًا بعد ذلك.',
    ];
    $androidSteps = [
        'افتح ملف APK الذي نزّلته.',
        'إن ظهر تحذير، اسمح بـ«تثبيت التطبيقات غير المعروفة» للمتصفح أو مدير الملفات، فالتطبيق غير منشور على Google Play بعد.',
        'اضغط تثبيت. التطبيق ينبّهك داخله عند توفر تحديث.',
        'إن رفض الهاتف التثبيت فوق نسخة قديمة (قبل 1.1.110)، احذف القديمة أولًا.',
    ];
    $offlineNote = 'يتصل بسيرفر العيادة (clinic.lan) ويعمل بدون إنترنت';
    $offlineSteps = fn (array $steps) => array_merge($steps, [
        'يبدأ على سيرفر العيادة clinic.lan، ويمكن تغيير السيرفر من شاشة الدخول. يُنزَّل أيضًا من السيرفر نفسه على <code>http://clinic.lan/apps</code>.',
    ]);

    $apps = [];
    $apps[] = ['section' => 'online', 'icon' => 'android', 'tone' => 'green', 'title' => 'أندرويد', 'sub' => 'أندرويد 8 فأحدث', 'release' => $android, 'button' => 'تثبيت', 'steps' => $androidSteps];
    $apps[] = ['section' => 'online', 'icon' => 'windows', 'tone' => 'blue', 'title' => 'ويندوز', 'sub' => 'ويندوز 8 فأحدث (64-bit)', 'release' => $windows, 'button' => 'تثبيت', 'steps' => $windowsSteps];
    $apps[] = ['section' => 'online', 'icon' => 'ios', 'tone' => 'gray', 'title' => 'آيفون', 'sub' => 'iOS 15.5 فأحدث · يُثبَّت من حاسوب', 'release' => $ios, 'button' => 'تنزيل', 'steps' => [
        'الملف غير موقّع وغير منشور على App Store، فلا يُثبَّت بفتحه من الآيفون: نزّله على حاسوب ويندوز أو ماك.',
        'ثبّت <b>Sideloadly</b> أو <b>AltStore</b> على الحاسوب ووصّل الآيفون بكابل USB.',
        'اسحب ملف ipa إلى البرنامج وسجّل الدخول بحساب Apple ID ثم ابدأ التثبيت.',
        'على الآيفون: الإعدادات ← عام ← VPN وإدارة الجهاز ← ثقة، ومن iOS 16 فعّل <b>وضع المطوّر</b>.',
        'مع حساب Apple مجاني يجب تحديث التطبيق (Refresh) من البرنامج كل 7 أيام. ميزة NFC غير متاحة.',
    ]];
    if (! empty($androidOffline['url'])) {
        $apps[] = ['section' => 'offline', 'icon' => 'android', 'tone' => 'teal', 'title' => 'أندرويد أوفلاين', 'sub' => $offlineNote, 'release' => $androidOffline, 'button' => 'تثبيت', 'steps' => $offlineSteps($androidSteps)];
    }
    if (! empty($windowsOffline['url'])) {
        $apps[] = ['section' => 'offline', 'icon' => 'windows', 'tone' => 'teal', 'title' => 'ويندوز أوفلاين', 'sub' => $offlineNote, 'release' => $windowsOffline, 'button' => 'تثبيت', 'steps' => $offlineSteps($windowsSteps)];
    }
    if ($offline) {
        $apps[] = ['section' => 'offline', 'icon' => 'server', 'tone' => 'purple', 'title' => 'سيرفر الأوفلاين',
            'sub' => 'النظام كامل على حاسوب ويندوز واحد بدون إنترنت، ويحتاج رمز تفعيل الجامعة مرة واحدة',
            'release' => ['url' => $offline['url'], 'version' => $offline['build'], 'size' => $offline['size'] ?? null], 'button' => 'تنزيل', 'steps' => [
                'فك ضغط الملف في مكان ثابت (مثل C:\\DentalClinicOffline) وشغّل <b>DentalClinic.exe</b>.',
                'اضغط تشغيل، ثم أدخل رمز تفعيل الجامعة في المتصفح عند أول فتح (يحتاج إنترنت مرة واحدة).',
                'لنقل بيانات هذا الموقع إليه: صفحة «النسخ الاحتياطي» هنا ← «تنزيل النسخة»، ثم «استعادة نسخة» في لوحة التحكم.',
            ]];
        if (! empty($offline['client_url'])) {
            $apps[] = ['section' => 'offline', 'icon' => 'client', 'tone' => 'purple', 'title' => 'برنامج الحواسيب الأخرى',
                'sub' => 'لحواسيب العيادة الأخرى: يفتح النظام من السيرفر ويطبع التكت والوصولات مباشرة',
                'release' => ['url' => $offline['client_url'], 'version' => $offline['build'], 'size' => $offline['client_size'] ?? null], 'button' => 'تثبيت', 'steps' => $windowsSteps];
        }
    }

    $mb = fn ($bytes) => $bytes ? (round($bytes / 1048576, $bytes < 10485760 ? 1 : 0).' م.ب') : null;
@endphp
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>تحميل التطبيق — {{ $clinicName }}</title>
    <style>
        :root {
            --bg: #ffffff;
            --surface: #ffffff;
            --text: #1f1f1f;
            --muted: #5f6368;
            --line: #e0e0e0;
            --chip: #f1f3f4;
            --play: #01875f;
            --play-hover: #016e4e;
            --link: #01875f;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #131314;
                --surface: #1e1f20;
                --text: #e3e3e3;
                --muted: #a8abaf;
                --line: #333537;
                --chip: #2a2b2d;
                --play: #5bb974;
                --play-hover: #7ccc8f;
                --link: #81c995;
            }
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: "Google Sans", Roboto, -apple-system, "Segoe UI", Tahoma, Arial, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.6;
        }
        .wrap { max-width: 880px; margin: 0 auto; padding: 1.75rem 1rem 4rem; }

        .hero { display: flex; gap: 1.25rem; align-items: center; }
        .hero-icon {
            width: 88px; height: 88px; flex-shrink: 0; border-radius: 20px; object-fit: cover;
            box-shadow: 0 1px 3px rgba(0,0,0,.25); background: linear-gradient(135deg, #01875f, #34a853);
            display: flex; align-items: center; justify-content: center; color: #fff; font-size: 2.2rem; font-weight: 700;
        }
        .hero h1 { margin: 0; font-size: 1.6rem; font-weight: 600; line-height: 1.3; }
        .dev { color: var(--link); font-weight: 600; font-size: .95rem; margin-top: .15rem; }
        .hero-sub { color: var(--muted); font-size: .8rem; }

        .stats { display: flex; margin: 1.25rem 0 1rem; overflow-x: auto; scrollbar-width: none; }
        .stat { flex: 0 0 auto; padding: 0 1.25rem; text-align: center; border-inline-start: 1px solid var(--line); }
        .stat:first-child { border-inline-start: 0; padding-inline-start: 0; }
        .stat b { display: block; font-size: .95rem; font-weight: 600; }
        .stat span { color: var(--muted); font-size: .75rem; }

        .install {
            display: inline-flex; align-items: center; justify-content: center; gap: .4rem;
            background: var(--play); color: #fff; text-decoration: none; font-weight: 600; font-size: .9rem;
            border-radius: 10px; padding: .55rem 1.6rem; min-width: 6.5rem; border: 0; cursor: pointer;
        }
        @media (prefers-color-scheme: dark) { .install { color: #0b2814; } }
        .install:hover { background: var(--play-hover); }
        .hero-actions { display: flex; flex-wrap: wrap; gap: .6rem; margin-bottom: 1.5rem; }
        .hero-actions .install { flex: 1 1 12rem; padding: .7rem 1rem; }

        h2 { font-size: 1.15rem; font-weight: 600; margin: 2rem 0 .25rem; display: flex; align-items: center; gap: .5rem; }
        .section-note { color: var(--muted); font-size: .85rem; margin: 0 0 .75rem; }

        .app { border-bottom: 1px solid var(--line); }
        .row { display: flex; align-items: center; gap: 1rem; padding: .9rem 0; }
        .app-icon {
            width: 56px; height: 56px; flex-shrink: 0; border-radius: 14px;
            display: flex; align-items: center; justify-content: center; color: #fff;
            box-shadow: 0 1px 2px rgba(0,0,0,.2);
        }
        .app-icon svg { width: 30px; height: 30px; fill: currentColor; }
        .tone-green { background: linear-gradient(135deg, #34a853, #0f9d58); }
        .tone-blue { background: linear-gradient(135deg, #4285f4, #1a73e8); }
        .tone-gray { background: linear-gradient(135deg, #5f6368, #202124); }
        .tone-teal { background: linear-gradient(135deg, #12b5cb, #00796b); }
        .tone-purple { background: linear-gradient(135deg, #a142f4, #6a1b9a); }
        .info { flex: 1; min-width: 0; }
        .info .name { font-weight: 600; font-size: 1rem; }
        .info .sub { color: var(--muted); font-size: .8rem; }
        .info .meta { color: var(--muted); font-size: .75rem; margin-top: .15rem; }
        .actions { display: flex; flex-direction: column; align-items: center; gap: .25rem; }
        .zip { color: var(--link); font-size: .72rem; text-decoration: none; }
        .zip:hover { text-decoration: underline; }

        details { padding: 0 0 .9rem; padding-inline-start: 72px; }
        summary { cursor: pointer; color: var(--link); font-size: .82rem; font-weight: 600; list-style: none; }
        summary::-webkit-details-marker { display: none; }
        summary::after { content: " ⌄"; }
        details[open] summary::after { content: " ⌃"; }
        details ol { margin: .5rem 0 0; padding-inline-start: 1.2rem; font-size: .85rem; color: var(--text); }
        details li { margin-bottom: .35rem; }

        .help { background: var(--chip); border-radius: 14px; padding: 1rem 1.25rem; margin-top: 2rem; font-size: .85rem; }
        .help h3 { margin: 0 0 .5rem; font-size: .95rem; }
        .help ol { margin: 0; padding-inline-start: 1.2rem; }
        code { background: var(--surface); border: 1px solid var(--line); border-radius: 6px; padding: 0 .3rem; font-size: .85em; }

        @media (max-width: 560px) {
            .hero-icon { width: 72px; height: 72px; border-radius: 16px; }
            .hero h1 { font-size: 1.3rem; }
            details { padding-inline-start: 0; }
        }
    </style>
</head>
<body>
<div class="wrap">
    <div class="hero">
        @if($logo)
            <img src="{{ $logo }}" alt="" class="hero-icon">
        @else
            <span class="hero-icon">ع</span>
        @endif
        <div>
            <h1>{{ $clinicName }}</h1>
            <div class="dev">{{ $college }}</div>
            <div class="hero-sub">نظام العيادة التعليمية · أندرويد · ويندوز · آيفون</div>
        </div>
    </div>

    <div class="stats">
        <div class="stat"><b>{{ $android['version'] }}</b><span>الإصدار</span></div>
        <div class="stat"><b>3</b><span>أنظمة</span></div>
        <div class="stat"><b>مجاني</b><span>للطلاب والكادر</span></div>
        @if ($offline)
            <div class="stat"><b>أوفلاين</b><span>بدون إنترنت</span></div>
        @endif
    </div>

    <div class="hero-actions">
        <a href="{{ $android['url'] }}" class="install">تثبيت على أندرويد</a>
        <a href="{{ $windows['url'] }}" class="install">تثبيت على ويندوز</a>
    </div>

    @foreach (['online' => ['تطبيقات العيادة', 'تعمل عبر الإنترنت على هذا الموقع.'], 'offline' => ['للعمل بدون إنترنت (أوفلاين)', 'لسيرفر العيادة على شبكتها المحلية: السيرفر نفسه، وتطبيقات تتصل به مباشرة.']] as $section => [$heading, $note])
        @php $rows = array_filter($apps, fn ($a) => $a['section'] === $section); @endphp
        @if ($rows)
            <h2>{{ $heading }}</h2>
            <p class="section-note">{{ $note }}</p>
            @foreach ($rows as $app)
                <div class="app">
                    <div class="row">
                        <span class="app-icon tone-{{ $app['tone'] }}"><svg viewBox="0 0 24 24" aria-hidden="true">{!! $icons[$app['icon']] !!}</svg></span>
                        <div class="info">
                            <div class="name">{{ $app['title'] }}</div>
                            <div class="sub">{{ $app['sub'] }}</div>
                            <div class="meta">
                                الإصدار {{ $app['release']['version'] ?? '' }}
                                @if ($size = $mb($app['release']['size'] ?? null)) · {{ $size }} @endif
                            </div>
                        </div>
                        <div class="actions">
                            <a href="{{ $app['release']['url'] }}" class="install">{{ $app['button'] }}</a>
                            @if (! empty($app['release']['zip_url']))
                                <a href="{{ $app['release']['zip_url'] }}" class="zip">نسخة ZIP</a>
                            @endif
                        </div>
                    </div>
                    <details>
                        <summary>طريقة التثبيت</summary>
                        <ol>
                            @foreach ($app['steps'] as $step)
                                <li>{!! $step !!}</li>
                            @endforeach
                        </ol>
                    </details>
                </div>
            @endforeach
        @endif
    @endforeach

    <div class="help">
        <h3>إذا لم يبدأ التنزيل</h3>
        <ol>
            <li>Chrome وEdge قد يحجبان الملف بصمت لأنه جديد. افتح التنزيلات (<code>chrome://downloads</code>).</li>
            <li>إن ظهر <b>Blocked</b> أو <b>Dangerous</b>، اضغط ⌄ بجانبه واختر <b>Keep</b>، أو نزّل «نسخة ZIP» وفك ضغطها.</li>
            <li>إن استمرت المشكلة جرّب متصفحًا آخر.</li>
        </ol>
    </div>
</div>
</body>
</html>
