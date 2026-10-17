<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>@yield('title', 'التراخيص') · بوابة التراخيص</title>
    <style>
        :root { color-scheme: light dark; --bg: #f3f5f8; --card: #fff; --card-2: #f8fafc; --text: #1f2937; --muted: #6b7280; --border: #e2e8f0; --accent: #0f9f8f; --accent-fg: #fff; --red: #dc2626; --amber: #b45309; --green: #15803d; }
        @media (prefers-color-scheme: dark) { :root { --bg: #11161d; --card: #1c242d; --card-2: #232d38; --text: #e5e7eb; --muted: #9ca3af; --border: #334155; --red: #f87171; --amber: #fbbf24; --green: #4ade80; } }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; background: var(--bg); color: var(--text); font-family: Tahoma, "Segoe UI", sans-serif; font-size: 15px; }
        a { color: var(--accent); text-decoration: none; }
        header { background: var(--card); border-bottom: 1px solid var(--border); }
        .bar { max-width: 1100px; margin: 0 auto; padding: 12px 16px; display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
        .brand { font-weight: bold; font-size: 1.05rem; color: var(--text); }
        .bar nav { display: flex; gap: 14px; margin-inline-start: auto; align-items: center; }
        main { max-width: 1100px; margin: 0 auto; padding: 20px 16px 40px; }
        h1 { font-size: 1.35rem; margin: 0 0 4px; }
        h2 { font-size: 1.05rem; margin: 0 0 12px; }
        .muted { color: var(--muted); font-size: .85rem; }
        .card { background: var(--card); border: 1px solid var(--border); border-radius: 14px; padding: 18px; margin-bottom: 16px; }
        .grid { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); }
        .stat { background: var(--card-2); border-radius: 10px; padding: 12px; }
        .stat b { display: block; font-size: 1.4rem; margin-top: 4px; }
        form.inline { display: inline; }
        .row { display: flex; gap: 10px; flex-wrap: wrap; align-items: end; }
        .row > label { flex: 1 1 180px; }
        label { display: block; font-size: .85rem; color: var(--muted); }
        input, select { width: 100%; margin-top: 4px; padding: 9px 10px; border-radius: 9px; border: 1px solid var(--border); background: var(--card-2); color: var(--text); font: inherit; }
        button, .btn { display: inline-block; padding: 9px 14px; border-radius: 9px; border: 1px solid var(--border); background: var(--card-2); color: var(--text); font: inherit; cursor: pointer; white-space: nowrap; }
        .btn-primary { background: var(--accent); color: var(--accent-fg); border-color: var(--accent); }
        .btn-small { padding: 4px 9px; font-size: .8rem; }
        .btn-danger { color: var(--red); }
        .link { background: none; border: 0; color: var(--accent); padding: 0; }
        .table-wrap { overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: start; padding: 9px 8px; border-bottom: 1px solid var(--border); vertical-align: middle; }
        th { font-size: .8rem; color: var(--muted); font-weight: normal; }
        code, .ltr { direction: ltr; unicode-bidi: embed; font-family: Consolas, monospace; }
        code { white-space: nowrap; }
        .tag { display: inline-block; padding: 2px 8px; border-radius: 99px; font-size: .75rem; background: var(--card-2); }
        .tag.green { color: var(--green); } .tag.red { color: var(--red); } .tag.amber { color: var(--amber); }
        .flash { padding: 10px 14px; border-radius: 10px; margin-bottom: 14px; background: var(--card); border: 1px solid var(--border); }
        .flash.ok { border-color: var(--green); } .flash.err { border-color: var(--red); color: var(--red); }
        .error { color: var(--red); font-size: .8rem; margin-top: 4px; }
        .actions { display: flex; gap: 6px; flex-wrap: wrap; }
    </style>
</head>
<body>
    @auth('license')
        <header>
            <div class="bar">
                <a class="brand" href="{{ route('licensing.home') }}">بوابة التراخيص</a>
                <nav>
                    <a href="{{ route('licensing.home') }}">الجامعات</a>
                    <a href="{{ route('licensing.account') }}">{{ auth('license')->user()->name }}</a>
                    <form class="inline" method="POST" action="{{ route('licensing.logout') }}">
                        @csrf
                        <button class="link" type="submit">خروج</button>
                    </form>
                </nav>
            </div>
        </header>
    @endauth
    <main>
        @if (session('success')) <div class="flash ok">{{ session('success') }}</div> @endif
        @if (session('error')) <div class="flash err">{{ session('error') }}</div> @endif
        @yield('content')
    </main>
    <script>
        // Confirm destructive actions before submitting.
        document.addEventListener('submit', function (e) {
            var msg = e.target.getAttribute('data-confirm');
            if (msg && !confirm(msg)) e.preventDefault();
        });
        document.addEventListener('click', function (e) {
            var code = e.target.closest('[data-copy]');
            if (!code || !navigator.clipboard) return;
            navigator.clipboard.writeText(code.getAttribute('data-copy'));
            code.setAttribute('title', 'تم النسخ');
        });
    </script>
</body>
</html>
