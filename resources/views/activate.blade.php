<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>تفعيل النظام</title>
    <style>
        :root { color-scheme: light dark; --bg: #f3f5f8; --card: #fff; --text: #1f2937; --muted: #6b7280; --border: #d1d5db; --accent: #0f9f8f; --red: #dc2626; }
        @media (prefers-color-scheme: dark) { :root { --bg: #11161d; --card: #1c242d; --text: #e5e7eb; --muted: #9ca3af; --border: #334155; } }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 16px; background: var(--bg); color: var(--text); font-family: Tahoma, "Segoe UI", sans-serif; }
        .card { width: 100%; max-width: 440px; background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 28px 24px; }
        h1 { font-size: 1.25rem; margin: 0 0 8px; }
        p { color: var(--muted); font-size: .9rem; line-height: 1.7; margin: 0 0 18px; }
        label { display: block; font-size: .85rem; margin-bottom: 6px; }
        input { width: 100%; padding: 12px; border-radius: 10px; border: 1px solid var(--border); background: transparent; color: var(--text); font-size: 1.1rem; letter-spacing: 2px; text-align: center; direction: ltr; text-transform: uppercase; }
        button { margin-top: 14px; width: 100%; padding: 12px; border: 0; border-radius: 10px; background: var(--accent); color: #fff; font-size: 1rem; cursor: pointer; }
        .error { color: var(--red); font-size: .85rem; margin-top: 8px; }
        .machine { margin-top: 20px; padding-top: 14px; border-top: 1px solid var(--border); font-size: .8rem; color: var(--muted); }
        .machine code { direction: ltr; display: inline-block; font-size: .9rem; color: var(--text); }
    </style>
</head>
<body>
    <form class="card" method="POST" action="/activate">
        @csrf
        <h1>تفعيل النظام على هذا الحاسوب</h1>
        <p>أدخل رمز التفعيل الخاص بجامعتك. يحتاج التفعيل اتصال إنترنت مرة واحدة فقط، وبعدها يعمل النظام بدون إنترنت. كل رمز يُستخدم على حاسوب واحد فقط.</p>
        <label for="code">رمز التفعيل</label>
        <input id="code" name="code" value="{{ old('code') }}" placeholder="XXXX-XXXX-XXXX-XXXX" autocomplete="off" required autofocus>
        @error('code') <div class="error">{{ $message }}</div> @enderror
        <button type="submit">تفعيل</button>
        <div class="machine">رقم هذا الحاسوب: <code>{{ $machineId }}</code> ({{ $machineName }})</div>
    </form>
</body>
</html>
