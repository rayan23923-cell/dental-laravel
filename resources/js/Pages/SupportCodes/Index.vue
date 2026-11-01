<script setup>
/**
 * "بطاقات الرعاية" (2026-11-01, by request): generate one-time 5-digit
 * codes, print them as cards to cut out and hand out, and stop unused
 * ones. A code typed at registration makes the service and the lab test
 * free. See App\Support\SupportCodes.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatPager from '@/Components/ChatList/ChatPager.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { Head, Link, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    codes: Object,
    counts: Object,
    batches: Array,
    filters: Object,
    enabled: Boolean,
    maxBatch: Number,
    can: Object,
});
const page = usePage();

const genForm = useForm({ count: 50, note: '' });
const generate = () => genForm.post(route('support-codes.store'), { preserveScroll: true, onSuccess: () => genForm.reset('note') });

const search = ref(props.filters.search ?? '');
const reload = (changes) => {
    router.get(route('support-codes.index'), { ...props.filters, ...changes }, { preserveState: true, preserveScroll: true, replace: true });
};
let timer = null;
watch(search, (v) => {
    clearTimeout(timer);
    timer = setTimeout(() => reload({ search: v || undefined, page: undefined }), 350);
});

const tiles = computed(() => [
    { key: null, label: t('supportCodes.all'), n: props.counts.all, icon: 'style', tone: 'bg-slate-600' },
    { key: 'active', label: t('supportCodes.active'), n: props.counts.active, icon: 'verified', tone: 'bg-teal-600' },
    { key: 'used', label: t('supportCodes.used'), n: props.counts.used, icon: 'task_alt', tone: 'bg-sky-600' },
    { key: 'disabled', label: t('supportCodes.disabled'), n: props.counts.disabled, icon: 'block', tone: 'bg-rose-600' },
]);
const statusChip = {
    active: { tone: 'teal', icon: 'verified' },
    used: { tone: 'sky', icon: 'task_alt' },
    disabled: { tone: 'rose', icon: 'block' },
};

const selected = ref([]);
watch(() => props.codes.data, () => (selected.value = selected.value.filter((id) => props.codes.data.some((c) => c.id === id))));
const selectable = computed(() => props.codes.data.filter((c) => c.status !== 'used'));
const allSelected = computed(() => selectable.value.length > 0 && selectable.value.every((c) => selected.value.includes(c.id)));
const toggleAll = () => {
    selected.value = allSelected.value ? [] : selectable.value.map((c) => c.id);
};

const setDisabled = (disabled, ids = selected.value, batch = null) => {
    if (disabled && !confirm(batch ? t('supportCodes.disableBatchConfirm', { batch }) : t('supportCodes.disableConfirm', { n: ids.length }))) return;
    router.post(route('support-codes.status'), { ids, batch, disabled }, { preserveScroll: true, onSuccess: () => (selected.value = []) });
};

const cardsUrl = (params) => route('support-codes.cards', { ...params, autoprint: 1 });
const printSelected = computed(() => {
    const ids = props.codes.data.filter((c) => selected.value.includes(c.id) && c.status === 'active').map((c) => c.id);
    return ids.length ? cardsUrl({ ids: ids.join(',') }) : null;
});
const currentBatch = computed(() => props.batches.find((b) => b.batch === props.filters.batch) ?? null);
const fmt = (d) => (d ? new Date(d).toLocaleString('en-GB', { dateStyle: 'short', timeStyle: 'short' }) : '—');
</script>

<template>
    <Head :title="t('supportCodes.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="flex items-center gap-2 text-xl font-semibold leading-tight text-gray-800">
                    <Icon name="volunteer_activism" class="text-teal-700" />{{ t('supportCodes.title') }}
                </h2>
                <ChatAddButton v-if="can.settings" :label="t('supportCodes.openSettings')" icon="tune" secondary :href="route('patient-registrations.settings')" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-5xl space-y-6 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">{{ page.props.flash.success }}</div>
                <div v-if="!enabled" class="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-amber-50 p-4 text-sm text-amber-800">
                    <span>{{ t('supportCodes.disabledFeature') }}</span>
                    <Link v-if="can.settings" :href="route('patient-registrations.settings')" class="font-semibold underline">{{ t('supportCodes.openSettings') }}</Link>
                </div>
                <p class="text-sm text-gray-600">{{ t('supportCodes.intro') }}</p>

                <!-- Generate -->
                <div v-if="can.generate" class="rounded-2xl bg-white p-6 shadow-sm ring-1 ring-gray-100">
                    <h3 class="mb-4 font-semibold text-gray-800">{{ t('supportCodes.generateHeading') }}</h3>
                    <form class="grid grid-cols-1 items-end gap-3 sm:grid-cols-[10rem_1fr_auto]" @submit.prevent="generate">
                        <div>
                            <InputLabel for="count" :value="t('supportCodes.count')" />
                            <TextInput id="count" v-model="genForm.count" type="number" min="1" :max="maxBatch" dir="ltr" class="mt-1 block w-full rounded-xl" required />
                            <InputError class="mt-2" :message="genForm.errors.count" />
                        </div>
                        <div>
                            <InputLabel for="note" :value="t('supportCodes.note')" />
                            <TextInput id="note" v-model="genForm.note" type="text" :placeholder="t('supportCodes.notePlaceholder')" class="mt-1 block w-full rounded-xl" />
                        </div>
                        <PrimaryButton class="rounded-full" :disabled="genForm.processing"><Icon name="add" class="ml-1" />{{ t('supportCodes.generate') }}</PrimaryButton>
                    </form>
                </div>

                <!-- Status tiles -->
                <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                    <button
                        v-for="tile in tiles"
                        :key="tile.label"
                        type="button"
                        class="flex items-center gap-3 rounded-2xl bg-white p-4 text-start shadow-sm ring-1 transition"
                        :class="(filters.status ?? null) === tile.key ? 'ring-2 ring-teal-500' : 'ring-gray-100 hover:ring-teal-200'"
                        @click="reload({ status: tile.key ?? undefined, page: undefined })"
                    >
                        <span class="flex h-10 w-10 items-center justify-center rounded-full text-white" :class="tile.tone"><Icon :name="tile.icon" /></span>
                        <span>
                            <span class="block text-xs text-gray-500">{{ tile.label }}</span>
                            <span class="block text-xl font-bold text-gray-900">{{ tile.n }}</span>
                        </span>
                    </button>
                </div>

                <!-- List -->
                <div class="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-gray-100">
                    <div class="flex flex-wrap items-center gap-2 border-b border-gray-100 p-4">
                        <TextInput v-model="search" type="search" inputmode="numeric" :placeholder="t('supportCodes.search')" dir="ltr" class="w-40 rounded-xl" />
                        <select
                            class="rounded-xl border-gray-300 text-sm shadow-sm focus:border-teal-500 focus:ring-teal-500"
                            :value="filters.batch ?? ''"
                            @change="reload({ batch: $event.target.value || undefined, page: undefined })"
                        >
                            <option value="">{{ t('supportCodes.allBatches') }}</option>
                            <option v-for="b in batches" :key="b.batch" :value="b.batch">
                                {{ t('supportCodes.batchOption', { batch: b.batch, active: b.active, total: b.total }) }}{{ b.note ? ' · ' + b.note : '' }}
                            </option>
                        </select>
                        <div class="ms-auto flex flex-wrap gap-2">
                            <template v-if="can.generate">
                                <a v-if="printSelected" :href="printSelected" target="_blank" class="inline-flex items-center gap-1 rounded-full bg-teal-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-teal-700">
                                    <Icon name="print" />{{ t('supportCodes.printSelected', { n: selected.length }) }}
                                </a>
                                <a v-else-if="currentBatch" :href="cardsUrl({ batch: currentBatch.batch })" target="_blank" class="inline-flex items-center gap-1 rounded-full bg-teal-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-teal-700">
                                    <Icon name="print" />{{ t('supportCodes.printBatch') }}
                                </a>
                                <a v-else :href="cardsUrl({})" target="_blank" class="inline-flex items-center gap-1 rounded-full border border-teal-600 px-3 py-1.5 text-sm font-semibold text-teal-700 hover:bg-teal-50">
                                    <Icon name="print" />{{ t('supportCodes.printActive') }}
                                </a>
                            </template>
                            <template v-if="can.disable">
                                <button v-if="selected.length" type="button" class="inline-flex items-center gap-1 rounded-full bg-rose-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-rose-700" @click="setDisabled(true)">
                                    <Icon name="block" />{{ t('supportCodes.disableSelected') }}
                                </button>
                                <button v-if="selected.length" type="button" class="inline-flex items-center gap-1 rounded-full border border-gray-300 px-3 py-1.5 text-sm font-semibold text-gray-700 hover:bg-gray-50" @click="setDisabled(false)">
                                    <Icon name="restart_alt" />{{ t('supportCodes.enableSelected') }}
                                </button>
                                <button v-if="!selected.length && currentBatch && currentBatch.active" type="button" class="inline-flex items-center gap-1 rounded-full border border-rose-500 px-3 py-1.5 text-sm font-semibold text-rose-600 hover:bg-rose-50" @click="setDisabled(true, [], currentBatch.batch)">
                                    <Icon name="block" />{{ t('supportCodes.disableBatch') }}
                                </button>
                            </template>
                        </div>
                    </div>

                    <div class="overflow-x-auto">
                        <table class="min-w-full divide-y divide-gray-100 text-sm">
                            <thead class="bg-gray-50 text-xs text-gray-500">
                                <tr>
                                    <th class="w-10 px-4 py-2"><input type="checkbox" :checked="allSelected" class="rounded border-gray-300 text-teal-600" @change="toggleAll" /></th>
                                    <th class="px-4 py-2 text-right">{{ t('supportCodes.code') }}</th>
                                    <th class="px-4 py-2 text-right">{{ t('supportCodes.status') }}</th>
                                    <th class="px-4 py-2 text-right">{{ t('supportCodes.batch') }}</th>
                                    <th class="px-4 py-2 text-right">{{ t('supportCodes.patient') }}</th>
                                    <th class="px-4 py-2 text-right">{{ t('supportCodes.createdAt') }}</th>
                                    <th class="px-4 py-2 text-right">{{ t('supportCodes.usedAt') }}</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="c in codes.data" :key="c.id" :class="selected.includes(c.id) ? 'bg-teal-50/50' : ''">
                                    <td class="px-4 py-2">
                                        <input v-if="c.status !== 'used'" v-model="selected" type="checkbox" :value="c.id" class="rounded border-gray-300 text-teal-600" />
                                    </td>
                                    <td class="px-4 py-2 font-mono text-base font-bold tracking-[0.25em] text-gray-900" dir="ltr" style="text-align: right">{{ c.code }}</td>
                                    <td class="px-4 py-2"><ChatChip :tone="statusChip[c.status].tone" :icon="statusChip[c.status].icon">{{ t('supportCodes.' + c.status) }}</ChatChip></td>
                                    <td class="px-4 py-2 text-gray-600">{{ c.batch }}<span v-if="c.note" class="text-xs text-gray-400"> · {{ c.note }}</span></td>
                                    <td class="px-4 py-2 text-gray-800">{{ c.patient?.name ?? '—' }}</td>
                                    <td class="px-4 py-2 text-gray-500" dir="ltr" style="text-align: right">{{ fmt(c.created_at) }}</td>
                                    <td class="px-4 py-2 text-gray-500" dir="ltr" style="text-align: right">{{ fmt(c.used_at) }}</td>
                                </tr>
                                <tr v-if="codes.data.length === 0">
                                    <td colspan="7" class="px-4 py-10 text-center text-gray-500">{{ t('supportCodes.empty') }}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                    <ChatPager :links="codes.links" />
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
