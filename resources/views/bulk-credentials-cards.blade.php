{{-- Login cards to print on A4 and cut (2026-11-01, by request): see BulkCredentialsController::cards. --}}
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>بطاقات الدخول - {{ $title }}</title>
    <style>
        @page { size: A4; margin: 8mm; }
        * { box-sizing: border-box; }
        body { margin: 0; font-family: Tahoma, "Segoe UI", Arial, sans-serif; color: #111; background: #f3f4f6; }
        .bar { position: sticky; top: 0; display: flex; gap: 12px; align-items: center; justify-content: center; padding: 10px; background: #0e7490; color: #fff; font-size: 14px; }
        .bar button { font: inherit; padding: 6px 18px; border: 0; border-radius: 18px; background: #fff; color: #0e7490; cursor: pointer; }
        .page { display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: repeat(5, 1fr); width: 194mm; height: 280mm; margin: 10px auto; background: #fff; page-break-after: always; break-after: page; }
        .page:last-child { page-break-after: auto; break-after: auto; }
        .card { border: 1px dashed #888; padding: 3.5mm 4.5mm; display: flex; flex-direction: column; gap: 1.5mm; overflow: hidden; }
        .head { display: flex; justify-content: space-between; align-items: center; gap: 2mm; border-bottom: 1.5px solid #0e7490; padding-bottom: 1mm; }
        .title { font-weight: bold; color: #0e7490; font-size: 10.5pt; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .label { font-size: 8.5pt; background: #e0f2fe; color: #075985; padding: .3mm 2.5mm; border-radius: 3mm; white-space: nowrap; }
        .name { font-weight: bold; font-size: 11.5pt; text-align: center; }
        table { width: 100%; border-collapse: collapse; font-size: 9.5pt; }
        td { padding: .6mm 0; }
        .k { color: #555; width: 25mm; }
        .v { direction: ltr; text-align: left; font-family: Consolas, "DejaVu Sans Mono", monospace; font-size: 10pt; }
        .pw { font-weight: bold; font-size: 13pt; letter-spacing: .6mm; }
        .note { font-size: 7.5pt; color: #666; margin-top: auto; line-height: 1.35; }
        @media print { body { background: #fff; } .bar { display: none; } .page { margin: 0; } }
    </style>
</head>
<body>
    <div class="bar">
        <span>{{ $cards->count() }} بطاقة · {{ (int) ceil($cards->count() / 10) }} صفحة A4 · اطبع ثم قص على الخطوط المنقطة</span>
        <button type="button" onclick="window.print()">طباعة / حفظ PDF</button>
    </div>
    @foreach ($cards->chunk(10) as $page)
        <section class="page">
            @foreach ($page as $c)
                <div class="card">
                    <div class="head"><span class="title">{{ $title }}</span><span class="label">{{ $c['label'] }}</span></div>
                    <div class="name" dir="auto">{{ $c['name'] }}</div>
                    <table>
                        <tr><td class="k">اسم المستخدم</td><td class="v">{{ $c['username'] }}</td></tr>
                        <tr><td class="k">كلمة المرور</td><td class="v pw">{{ $c['password'] }}</td></tr>
                        <tr><td class="k">رابط النظام</td><td class="v">{{ $loginUrl }}</td></tr>
                        <tr><td class="k">أو بالآيبي</td><td class="v">{{ $altUrl }}</td></tr>
                    </table>
                    <div class="note">يعمل فقط عند الاتصال بشبكة (واي فاي) عيادة المستشفى التعليمي. يُفضّل تغيير كلمة المرور بعد أول دخول.</div>
                </div>
            @endforeach
        </section>
    @endforeach
</body>
</html>
