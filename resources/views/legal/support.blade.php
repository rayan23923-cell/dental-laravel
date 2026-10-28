@extends('legal.layout')

@section('title', 'الدعم والتواصل')

@section('content')
    <p>لأي مشكلة في الدخول أو استخدام التطبيق، تواصل مع إدارة العيادة:</p>
    <ul>
        @if($clinic->clinic_phone)<li>الهاتف: <a href="tel:{{ $clinic->clinic_phone }}" dir="ltr">{{ $clinic->clinic_phone }}</a></li>@endif
        @if($clinic->clinic_email)<li>البريد: <a href="mailto:{{ $clinic->clinic_email }}">{{ $clinic->clinic_email }}</a></li>@endif
        @if($clinic->clinic_address)<li>العنوان: {{ $clinic->clinic_address }}</li>@endif
        @unless($clinic->clinic_phone || $clinic->clinic_email || $clinic->clinic_address)
            <li>مكتب إدارة العيادة في الكلية.</li>
        @endunless
    </ul>

    <h2>أسئلة شائعة</h2>
    <p><strong>كيف أحصل على حساب؟</strong><br>تُنشئ إدارة العيادة حسابات الطلاب والموظفين، ولا يوجد تسجيل ذاتي.</p>
    <p><strong>نسيت كلمة المرور.</strong><br>اضغط «نسيت كلمة المرور» في شاشة الدخول لاستلام رمز على بريدك، أو راجع الإدارة.</p>
    <p><strong>كيف أحذف حسابي؟</strong><br>من التطبيق: حسابي ← حذف حسابي، أو من صفحة <a href="{{ route('account-deletion.show') }}">طلب حذف الحساب</a>.</p>
@endsection
