<!doctype html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="refresh" content="60">
    <title>خادم العيادة غير متصل</title>
    <style>
        body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f1f5f9; color: #0f172a;
               font-family: "Segoe UI", Tahoma, Arial, sans-serif; padding: 16px; box-sizing: border-box; }
        .card { background: #fff; border-radius: 16px; box-shadow: 0 10px 30px rgba(15, 23, 42, .08); padding: 32px 28px;
                max-width: 440px; text-align: center; }
        .dot { width: 56px; height: 56px; border-radius: 50%; background: #fef3c7; color: #d97706; display: grid;
               place-items: center; font-size: 28px; margin: 0 auto 16px; }
        h1 { font-size: 20px; margin: 0 0 10px; }
        p { color: #475569; line-height: 1.8; margin: 0 0 8px; font-size: 15px; }
        .muted { color: #94a3b8; font-size: 13px; }
    </style>
</head>
<body>
    <div class="card">
        <div class="dot">!</div>
        <h1>خادم العيادة غير متصل بالإنترنت الآن</h1>
        <p>هذا الرابط يفتح نظام العيادة الذي يعمل على حاسوب العيادة (النسخة الأوفلاين).
           يعمل الرابط عندما يكون ذلك الحاسوب يعمل ومتصلًا بالإنترنت و«الوصول عبر الإنترنت» مفعّل في لوحة التشغيل.</p>
        @if ($license->tunnel_seen_at)
            <p class="muted">آخر اتصال: {{ $license->tunnel_seen_at->locale('ar')->diffForHumans() }}</p>
        @endif
        <p class="muted">تُعاد المحاولة تلقائيًا كل دقيقة.</p>
    </div>
</body>
</html>
