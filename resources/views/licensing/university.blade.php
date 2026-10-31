@extends('licensing.layout')

@section('title', $university->name)

@section('content')
    @php
        $used = $licenses->whereNotNull('machine_id');
        $free = $licenses->whereNull('machine_id');
        $latestBuild = $latest['build'] ?? null;
        $active = $university->activeDevices();
        $outdated = $latestBuild ? $used->filter(fn ($l) => $l->installed_build && $l->installed_build < $latestBuild)->count() : 0;
    @endphp

    <p class="muted" style="margin: 0 0 6px;"><a href="{{ route('licensing.home') }}">الجامعات</a> ›</p>
    <h1>{{ $university->name }}</h1>
    @if ($university->contact || $university->notes)
        <p class="muted" style="margin: 0 0 16px;">{{ collect([$university->contact, $university->notes])->filter()->join(' · ') }}</p>
    @endif

    <div class="grid" style="margin: 16px 0;">
        <div class="stat"><span class="muted">الرموز</span><b>{{ $licenses->count() }}</b></div>
        <div class="stat"><span class="muted">حواسيب مفعّلة</span><b>{{ $used->count() }}</b></div>
        <div class="stat"><span class="muted">الحد المسموح للأجهزة</span>
            @if ($university->max_devices)
                <b class="ltr">{{ $active }} / {{ $university->max_devices }}</b>
                <span class="muted">{{ $active >= $university->max_devices ? 'مكتمل، لن يُفعَّل حاسوب جديد' : 'متبقٍّ '.($university->max_devices - $active) }}</span>
            @else
                <b>بلا حد</b>
            @endif
        </div>
        <div class="stat"><span class="muted">رموز غير مستخدمة</span><b>{{ $free->count() }}</b></div>
        <div class="stat"><span class="muted">تحتاج تحديث</span><b>{{ $outdated }}</b>
            <span class="muted">آخر نسخة: <span class="ltr">{{ $latestBuild ?? '—' }}</span></span></div>
    </div>

    <div class="card">
        <h2>الحواسيب المفعّلة</h2>
        @if ($used->isEmpty())
            <p class="muted">لم يُفعَّل أي حاسوب بعد.</p>
        @else
            <div class="table-wrap">
                <table>
                    <thead>
                        <tr><th>الحاسوب</th><th>رقم الحاسوب</th><th>الرمز</th><th>النسخة المثبّتة</th><th>تاريخ التفعيل</th><th>آخر اتصال</th><th>عبر الإنترنت</th><th>الحالة</th><th></th></tr>
                    </thead>
                    <tbody>
                        @foreach ($used as $l)
                            <tr>
                                <td>{{ $l->machine_name ?: '—' }}
                                    @if ($l->last_ip) <div class="muted ltr">{{ $l->last_ip }}</div> @endif</td>
                                <td><code>{{ $l->machine_id }}</code></td>
                                <td><code data-copy="{{ $l->code }}">{{ $l->code }}</code></td>
                                <td>
                                    @if (! $l->installed_build) <span class="muted">غير معروفة</span>
                                    @elseif ($latestBuild && $l->installed_build < $latestBuild) <span class="tag amber ltr">{{ $l->installed_build }}</span> <span class="muted">قديمة</span>
                                    @else <span class="tag green ltr">{{ $l->installed_build }}</span>
                                    @endif
                                </td>
                                <td class="muted">{{ $l->activated_at?->format('Y-m-d H:i') }}</td>
                                <td class="muted">{{ $l->last_seen_at?->locale('ar')->diffForHumans() ?? '—' }}</td>
                                <td>
                                    @if ($l->tunnelOnline())
                                        <a class="tag green" href="{{ $l->tunnelLink() }}" target="_blank" rel="noopener">فتح النظام</a>
                                        @if ($l->tunnel_panel_url) <a class="tag" href="{{ $l->tunnelLink('control') }}" target="_blank" rel="noopener">لوحة التشغيل</a> @endif
                                    @elseif ($l->tunnel_slug) <span class="muted">غير متصل</span>
                                    @else <span class="muted">—</span>
                                    @endif
                                </td>
                                <td>@if ($l->revoked_at) <span class="tag red">موقوف</span> @else <span class="tag green">فعّال</span> @endif</td>
                                <td>@include('licensing.code-actions', ['license' => $l])</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </div>

    <div class="card">
        <h2>رموز التفعيل غير المستخدمة</h2>
        <form method="POST" action="{{ route('licensing.codes.store', $university) }}" class="row" style="margin-bottom: 14px;">
            @csrf
            <label style="flex: 0 1 120px;">العدد <input type="number" name="count" value="1" min="1" max="50" required></label>
            <label>ملاحظة <input name="notes" placeholder="مثلاً: حاسوب الاستقبال"></label>
            <button class="btn-primary" type="submit">إنشاء رموز</button>
        </form>
        @error('count') <div class="error">{{ $message }}</div> @enderror
        @if ($free->isEmpty())
            <p class="muted">لا توجد رموز غير مستخدمة.</p>
        @else
            <div class="table-wrap">
                <table>
                    <thead><tr><th>الرمز</th><th>ملاحظة</th><th>أُنشئ</th><th>الحالة</th><th></th></tr></thead>
                    <tbody>
                        @foreach ($free as $l)
                            <tr>
                                <td><code data-copy="{{ $l->code }}" style="cursor: copy;" title="انقر للنسخ">{{ $l->code }}</code></td>
                                <td>{{ $l->notes }}</td>
                                <td class="muted">{{ $l->created_at?->format('Y-m-d') }}</td>
                                <td>@if ($l->revoked_at) <span class="tag red">موقوف</span> @else <span class="tag">جاهز</span> @endif</td>
                                <td>@include('licensing.code-actions', ['license' => $l])</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </div>

    <div class="card">
        <h2>بيانات الجامعة</h2>
        <form method="POST" action="{{ route('licensing.universities.update', $university) }}" class="row">
            @csrf @method('PATCH')
            <label>اسم الجامعة <input name="name" value="{{ old('name', $university->name) }}" required></label>
            <label>جهة الاتصال <input name="contact" value="{{ old('contact', $university->contact) }}"></label>
            <label style="flex: 0 1 150px;">عدد الأجهزة المسموح <input type="number" name="max_devices" value="{{ old('max_devices', $university->max_devices) }}" min="1" placeholder="بلا حد"></label>
            <label>ملاحظات <input name="notes" value="{{ old('notes', $university->notes) }}"></label>
            <button type="submit">حفظ</button>
        </form>
        <p class="muted" style="margin: 8px 0 0;">اتركه فارغاً بلا حد. عند الوصول إلى الحد يُرفض تفعيل أي حاسوب جديد، ويبقى المفعّل يعمل. تحرير رمز أو إيقافه يفرّغ مكاناً.</p>
        @error('name') <div class="error">{{ $message }}</div> @enderror
        @error('max_devices') <div class="error">{{ $message }}</div> @enderror
        @if ($used->isEmpty())
            <form method="POST" action="{{ route('licensing.universities.destroy', $university) }}" data-confirm="حذف الجامعة وكل رموزها؟" style="margin-top: 14px;">
                @csrf @method('DELETE')
                <button class="btn-danger btn-small" type="submit">حذف الجامعة</button>
            </form>
        @endif
    </div>
@endsection
