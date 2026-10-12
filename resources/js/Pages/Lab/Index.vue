<script setup>
/**
 * "المختبر" — web twin of the Flutter lab screen (2026-10-11). Lab staff
 * scan a patient's ticket QR (or search by name/phone, or pick from the
 * pending list) and record the infectious-disease screening result:
 * "سليم" (clear) or "غير سليم" (flagged). Until "سليم" is recorded,
 * `PatientScreeningGate` blocks payment and task-starting server-side.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import Modal from '@/Components/Modal.vue';
import QrScanner from '@/Components/QrScanner.vue';
import { Head, Link, router } from '@inertiajs/vue3';
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';

const { t } = useI18n();
const props = defineProps({
    registrations: Object,
    counts: { type: Object, default: () => ({}) },
    filters: Object,
    canConfirm: Boolean,
    labFee: { type: [Number, String], default: null },
    currency: { type: String, default: '' },
    validityDays: { type: Number, default: 0 },
});

const statusTabs = [
    { key: 'pending', label: () => t('patientReg.screeningPending'), tone: 'amber' },
    { key: 'flagged', label: () => t('patientReg.screeningFlagged'), tone: 'red' },
    { key: 'clear', label: () => t('patientReg.screeningClear'), tone: 'green' },
    { key: 'all', label: () => t('lab.all'), tone: 'gray' },
];
const countFor = (key) =>
    key === 'all' ? Object.values(props.counts).reduce((a, b) => a + Number(b), 0) : Number(props.counts[key] ?? 0);

const search = ref(props.filters.search || '');
const go = (params) =>
    router.get(route('lab.index'), { status: props.filters.status, search: search.value || undefined, ...params }, { preserveState: true, replace: true });

let searchTimer;
const runSearch = () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => go({}), 300);
};

const badgeClass = (status) =>
    ({ clear: 'bg-green-100 text-green-800', flagged: 'bg-red-100 text-red-800' })[status] ?? 'bg-amber-100 text-amber-800';
const statusLabel = (status) =>
    ({ clear: t('patientReg.screeningClear'), flagged: t('patientReg.screeningFlagged') })[status] ?? t('patientReg.screeningPending');
const isPaid = (r) => !!r.lab_paid;
// The lab fee is taken with the result (2026-10-12): picking "سليم" or
// "غير سليم" records the payment and prints one paid slip (LabFeeGate).
const hasLabFee = computed(() => props.labFee !== null && props.labFee !== '');
const labFeeText = computed(() => `${Number(props.labFee).toLocaleString()} ${props.currency ?? ''}`.trim());
// A clear result from the last `validityDays` (same phone) is reused
// instead: no new screening and nothing to pay (LabFeeGate).
const canReuse = (r) => r.screening_status === 'pending' && !!r.previous_screening;
const feeDue = (r) => hasLabFee.value && !isPaid(r) && !canReuse(r);
const placeAndDay = (r) => [r.service?.name ?? '—', r.register_day?.name].filter(Boolean).join(' · ');
const fmtDate = (value) => (value ? new Date(value).toLocaleString('ar-IQ', { dateStyle: 'medium', timeStyle: 'short' }) : '—');

// --- Scan a ticket QR ---
const scanning = ref(false);
const scannerRef = ref(null);
const scanError = ref('');

const openScanner = async () => {
    scanError.value = '';
    scanning.value = true;
    await nextTick();
    scannerRef.value?.start();
};
const closeScanner = () => {
    scannerRef.value?.stop();
    scanning.value = false;
};
const onDecoded = async (text) => {
    scanError.value = '';
    try {
        const { data } = await axios.post(route('lab.scan'), { payload: text });
        closeScanner();
        selected.value = data.data;
    } catch (e) {
        scanError.value = e?.response?.data?.message ?? t('payments.qrReadFailed');
    }
};

// --- Record a result ---
const selected = ref(null);
const submitting = ref(false);
const resultError = ref('');

// Saving a result prints the lab slip (result, paid fee, patient QR). The tab is
// opened before the request, while still inside the click, so browsers
// don't block it as a pop-up; it is pointed at the slip once saved.
const openPrint = (id, win) => {
    const url = route('lab.print', { patientRegistration: id, autoprint: 1 });
    if (win) win.location.href = url;
    else window.open(url, '_blank');
};

const reuse = async () => {
    submitting.value = true;
    resultError.value = '';
    const printWindow = window.open('', '_blank');
    try {
        const id = selected.value.id;
        await axios.post(route('lab.reuse', id));
        openPrint(id, printWindow);
        selected.value = null;
        router.reload({ only: ['registrations', 'counts'] });
    } catch (e) {
        printWindow?.close();
        resultError.value = e?.response?.data?.message ?? t('lab.recordFailed');
    } finally {
        submitting.value = false;
    }
};

const record = async (status) => {
    submitting.value = true;
    resultError.value = '';
    const printWindow = window.open('', '_blank');
    try {
        const id = selected.value.id;
        await axios.post(route('patient-registrations.screening', id), { screening_status: status });
        openPrint(id, printWindow);
        selected.value = null;
        router.reload({ only: ['registrations', 'counts'] });
    } catch (e) {
        printWindow?.close();
        resultError.value = e?.response?.data?.message ?? t('lab.recordFailed');
    } finally {
        submitting.value = false;
    }
};
</script>

<template>
    <Head :title="t('dashboard.lab')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex flex-wrap items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">
                    <Icon name="coronavirus" class="ml-1" />{{ t('dashboard.lab') }}
                </h2>
                <button
                    type="button"
                    @click="openScanner"
                    class="inline-flex items-center rounded-md bg-rose-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-rose-700"
                >
                    <Icon name="qr_code_scanner" class="ml-1" />{{ t('lab.scanTicket') }}
                </button>
            </div>
        </template>

        <div class="py-6 sm:py-12">
            <div class="mx-auto max-w-5xl space-y-4 px-4 sm:px-6 lg:px-8">
                <p class="text-sm text-gray-500">{{ t('dashboard.labDesc') }}</p>

                <!-- Status tabs: scroll sideways on phones -->
                <div class="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
                    <button
                        v-for="tab in statusTabs"
                        :key="tab.key"
                        type="button"
                        @click="go({ status: tab.key, page: undefined })"
                        class="inline-flex shrink-0 items-center gap-2 whitespace-nowrap rounded-full border px-4 py-2 text-sm font-medium"
                        :class="filters.status === tab.key ? 'border-indigo-600 bg-indigo-600 text-white' : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'"
                    >
                        {{ tab.label() }}
                        <span class="rounded-full px-2 text-xs" :class="filters.status === tab.key ? 'bg-white/20' : 'bg-gray-100'">{{ countFor(tab.key) }}</span>
                    </button>
                </div>

                <input
                    v-model="search"
                    @input="runSearch"
                    type="search"
                    :placeholder="t('patientReg.searchPlaceholder')"
                    class="w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />

                <!-- Patient cards (one column on phones, two on wider screens) -->
                <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
                    <button
                        v-for="r in registrations.data"
                        :key="r.id"
                        type="button"
                        @click="selected = r"
                        class="flex flex-col gap-1 rounded-lg bg-white p-4 text-right shadow-sm ring-1 ring-gray-100 transition hover:ring-indigo-300"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <span class="font-semibold text-gray-900">{{ r.name }}</span>
                            <span class="flex shrink-0 gap-1">
                                <span v-if="canReuse(r)" class="rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800">{{ t('lab.previousValidBadge') }}</span>
                                <span v-else class="rounded-full px-2 py-0.5 text-xs font-medium" :class="isPaid(r) ? 'bg-sky-100 text-sky-800' : 'bg-gray-100 text-gray-600'">{{ isPaid(r) ? t('lab.paid') : t('lab.unpaid') }}</span>
                                <span class="rounded-full px-2 py-0.5 text-xs font-medium" :class="badgeClass(r.screening_status)">{{ statusLabel(r.screening_status) }}</span>
                            </span>
                        </div>
                        <span class="text-sm text-gray-500" dir="ltr" style="text-align: right">{{ r.phone }}</span>
                        <span class="text-xs text-gray-400">{{ placeAndDay(r) }} · {{ fmtDate(r.created_at) }}</span>
                    </button>
                </div>

                <div v-if="registrations.data.length === 0" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                    {{ t('lab.empty') }}
                </div>

                <div v-if="registrations.links?.length > 3" class="flex flex-wrap gap-1">
                    <Link
                        v-for="(link, i) in registrations.links"
                        :key="i"
                        :href="link.url || '#'"
                        v-html="link.label"
                        preserve-scroll
                        class="rounded px-3 py-1 text-sm"
                        :class="link.active ? 'bg-indigo-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'"
                    />
                </div>
            </div>
        </div>

        <!-- Scanner -->
        <Modal :show="scanning" @close="closeScanner">
            <div class="p-4 sm:p-6">
                <h3 class="mb-3 text-lg font-semibold text-gray-800">{{ t('lab.scanTicket') }}</h3>
                <div v-if="scanError" class="mb-3 rounded-md bg-red-50 p-3 text-sm text-red-700">{{ scanError }}</div>
                <QrScanner ref="scannerRef" @decoded="onDecoded" />
            </div>
        </Modal>

        <!-- Result -->
        <Modal :show="!!selected" @close="selected = null">
            <div v-if="selected" class="flex flex-col gap-4 p-4 sm:p-6">
                <div>
                    <h3 class="text-lg font-semibold text-gray-900">{{ selected.name }}</h3>
                    <p class="text-sm text-gray-500" dir="ltr" style="text-align: right">{{ selected.phone }}</p>
                    <p class="text-sm text-gray-500">{{ placeAndDay(selected) }}</p>
                </div>

                <div v-if="canReuse(selected)" class="flex flex-col gap-3 rounded-md bg-green-50 p-3 text-sm text-green-800">
                    <span>
                        <Icon name="verified" class="ml-1" />
                        {{ t('lab.previousValid', { date: fmtDate(selected.previous_screening.checked_at), days: validityDays }) }}
                    </span>
                    <button
                        v-if="canConfirm"
                        type="button"
                        :disabled="submitting"
                        @click="reuse"
                        class="rounded-md bg-green-700 px-4 py-3 text-sm font-semibold text-white hover:bg-green-800 disabled:opacity-50"
                    >
                        <Icon name="print" class="ml-1" />{{ t('lab.reusePrint') }}
                    </button>
                </div>

                <div v-if="!canReuse(selected) && hasLabFee" class="flex items-center gap-1 rounded-md p-3 text-sm font-semibold" :class="isPaid(selected) ? 'bg-sky-50 text-sky-800' : 'bg-amber-50 text-amber-800'">
                    <Icon :name="isPaid(selected) ? 'paid' : 'payments'" class="ml-1" />
                    <span>{{ isPaid(selected) ? t('lab.paid') : t('lab.feeWithResult') }}</span>
                    <span class="font-normal" dir="ltr">({{ labFeeText }})</span>
                </div>

                <div class="rounded-md p-3 text-sm font-semibold" :class="badgeClass(selected.screening_status)">
                    {{ t('lab.currentStatus') }} {{ statusLabel(selected.screening_status) }}
                    <span v-if="selected.screening_checked_by?.full_name" class="block text-xs font-normal opacity-80">
                        {{ selected.screening_checked_by.full_name }} · {{ fmtDate(selected.screening_checked_at) }}
                    </span>
                </div>

                <div v-if="resultError" class="rounded-md bg-red-50 p-3 text-sm text-red-700">{{ resultError }}</div>

                <template v-if="canConfirm">
                    <h4 v-if="canReuse(selected)" class="text-xs text-gray-500">{{ t('lab.orScreenAgain') }}</h4>
                    <h4 v-else class="text-sm font-medium text-gray-700">{{ t('lab.resultHeading') }}</h4>
                    <div class="grid grid-cols-2 gap-3">
                        <button
                            type="button"
                            :disabled="submitting"
                            @click="record('clear')"
                            class="rounded-md bg-green-700 px-4 py-3 text-sm font-semibold text-white hover:bg-green-800 disabled:opacity-50"
                        >
                            <Icon name="check_circle" class="ml-1" />{{ t('patientReg.screeningClear') }}
                            <span v-if="feeDue(selected)" class="block text-xs font-normal opacity-90">{{ t('lab.payAndPrint') }}</span>
                        </button>
                        <button
                            type="button"
                            :disabled="submitting"
                            @click="record('flagged')"
                            class="rounded-md bg-red-700 px-4 py-3 text-sm font-semibold text-white hover:bg-red-800 disabled:opacity-50"
                        >
                            <Icon name="cancel" class="ml-1" />{{ t('patientReg.screeningFlagged') }}
                            <span v-if="feeDue(selected)" class="block text-xs font-normal opacity-90">{{ t('lab.payAndPrint') }}</span>
                        </button>
                    </div>
                </template>
                <p v-else class="text-sm text-gray-500">{{ t('lab.noConfirmPermission') }}</p>

                <button
                    v-if="selected.screening_status !== 'pending'"
                    type="button"
                    @click="openPrint(selected.id)"
                    class="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                    <Icon name="print" class="ml-1" />{{ t('lab.printResult') }}
                </button>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
