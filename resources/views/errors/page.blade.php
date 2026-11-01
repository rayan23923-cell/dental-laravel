@php
    // Our own error page instead of the framework's plain one (2026-11-01,
    // by request): Arabic and English, a back button, and no framework
    // branding. Self-contained (no Vite bundle, no database needed) so it
    // still renders when the error came from the app itself.
    $status = isset($exception) && method_exists($exception, 'getStatusCode') ? $exception->getStatusCode() : 500;

    $texts = [
        401 => ['ar' => ['غير مسجّل الدخول', 'يجب تسجيل الدخول للوصول إلى هذه الصفحة.'], 'en' => ['Not signed in', 'Please sign in to open this page.']],
        403 => ['ar' => ['لا تملك صلاحية', 'ليست لديك صلاحية للوصول إلى هذه الصفحة.'], 'en' => ['Access denied', 'You do not have permission to open this page.']],
        404 => ['ar' => ['الصفحة غير موجودة', 'الصفحة التي تبحث عنها غير موجودة أو تم نقلها.'], 'en' => ['Page not found', 'The page you are looking for does not exist or has moved.']],
        405 => ['ar' => ['طريقة الطلب غير مسموحة', 'لا يمكن فتح هذا الرابط بهذه الطريقة. ارجع وحاول من داخل النظام.'], 'en' => ['Method not allowed', 'This link cannot be opened this way. Go back and try again from inside the system.']],
        419 => ['ar' => ['انتهت الجلسة', 'انتهت صلاحية الصفحة. حدّث الصفحة وحاول مرة أخرى.'], 'en' => ['Session expired', 'This page has expired. Refresh it and try again.']],
        429 => ['ar' => ['طلبات كثيرة', 'أرسلت طلبات كثيرة خلال وقت قصير. انتظر قليلًا ثم حاول مرة أخرى.'], 'en' => ['Too many requests', 'Too many requests in a short time. Wait a moment and try again.']],
        500 => ['ar' => ['خطأ في الخادم', 'حدث خطأ غير متوقع. حاول مرة أخرى بعد قليل.'], 'en' => ['Server error', 'Something went wrong. Please try again shortly.']],
        503 => ['ar' => ['الخدمة غير متاحة مؤقتًا', 'النظام قيد الصيانة أو التحديث. حاول مرة أخرى بعد قليل.'], 'en' => ['Temporarily unavailable', 'The system is being maintained or updated. Please try again shortly.']],
    ];
    $text = $texts[$status] ?? ($status >= 500 ? $texts[500] : ['ar' => ['حدث خطأ', 'تعذّر فتح هذه الصفحة.'], 'en' => ['Something went wrong', 'This page could not be opened.']]);

    try {
        $principal = auth('web')->user() ?? auth('doctor')->user();
    } catch (\Throwable) {
        $principal = null;
    }
    $locale = in_array($principal?->locale, ['ar', 'en'], true)
        ? $principal->locale
        : (request()->getPreferredLanguage(['ar', 'en']) ?? 'ar');
@endphp
<!DOCTYPE html>
<html lang="{{ $locale }}" dir="{{ $locale === 'ar' ? 'rtl' : 'ltr' }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>{{ $status }} · {{ $text[$locale][0] }}</title>
    <link rel="icon" href="/icons/icon-192.png">
    <style>
        :root { --bg: #f3f6fa; --card: #fff; --text: #1f2937; --muted: #6b7280; --accent: #0f766e; --accent-soft: #ccfbf1; --border: #e5e7eb; }
        @media (prefers-color-scheme: dark) {
            :root { --bg: #0f172a; --card: #1e293b; --text: #e5e7eb; --muted: #94a3b8; --accent: #2dd4bf; --accent-soft: #134e4a; --border: #334155; }
        }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px;
               background: var(--bg); color: var(--text); font-family: "Segoe UI", Tahoma, "Noto Sans Arabic", Arial, sans-serif; }
        .card { width: 100%; max-width: 440px; background: var(--card); border: 1px solid var(--border); border-radius: 20px; padding: 32px 24px; text-align: center; box-shadow: 0 10px 30px rgba(0,0,0,.06); }
        .code { font-size: 64px; font-weight: 800; line-height: 1; color: var(--accent); letter-spacing: 2px; }
        h1 { font-size: 22px; margin: 16px 0 8px; }
        p { margin: 0 0 24px; color: var(--muted); line-height: 1.7; }
        .actions { display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; }
        a.btn, button.btn { appearance: none; border: 0; cursor: pointer; border-radius: 12px; padding: 12px 20px; font: inherit; font-weight: 600; text-decoration: none; }
        .primary { background: var(--accent); color: #fff; }
        .secondary { background: var(--accent-soft); color: var(--text); }
        .lang { margin-top: 20px; background: none; border: 0; color: var(--muted); cursor: pointer; font: inherit; text-decoration: underline; }
        [data-lang] { display: none; }
        html[lang="ar"] [data-lang="ar"], html[lang="en"] [data-lang="en"] { display: block; }
        html[lang="ar"] span[data-lang="ar"], html[lang="en"] span[data-lang="en"] { display: inline; }
    </style>
</head>
<body>
    <main class="card">
        <div class="code">{{ $status }}</div>
        @foreach (['ar', 'en'] as $l)
            <div data-lang="{{ $l }}">
                <h1>{{ $text[$l][0] }}</h1>
                <p>{{ $text[$l][1] }}</p>
            </div>
        @endforeach
        <div class="actions">
            <button type="button" class="btn primary" onclick="goBack()">
                <span data-lang="ar">→ رجوع للصفحة السابقة</span><span data-lang="en">← Go back</span>
            </button>
            @if ($status === 419)
                <button type="button" class="btn secondary" onclick="location.reload()">
                    <span data-lang="ar">تحديث الصفحة</span><span data-lang="en">Refresh</span>
                </button>
            @endif
            <a class="btn secondary" href="/">
                <span data-lang="ar">الصفحة الرئيسية</span><span data-lang="en">Home</span>
            </a>
        </div>
        <button type="button" class="lang" onclick="toggleLang()">
            <span data-lang="ar">English</span><span data-lang="en">العربية</span>
        </button>
    </main>
    <script>
        function goBack() {
            if (history.length > 1 && document.referrer) { history.back(); } else { location.href = '/'; }
        }
        function toggleLang() {
            var html = document.documentElement, next = html.lang === 'ar' ? 'en' : 'ar';
            html.lang = next; html.dir = next === 'ar' ? 'rtl' : 'ltr';
            try { localStorage.setItem('error-page-lang', next); } catch (e) {}
        }
        try {
            var saved = localStorage.getItem('error-page-lang');
            if (saved === 'ar' || saved === 'en') { document.documentElement.lang = saved; document.documentElement.dir = saved === 'ar' ? 'rtl' : 'ltr'; }
        } catch (e) {}
    </script>
</body>
</html>
