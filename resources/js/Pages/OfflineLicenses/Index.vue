<script setup>
/**
 * Activation codes for offline copies (2026-10-17, by request): each code
 * activates one copy once and is then tied to that computer. See
 * App\Http\Controllers\OfflineLicenseController.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import InputError from '@/Components/InputError.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    licenses: { type: Array, default: () => [] },
    latest: { type: Object, default: null },
});
const page = usePage();

const input = 'rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500';
const form = useForm({ university: '', count: 1, notes: '' });
const create = () => form.post(route('offline-licenses.store'), { preserveScroll: true, onSuccess: () => form.reset('count', 'notes') });

const search = ref('');
const shown = computed(() => {
    const q = search.value.trim().toLowerCase();
    return q ? props.licenses.filter((l) => [l.code, l.university, l.notes, l.machine_name, l.machine_id].some((v) => (v ?? '').toLowerCase().includes(q))) : props.licenses;
});
const counts = computed(() => ({
    all: props.licenses.length,
    used: props.licenses.filter((l) => l.machine_id).length,
}));

const act = (license, action) => {
    if (action === 'release' && !window.confirm(t('offlineLicenses.confirmRelease'))) return;
    router.patch(route('offline-licenses.update', license.id), { action }, { preserveScroll: true });
};
const remove = (license) => {
    if (!window.confirm(t('offlineLicenses.confirmDelete'))) return;
    router.delete(route('offline-licenses.destroy', license.id), { preserveScroll: true });
};

const copied = ref(null);
const copy = async (code) => {
    try {
        await navigator.clipboard.writeText(code);
        copied.value = code;
        setTimeout(() => (copied.value = null), 1500);
    } catch {
        window.prompt(t('offlineLicenses.copy'), code);
    }
};
const date = (value) => (value ? new Date(value).toLocaleString('ar') : '');
</script>

<template>
    <Head :title="t('offlineLicenses.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('offlineLicenses.title') }}</h2>
        </template>

        <div class="py-8">
            <div class="mx-auto max-w-4xl space-y-6 px-4 sm:px-6 lg:px-8">
                <p v-if="page.props.flash?.success" class="rounded-md bg-emerald-50 px-4 py-2 text-sm text-emerald-700">{{ page.props.flash.success }}</p>

                <div class="rounded-lg bg-white p-4 shadow-sm">
                    <p class="text-sm text-gray-600">{{ t('offlineLicenses.intro') }}</p>
                    <p class="mt-2 text-sm text-gray-700">
                        <template v-if="latest">
                            {{ t('offlineLicenses.latest', { n: latest.build }) }}
                            <a :href="route('backup.offline-server', 'server')" class="font-medium text-indigo-600 hover:underline">{{ t('offlineLicenses.download') }}</a>
                        </template>
                        <template v-else>{{ t('offlineLicenses.noBuild') }}</template>
                    </p>
                </div>

                <form class="space-y-3 rounded-lg bg-white p-4 shadow-sm" @submit.prevent="create">
                    <div class="text-sm font-semibold text-gray-800">{{ t('offlineLicenses.newCodes') }}</div>
                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-4">
                        <label class="text-xs text-gray-600 sm:col-span-2">
                            {{ t('offlineLicenses.university') }}
                            <input v-model="form.university" type="text" required maxlength="255" class="mt-1 block w-full" :class="input" />
                            <InputError :message="form.errors.university" />
                        </label>
                        <label class="text-xs text-gray-600">
                            {{ t('offlineLicenses.count') }}
                            <input v-model.number="form.count" type="number" min="1" max="50" required class="mt-1 block w-full" :class="input" />
                            <InputError :message="form.errors.count" />
                        </label>
                        <label class="text-xs text-gray-600">
                            {{ t('offlineLicenses.notes') }}
                            <input v-model="form.notes" type="text" maxlength="255" class="mt-1 block w-full" :class="input" />
                        </label>
                    </div>
                    <PrimaryButton :disabled="form.processing" class="gap-1"><Icon name="key" size="text-[18px]" />{{ t('offlineLicenses.create') }}</PrimaryButton>
                </form>

                <div class="rounded-lg bg-white p-4 shadow-sm">
                    <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
                        <div class="text-sm text-gray-600">{{ t('offlineLicenses.counts', counts) }}</div>
                        <input v-model="search" type="search" :placeholder="t('offlineLicenses.search')" class="w-full sm:w-64" :class="input" />
                    </div>
                    <p v-if="!shown.length" class="py-6 text-center text-sm text-gray-500">{{ t('offlineLicenses.empty') }}</p>
                    <div class="divide-y divide-gray-100">
                        <div v-for="l in shown" :key="l.id" class="flex flex-wrap items-center gap-x-4 gap-y-2 py-3">
                            <div class="min-w-0 flex-1">
                                <div class="flex flex-wrap items-center gap-2">
                                    <code dir="ltr" class="whitespace-nowrap font-mono text-base font-semibold tracking-wider text-gray-900">{{ l.code }}</code>
                                    <button type="button" class="text-gray-400 hover:text-indigo-600" :title="t('offlineLicenses.copy')" @click="copy(l.code)">
                                        <Icon :name="copied === l.code ? 'check' : 'content_copy'" size="text-[18px]" />
                                    </button>
                                    <span v-if="l.revoked_at" class="rounded-full bg-red-100 px-2 py-0.5 text-xs text-red-700">{{ t('offlineLicenses.revoked') }}</span>
                                    <span v-else-if="l.machine_id" class="rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-800">{{ t('offlineLicenses.used') }}</span>
                                    <span v-else class="rounded-full bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700">{{ t('offlineLicenses.unused') }}</span>
                                </div>
                                <div class="mt-1 text-sm text-gray-700">{{ l.university }}<span v-if="l.notes" class="text-gray-500"> · {{ l.notes }}</span></div>
                                <div v-if="l.machine_id" class="mt-1 text-xs text-gray-500">
                                    {{ t('offlineLicenses.machine') }} <span dir="ltr" class="font-mono">{{ l.machine_id }}</span><span v-if="l.machine_name"> ({{ l.machine_name }})</span>
                                    · {{ t('offlineLicenses.activatedAt') }} {{ date(l.activated_at) }}
                                    <template v-if="l.last_seen_at"> · {{ t('offlineLicenses.lastSeen') }} {{ date(l.last_seen_at) }}</template>
                                </div>
                            </div>
                            <div class="flex shrink-0 flex-wrap gap-2 text-xs">
                                <button v-if="l.machine_id" type="button" class="rounded-md border border-gray-300 px-2 py-1 text-gray-700 hover:bg-gray-50" @click="act(l, 'release')">{{ t('offlineLicenses.release') }}</button>
                                <button v-if="!l.revoked_at" type="button" class="rounded-md border border-red-200 px-2 py-1 text-red-600 hover:bg-red-50" @click="act(l, 'revoke')">{{ t('offlineLicenses.revoke') }}</button>
                                <button v-else type="button" class="rounded-md border border-gray-300 px-2 py-1 text-gray-700 hover:bg-gray-50" @click="act(l, 'restore')">{{ t('offlineLicenses.restore') }}</button>
                                <button type="button" class="rounded-md px-2 py-1 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="remove(l)"><Icon name="delete" size="text-[18px]" /></button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
