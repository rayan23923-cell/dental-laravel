@extends('licensing.layout')

@section('title', 'حسابي')

@section('content')
    <form class="card" method="POST" action="{{ route('licensing.account.update') }}" style="max-width: 460px;">
        @csrf @method('PUT')
        <h1 style="margin-bottom: 14px;">حسابي</h1>
        <p class="muted" style="margin: 0 0 12px;">اسم المستخدم: <b class="ltr">{{ $admin->username }}</b></p>
        <label>الاسم <input name="name" value="{{ old('name', $admin->name) }}" required></label>
        @error('name') <div class="error">{{ $message }}</div> @enderror
        <label style="margin-top: 12px;">كلمة المرور الجديدة (اتركها فارغة للإبقاء على الحالية)
            <input type="password" name="password" autocomplete="new-password"></label>
        @error('password') <div class="error">{{ $message }}</div> @enderror
        <label style="margin-top: 12px;">تأكيد كلمة المرور الجديدة
            <input type="password" name="password_confirmation" autocomplete="new-password"></label>
        <label style="margin-top: 12px;">كلمة المرور الحالية
            <input type="password" name="current_password" autocomplete="current-password" required></label>
        @error('current_password') <div class="error">{{ $message }}</div> @enderror
        <button class="btn-primary" type="submit" style="margin-top: 16px;">حفظ</button>
    </form>
@endsection
