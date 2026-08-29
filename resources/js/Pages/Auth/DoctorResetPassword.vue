<script setup>
import AuthField from '@/Components/AuthField.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';


const props = defineProps({
    email: { type: String, default: '' },
    status: { type: String, default: null },
});

const form = useForm({
    email: props.email,
    otp: '',
    password: '',
    password_confirmation: '',
});

const submit = () => {
    form.post(route('doctor.password.store'), {
        onFinish: () => form.reset('otp', 'password', 'password_confirmation'),
    });
};
</script>

<template>
    <GuestLayout>
        <Head title="تعيين كلمة مرور جديدة" />

        <h2 class="text-lg font-semibold text-content">تعيين كلمة مرور جديدة</h2>
        <p class="mt-1 text-sm leading-relaxed text-muted">أدخل رمز التحقق الذي وصلك عبر البريد الإلكتروني، ثم اختر كلمة مرور قوية لحسابك.</p>

        <div v-if="status" class="mt-5 rounded-xl border border-accent/40 bg-accent/10 px-4 py-3 text-sm text-accent">
            {{ status }}
        </div>

        <form @submit.prevent="submit" class="mt-6 space-y-5">
            <AuthField
                id="email"
                v-model="form.email"
                label="البريد الإلكتروني"
                type="email"
                icon="mail"
                autocomplete="username"
                :error="form.errors.email"
                required
                readonly
            />

            <AuthField
                id="otp"
                v-model="form.otp"
                label="رمز التحقق"
                type="text"
                icon="pin"
                placeholder="123456"
                autocomplete="one-time-code"
                :error="form.errors.otp"
                required
                autofocus
            />

            <AuthField
                id="password"
                v-model="form.password"
                label="كلمة المرور الجديدة"
                type="password"
                icon="lock"
                placeholder="••••••••"
                autocomplete="new-password"
                :error="form.errors.password"
                required
            />

            <AuthField
                id="password_confirmation"
                v-model="form.password_confirmation"
                label="تأكيد كلمة المرور"
                type="password"
                icon="lock_reset"
                placeholder="••••••••"
                autocomplete="new-password"
                :error="form.errors.password_confirmation"
                required
            />

            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-3 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            >
                <Icon :name="form.processing ? 'progress_activity' : 'check_circle'" :class="form.processing ? 'animate-spin' : ''" />
                {{ form.processing ? 'جارٍ الحفظ…' : 'حفظ كلمة المرور' }}
            </button>

            <Link :href="route('doctor.password.request')" class="block text-center text-sm text-muted transition hover:text-content">
                لم يصلك الرمز؟ إعادة الإرسال
            </Link>

            <Link :href="route('login')" class="block text-center text-sm text-muted transition hover:text-content">
                العودة لتسجيل الدخول
            </Link>
        </form>
    </GuestLayout>
</template>
