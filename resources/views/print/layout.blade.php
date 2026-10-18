{{--
    Shared shell for the printable documents (doctor roster, doctor card).
    Standalone by design: its own letterhead and print rules, no app chrome.
--}}
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title', 'طباعة')</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: "Segoe UI", Tahoma, Arial, sans-serif;
            margin: 0;
            padding: 24px;
            color: #1f2937;
            background: #fff;
        }
        .watermark {
            position: fixed;
            inset: 0;
            display: flex;
            align-items: center;
            justify-content: center;
            opacity: .05;
            z-index: 0;
            pointer-events: none;
        }
        .watermark img { max-width: 60%; }
        .sheet { position: relative; z-index: 1; }

        .letterhead { text-align: center; border-bottom: 2px solid #374151; padding-bottom: 12px; margin-bottom: 20px; }
        .letterhead img { height: 80px; object-fit: contain; margin-bottom: 8px; }
        .letterhead h1 { font-size: 20px; margin: 0; }
        .letterhead h2 { font-size: 16px; margin: 4px 0; font-weight: 600; color: #374151; }
        .letterhead p { margin: 2px 0; font-size: 13px; }
        .muted { color: #6b7280; }

        table { width: 100%; border-collapse: collapse; margin-bottom: 18px; font-size: 13px; }
        th, td { border: 1px solid #9ca3af; padding: 6px 8px; text-align: right; }
        thead th { background: #f3f4f6; }
        tbody tr:nth-child(even) { background: #fafafa; }

        h3.section { font-size: 15px; margin: 18px 0 8px; }

        .summary { margin: 24px auto 0; max-width: 480px; border: 1px solid #9ca3af; border-radius: 8px; padding: 12px 16px; }
        .summary h3 { margin: 0 0 8px; font-size: 15px; text-align: center; border-bottom: 1px solid #d1d5db; padding-bottom: 6px; }
        .summary-row { display: flex; justify-content: space-between; font-size: 13px; padding: 3px 0; }

        .signatures { display: flex; justify-content: space-around; margin-top: 48px; font-size: 13px; }
        .signature { text-align: center; min-width: 160px; border-top: 1px solid #9ca3af; padding-top: 6px; }

        .toolbar { text-align: center; margin-bottom: 16px; }
        .toolbar button, .toolbar a {
            font: inherit; font-size: 14px; padding: 8px 18px; margin: 0 4px;
            border: 0; border-radius: 6px; cursor: pointer; text-decoration: none; display: inline-block;
        }
        .btn-print { background: #4f46e5; color: #fff; }
        .btn-back { background: #e5e7eb; color: #374151; }

        /* The toolbar is for the screen only; the watermark must survive
           printing, which needs colour-adjust or browsers drop backgrounds. */
        @media print {
            body { padding: 0; }
            .toolbar { display: none !important; }
            .watermark { opacity: .06; }
            * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
            @page { margin: 12mm; }
        }
    </style>
</head>
<body>
    <div class="toolbar">
        <button type="button" class="btn-print" onclick="window.print()">طباعة</button>
        <a href="@yield('back_url', route('doctors.index'))" class="btn-back">رجوع</a>
    </div>

    @if ($settings->logoUrl())
        <div class="watermark"><img src="{{ $settings->logoUrl() }}" alt=""></div>
    @endif

    <div class="sheet">
        @unless (View::hasSection('no_letterhead'))
        <div class="letterhead">
            @if ($settings->universityLogoUrl())
                <img src="{{ $settings->universityLogoUrl() }}" alt="">
            @elseif ($settings->logoUrl())
                <img src="{{ $settings->logoUrl() }}" alt="">
            @endif
            <h1>{{ $settings->university_name ?: $settings->clinic_name }}</h1>
            <h2>{{ $settings->college_name }}</h2>
            @yield('letterhead')
            <p class="muted">تاريخ الطباعة: {{ now()->format('Y-m-d H:i') }}</p>
        </div>
        @endunless

        @yield('content')
    </div>
</body>
</html>
