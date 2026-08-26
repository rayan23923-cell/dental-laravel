<script setup>
import AuthField from '@/Components/AuthField.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';

defineProps({
    status: { type: String },
});

const form = useForm({
    email: '',
});

const submit = () => {
    form.post(route('password.email'));
};
</script>

<template>
    <GuestLayout>
        <Head title="استعادة كلمة المرور" />

        <h2 class="text-lg font-semibold text-content">استعادة كلمة المرور</h2>
        <p class="mt-1 text-sm leading-relaxed text-muted">
            أدخل بريدك الإلكتروني وسنرسل لك رابطاً لتعيين كلمة مرور جديدة.
        </p>

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
                placeholder="name@clinic.local"
                autocomplete="username"
                :error="form.errors.email"
                required
                autofocus
            />

            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-3 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            >
                <Icon :name="form.processing ? 'progress_activity' : 'send'" :class="form.processing ? 'animate-spin' : ''" />
                {{ form.processing ? 'جارٍ الإرسال…' : 'إرسال الرابط' }}
            </button>

            <Link :href="route('login')" class="block text-center text-sm text-muted transition hover:text-content">
                العودة لتسجيل الدخول
            </Link>
        </form>
    </GuestLayout>
</template>
