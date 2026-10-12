<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="utf-8">
    <title>{{ $clinicName }}</title>
</head>
<body style="margin:0;padding:24px;background:#f4f5f7;font-family:Tahoma,Arial,sans-serif;color:#1f2937;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:12px;">
        <tr>
            <td style="padding:28px 28px 8px;">
                <h2 style="margin:0 0 6px;font-size:20px;">{{ $clinicName }}</h2>
                <p style="margin:0;color:#6b7280;font-size:14px;">
                    {{ $accountType === 'doctor' ? 'تم إنشاء حساب الطبيب الخاص بك' : 'تم إنشاء حسابك في النظام' }}
                </p>
            </td>
        </tr>
        <tr>
            <td style="padding:16px 28px;">
                <p style="margin:0 0 16px;font-size:15px;">مرحباً {{ $name }}،</p>
                <p style="margin:0 0 16px;font-size:15px;">هذه بيانات الدخول إلى حسابك:</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;">
                    <tr>
                        <td style="padding:12px 16px;color:#6b7280;font-size:14px;">اسم المستخدم</td>
                        <td style="padding:12px 16px;font-size:15px;font-weight:bold;direction:ltr;text-align:left;">{{ $username }}</td>
                    </tr>
                    <tr>
                        <td style="padding:12px 16px;color:#6b7280;font-size:14px;border-top:1px solid #e5e7eb;">كلمة المرور</td>
                        <td style="padding:12px 16px;font-size:15px;font-weight:bold;direction:ltr;text-align:left;border-top:1px solid #e5e7eb;">{{ $password }}</td>
                    </tr>
                </table>
                <p style="margin:24px 0;text-align:center;">
                    <a href="{{ $loginUrl }}" style="display:inline-block;background:#0095f6;color:#ffffff;text-decoration:none;padding:12px 28px;border-radius:8px;font-size:15px;">تسجيل الدخول</a>
                </p>
                <p style="margin:0 0 8px;font-size:13px;color:#b45309;">لأمان حسابك، غيّر كلمة المرور بعد أول تسجيل دخول.</p>
                <p style="margin:0;font-size:13px;color:#6b7280;">إذا لم تكن تتوقع هذه الرسالة فتجاهلها.</p>
            </td>
        </tr>
        <tr>
            <td style="padding:16px 28px 28px;font-size:12px;color:#9ca3af;direction:ltr;text-align:left;">
                Your account was created. Username: {{ $username }} — Password: {{ $password }} — Sign in: {{ $loginUrl }}
            </td>
        </tr>
    </table>
</body>
</html>
