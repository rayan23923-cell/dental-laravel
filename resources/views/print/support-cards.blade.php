{{-- Care cards to print on A4 and cut (2026-11-01, by request): ten to a
     page, cut on the dashed lines; see SupportCodeController::cards. The
     wording stays neutral on purpose. --}}
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>بطاقات الرعاية - {{ $title }}</title>
    <style>
        @page { size: A4; margin: 8mm; }
        * { box-sizing: border-box; }
        body { margin: 0; font-family: Tahoma, "Segoe UI", Arial, sans-serif; color: #111; background: #f3f4f6; }
        .bar { position: sticky; top: 0; display: flex; flex-wrap: wrap; gap: 12px; align-items: center; justify-content: center; padding: 10px; background: #0f766e; color: #fff; font-size: 14px; }
        .bar button, .bar a { font: inherit; padding: 6px 18px; border: 0; border-radius: 18px; background: #fff; color: #0f766e; cursor: pointer; text-decoration: none; }
        .page { display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: repeat(5, minmax(0, 1fr)); width: 194mm; height: 280mm; margin: 10px auto; background: #fff; page-break-after: always; break-after: page; }
        .page:last-child { page-break-after: auto; break-after: auto; }
        .card { border: 1px dashed #888; padding: 4mm 5mm; display: flex; flex-direction: column; gap: 1.5mm; overflow: hidden; position: relative; }
        .head { display: flex; justify-content: space-between; align-items: center; gap: 2mm; border-bottom: 1.5px solid #0f766e; padding-bottom: 1.2mm; }
        .head img { height: 9mm; width: auto; }
        .title { font-weight: bold; color: #0f766e; font-size: 10.5pt; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; flex: 1; }
        .label { font-size: 9pt; background: #ccfbf1; color: #115e59; padding: .4mm 3mm; border-radius: 3mm; white-space: nowrap; font-weight: bold; }
        .k { text-align: center; color: #555; font-size: 9pt; margin-top: 1mm; }
        .code { text-align: center; direction: ltr; font-family: Consolas, "DejaVu Sans Mono", monospace; font-size: 26pt; font-weight: bold; letter-spacing: 3mm; color: #0f172a; border: 1.5px solid #0f766e; border-radius: 3mm; padding: 1mm 0 1mm 3mm; margin: 0 8mm; }
        .ul { font-size: 8.5pt; color: #333; line-height: 1.5; margin: 0; padding: 0 4mm 0 0; }
        .foot { margin-top: auto; display: flex; justify-content: space-between; font-size: 7pt; color: #888; }
        .empty { text-align: center; padding: 40px; font-size: 16px; }
        @media print { body { background: #fff; } .bar { display: none; } .page { margin: 0; } }
    </style>
</head>
<body>
    <div class="bar">
        <span>{{ $codes->count() }} بطاقة · {{ (int) ceil($codes->count() / 10) }} صفحة A4 · اطبع ثم قص على الخطوط المنقطة</span>
        @if ($codes->count())
            <button type="button" onclick="window.print()">طباعة / حفظ PDF</button>
        @endif
        <a href="{{ route('support-codes.index') }}">رجوع</a>
    </div>
    @forelse ($codes->chunk(10) as $page)
        <section class="page">
            @foreach ($page as $c)
                <div class="card">
                    <div class="head">
                        @if ($settings->logoUrl())
                            <img src="{{ $settings->logoUrl() }}" alt="">
                        @endif
                        <span class="title">{{ $title }}</span>
                        <span class="label">بطاقة رعاية</span>
                    </div>
                    <div class="k">رمز الرعاية</div>
                    <div class="code">{{ $c->code }}</div>
                    <ul class="ul">
                        <li>تُقدَّم إلى موظف التذاكر عند التسجيل.</li>
                        <li>تشمل أجور الخدمة وفحص المختبر.</li>
                        <li>صالحة لمرة واحدة فقط.</li>
                    </ul>
                    <div class="foot"><span>دفعة {{ $c->batch }}</span><span dir="ltr">#{{ $c->id }}</span></div>
                </div>
            @endforeach
        </section>
    @empty
        <p class="empty">لا توجد أكواد فعّالة للطباعة.</p>
    @endforelse

    @if ($autoprint && $codes->count())
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
</body>
</html>
