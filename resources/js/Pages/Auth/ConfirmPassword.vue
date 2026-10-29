<script setup>
import TgSpinner from '@/Components/TgSpinner.vue';
import AuthField from '@/Components/AuthField.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const form = useForm({
    password: '',
});

const submit = () => {
    form.post(route('password.confirm'), {
        onFinish: () => form.reset(),
    });
};
</script>

<template>
    <GuestLayout>
        <Head :title="t('authPages.confirmPasswordTitle')" />

        <h2 class="text-lg font-semibold text-content">{{ t('authPages.confirmPasswordHeading') }}</h2>
        <p class="mt-1 text-sm leading-relaxed text-muted">{{ t('authPages.confirmPasswordDescription') }}</p>

        <form @submit.prevent="submit" class="mt-6 space-y-5">
            <AuthField
                id="password"
                v-model="form.password"
                :label="t('authPages.passwordLabel')"
                type="password"
                icon="lock"
                placeholder="••••••••"
                autocomplete="current-password"
                :error="form.errors.password"
                required
                autofocus
            />

            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-3 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            >
                <TgSpinner v-if="form.processing" :size="20" />
                <Icon v-else name="lock_open" />
                {{ form.processing ? t('authPages.confirming') : t('authPages.confirmButton') }}
            </button>
        </form>
    </GuestLayout>
</template>
