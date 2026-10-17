@extends('licensing.layout')

@section('title', 'تسجيل الدخول')

@section('content')
    <form class="card" method="POST" action="{{ route('licensing.login.store') }}" style="max-width: 400px; margin: 60px auto;">
        @csrf
        <h1>بوابة التراخيص</h1>
        <p class="muted" style="margin: 0 0 16px;">إدارة الجامعات ورموز التفعيل والحواسيب المفعّلة للنسخة الأوفلاين.</p>
        <label>اسم المستخدم
            <input name="username" value="{{ old('username') }}" autocomplete="username" required autofocus>
        </label>
        @error('username') <div class="error">{{ $message }}</div> @enderror
        <label style="margin-top: 12px;">كلمة المرور
            <input type="password" name="password" autocomplete="current-password" required>
        </label>
        <label style="margin-top: 12px; display: flex; gap: 8px; align-items: center;">
            <input type="checkbox" name="remember" value="1" style="width: auto; margin: 0;"> تذكرني
        </label>
        <button class="btn-primary" type="submit" style="width: 100%; margin-top: 16px;">دخول</button>
    </form>
@endsection
