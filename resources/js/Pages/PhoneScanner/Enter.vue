<script setup>
/**
 * The phone types the six-digit code shown on the computer (2026-10-12):
 * the server resolves it to the pairing's scanner page. No login needed.
 */
import Icon from '@/Components/Icon.vue';
import InputError from '@/Components/InputError.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const form = useForm({ code: '' });

const submit = () => {
    form.code = form.code.replace(/\D/g, '');
    form.post(route('phone-scanner.resolve'));
};
</script>

<template>
    <Head :title="t('phoneScanner.enterTitle')" />

    <div class="flex min-h-screen items-center justify-center bg-slate-900 px-4" dir="rtl">
        <form @submit.prevent="submit" class="w-full max-w-sm rounded-2xl bg-white p-6 text-center shadow-xl">
            <Icon name="qr_code_scanner" class="text-5xl text-indigo-600" />
            <h1 class="mt-2 text-xl font-bold text-gray-900">{{ t('phoneScanner.enterHeading') }}</h1>
            <p class="mt-1 text-sm text-gray-500">{{ t('phoneScanner.enterHint') }}</p>

            <label for="code" class="sr-only">{{ t('phoneScanner.codeLabel') }}</label>
            <input
                id="code"
                v-model="form.code"
                type="text"
                inputmode="numeric"
                pattern="[0-9]*"
                maxlength="6"
                autocomplete="one-time-code"
                dir="ltr"
                class="mt-6 block w-full rounded-xl border-gray-300 text-center font-mono text-4xl tracking-[0.4em] focus:border-indigo-500 focus:ring-indigo-500"
                autofocus
                required
            />
            <InputError class="mt-2" :message="form.errors.code" />

            <button
                type="submit"
                :disabled="form.processing || form.code.length < 6"
                class="mt-6 w-full rounded-xl bg-indigo-600 py-3 text-lg font-semibold text-white hover:bg-indigo-700 disabled:opacity-50"
            >
                {{ t('phoneScanner.connect') }}
            </button>
        </form>
    </div>
</template>
