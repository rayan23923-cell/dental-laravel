@extends('legal.layout')

@section('title', 'طلب حذف الحساب')

@section('content')
    @if(session('sent'))
        <p class="notice">وصل طلبك إلى إدارة العيادة. سيُحذف الحساب خلال 30 يومًا، وقد نتواصل معك للتأكد من هويتك.</p>
    @endif

    <p>
        الحسابات في هذا النظام تُنشئها إدارة العيادة/الكلية. لحذف حسابك أرسل الطلب
        من داخل التطبيق (حسابي ← حذف حسابي)، أو من النموذج أدناه.
    </p>

    <h2>ما الذي يُحذف</h2>
    <ul>
        <li>بيانات الحساب: الاسم، اسم المستخدم، البريد الإلكتروني، رقم الهاتف، الصورة الشخصية، وكلمة المرور.</li>
        <li>رموز الإشعارات وبيانات جلسات الدخول والأجهزة.</li>
    </ul>

    <h2>ما الذي يبقى</h2>
    <p>
        السجلات السريرية للمرضى التي أُدخلت بواسطة الحساب تبقى ضمن الأرشيف الطبي
        والأكاديمي للكلية، لأنها سجلات مرضى وليست بيانات شخصية لصاحب الحساب.
    </p>

    <h2>إرسال الطلب</h2>
    <form method="POST" action="{{ route('account-deletion.store') }}">
        @csrf
        <label>اسم المستخدم أو البريد الإلكتروني للحساب
            <input name="identifier" value="{{ old('identifier') }}" required maxlength="191">
        </label>
        @error('identifier')<p class="error">{{ $message }}</p>@enderror
        <label>رقم هاتف أو بريد للتواصل (اختياري)
            <input name="contact" value="{{ old('contact') }}" maxlength="191">
        </label>
        <label>السبب (اختياري)
            <textarea name="reason" rows="3" maxlength="2000">{{ old('reason') }}</textarea>
        </label>
        <button type="submit">إرسال طلب الحذف</button>
    </form>
@endsection
