<script setup>
import TgSpinner from '@/Components/TgSpinner.vue';
import AuthField from '@/Components/AuthField.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
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
    form.post(route('password.store'), {
        onFinish: () => form.reset('otp', 'password', 'password_confirmation'),
    });
};
</script>

<template>
    <GuestLayout>
        <Head :title="t('authPages.resetPasswordTitle')" />

        <h2 class="text-lg font-semibold text-content">{{ t('authPages.resetPasswordHeading') }}</h2>
        <p class="mt-1 text-sm leading-relaxed text-muted">{{ t('authPages.resetPasswordDescription') }}</p>

        <div v-if="status" class="mt-5 rounded-xl border border-accent/40 bg-accent/10 px-4 py-3 text-sm text-accent">
            {{ status }}
        </div>

        <form @submit.prevent="submit" class="mt-6 space-y-5">
            <AuthField
                id="email"
                v-model="form.email"
                :label="t('authPages.emailLabel')"
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
                :label="t('authPages.otpLabel')"
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
                :label="t('authPages.newPasswordLabel')"
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
                :label="t('authPages.confirmPasswordFieldLabel')"
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
                <TgSpinner v-if="form.processing" :size="20" />
                <Icon v-else name="check_circle" />
                {{ form.processing ? t('authPages.saving') : t('authPages.savePasswordButton') }}
            </button>

            <Link :href="route('password.request')" class="block text-center text-sm text-muted transition hover:text-content">
                {{ t('authPages.resendOtpLink') }}
            </Link>

            <Link :href="route('login')" class="block text-center text-sm text-muted transition hover:text-content">
                {{ t('authPages.backToLogin') }}
            </Link>
        </form>
    </GuestLayout>
</template>
