@extends('licensing.layout')

@section('title', 'الجامعات')

@section('content')
    <h1>الجامعات</h1>
    <p class="muted" style="margin: 0 0 16px;">
        آخر نسخة أوفلاين على الاستضافة:
        @if ($latest) <b class="ltr">{{ $latest['build'] }}</b> @else لا توجد بعد @endif
    </p>

    <div class="card">
        <h2>إضافة جامعة</h2>
        <form method="POST" action="{{ route('licensing.universities.store') }}" class="row">
            @csrf
            <label>اسم الجامعة <input name="name" value="{{ old('name') }}" required></label>
            <label>جهة الاتصال <input name="contact" value="{{ old('contact') }}" placeholder="اسم أو رقم هاتف"></label>
            <label>ملاحظات <input name="notes" value="{{ old('notes') }}"></label>
            <button class="btn-primary" type="submit">إضافة</button>
        </form>
        @error('name') <div class="error">{{ $message }}</div> @enderror
    </div>

    <div class="card">
        @if ($universities->isEmpty())
            <p class="muted">لا توجد جامعات بعد.</p>
        @else
            <div class="table-wrap">
                <table>
                    <thead>
                        <tr><th>الجامعة</th><th>الرموز</th><th>حواسيب مفعّلة</th><th>رموز غير مستخدمة</th><th>موقوفة</th><th>آخر اتصال</th></tr>
                    </thead>
                    <tbody>
                        @foreach ($universities as $u)
                            <tr>
                                <td><a href="{{ route('licensing.universities.show', $u) }}"><b>{{ $u->name }}</b></a>
                                    @if ($u->contact) <div class="muted">{{ $u->contact }}</div> @endif</td>
                                <td>{{ $u->licenses_count }}</td>
                                <td>{{ $u->used_count }}</td>
                                <td>{{ $u->licenses_count - $u->used_count }}</td>
                                <td>{{ $u->revoked_count }}</td>
                                <td class="muted">{{ $u->licenses_max_last_seen_at ? \Illuminate\Support\Carbon::parse($u->licenses_max_last_seen_at)->locale('ar')->diffForHumans() : '—' }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </div>
@endsection
