<script setup>
// Our own error page for in-app visits (2026-11-01, by request): Arabic and
// English, a back button, no framework page. Full page loads get the same
// page from resources/views/errors/page.blade.php.
import { Head, router } from '@inertiajs/vue3';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({ status: { type: Number, default: 500 } });
const { t, locale } = useI18n();

const known = [403, 404, 405, 419, 429, 500, 503];
const key = computed(() => (known.includes(props.status) ? props.status : props.status >= 500 ? 500 : 404));
const title = computed(() => t(`errors.title${key.value}`));
const rtl = computed(() => locale.value === 'ar');

const goBack = () => {
    if (window.history.length > 1) window.history.back();
    else router.visit('/');
};
const reload = () => window.location.reload();
const toggleLang = () => {
    locale.value = locale.value === 'ar' ? 'en' : 'ar';
};
</script>

<template>
    <Head :title="`${status} · ${title}`" />
    <div class="flex min-h-screen items-center justify-center bg-gray-100 p-4" :dir="rtl ? 'rtl' : 'ltr'">
        <div class="w-full max-w-md rounded-2xl border border-gray-200 bg-white px-6 py-8 text-center shadow-sm">
            <div class="text-6xl font-extrabold tracking-wider text-teal-700">{{ status }}</div>
            <h1 class="mt-4 text-xl font-bold text-gray-900">{{ title }}</h1>
            <p class="mt-2 leading-7 text-gray-500">{{ t(`errors.text${key}`) }}</p>
            <div class="mt-6 flex flex-wrap justify-center gap-2">
                <button type="button" class="rounded-xl bg-teal-700 px-5 py-3 font-semibold text-white hover:bg-teal-800" @click="goBack">
                    {{ rtl ? '→' : '←' }} {{ t('errors.goBack') }}
                </button>
                <button
                    v-if="status === 419"
                    type="button"
                    class="rounded-xl bg-teal-50 px-5 py-3 font-semibold text-gray-800 hover:bg-teal-100"
                    @click="reload"
                >
                    {{ t('errors.refresh') }}
                </button>
                <a href="/" class="rounded-xl bg-teal-50 px-5 py-3 font-semibold text-gray-800 hover:bg-teal-100">{{ t('errors.home') }}</a>
            </div>
            <button type="button" class="mt-5 text-sm text-gray-500 underline" @click="toggleLang">
                {{ rtl ? 'English' : 'العربية' }}
            </button>
        </div>
    </div>
</template>
