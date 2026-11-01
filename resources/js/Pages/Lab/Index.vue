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
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import ChatPager from '@/Components/ChatList/ChatPager.vue';
import QrScanner from '@/Components/QrScanner.vue';
import PhoneScannerLink from '@/Components/PhoneScannerLink.vue';
import { onRemoteScan } from '@/remoteScanner';
import { Head, router } from '@inertiajs/vue3';
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import { printInFrame } from '@/printInFrame';
import { useLiveRegistrations } from '@/Composables/useLiveRegistrations';

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

// New and changed registrations show up by themselves (2026-10-19, by request).
useLiveRegistrations(['registrations', 'counts']);

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
watch(search, () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => go({}), 300);
});

const badgeClass = (status) =>
    ({ clear: 'bg-green-100 text-green-800', flagged: 'bg-red-100 text-red-800' })[status] ?? 'bg-amber-100 text-amber-800';
// Chip/avatar tone and icon per screening status (chat-list rows).
const statusTone = (status) => ({ clear: 'emerald', flagged: 'rose' })[status] ?? 'amber';
const statusIcon = (status) => ({ clear: 'check_circle', flagged: 'cancel' })[status] ?? 'hourglass_top';
const statusLabel = (status) =>
    ({ clear: t('patientReg.screeningClear'), flagged: t('patientReg.screeningFlagged') })[status] ?? t('patientReg.screeningPending');
const isPaid = (r) => !!r.lab_paid;
// The lab fee is taken with the result (2026-10-12): picking "سليم" or
// "غير سليم" records the payment and prints one paid slip (LabFeeGate).
const hasLabFee = computed(() => props.labFee !== null && props.labFee !== '');
// Each patient's own fee: less the student discount when eligible (2026-10-25).
const feeOf = (r) => Number(r?.lab_fee_due ?? props.labFee ?? 0);
const labFeeText = (r) => `${feeOf(r).toLocaleString()} ${props.currency ?? ''}`.trim();
// "10,000 − 50%" beside the discounted fee (2026-10-25, by request).
const labDiscountText = (r) => {
    const full = Number(props.labFee ?? 0);
    if (!r?.discount_eligible || !(full > feeOf(r))) return '';
    const percent = Math.round((1 - feeOf(r) / full) * 1000) / 10;
    return `${full.toLocaleString()} − ${percent}%`;
};
// A clear result from the last `validityDays` (same phone) is reused
// instead: no new screening and nothing to pay (LabFeeGate).
const canReuse = (r) => r.screening_status === 'pending' && !!r.previous_screening;
const feeDue = (r) => hasLabFee.value && feeOf(r) > 0 && !isPaid(r) && !canReuse(r);
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
        // Opening a patient never prints by itself (2026-11-01, by request):
        // the slip prints only once staff pick a result (or reuse one).
        selected.value = data.data;
    } catch (e) {
        scanError.value = e?.response?.data?.message ?? t('payments.qrReadFailed');
    }
};

// A phone paired as a scanner (2026-10-12) reads tickets without the
// camera here being open; while it is open, QrScanner takes the code.
onRemoteScan(onDecoded, () => !scannerRef.value?.scanning);

// --- Record a result ---
const selected = ref(null);
const submitting = ref(false);
const resultError = ref('');

// Saving a result prints the lab slip (result, paid fee, patient QR)
// straight away, in a hidden frame rather than a new tab (2026-10-18, by
// request).
const printSlip = (id) => printInFrame(route('lab.print', { patientRegistration: id, autoprint: 1 }));
// "بدء الفحص" (2026-11-01, by request): prints the patient's name with a big
// "هنا توضع العينات" circle, so samples sit under the right name.
const startTest = (id) => printInFrame(route('lab.sample', { patientRegistration: id, autoprint: 1 }));

const reuse = async () => {
    submitting.value = true;
    resultError.value = '';
    try {
        const id = selected.value.id;
        await axios.post(route('lab.reuse', id));
        printSlip(id);
        selected.value = null;
        router.reload({ only: ['registrations', 'counts'] });
    } catch (e) {
        resultError.value = e?.response?.data?.message ?? t('lab.recordFailed');
    } finally {
        submitting.value = false;
    }
};

// Asked before a fee-due result is saved (2026-11-01, by request): "did you
// receive the lab fee?" Yes records the payment and prints; no saves nothing.
const feePendingStatus = ref(null);
const record = async (status, { feeConfirmed = false } = {}) => {
    if (feeDue(selected.value) && !feeConfirmed) {
        feePendingStatus.value = status;
        return;
    }
    feePendingStatus.value = null;
    submitting.value = true;
    resultError.value = '';
    try {
        const id = selected.value.id;
        await axios.post(route('patient-registrations.screening', id), { screening_status: status });
        printSlip(id);
        selected.value = null;
        router.reload({ only: ['registrations', 'counts'] });
    } catch (e) {
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
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('dashboard.lab') }}</h2>
                <div class="flex items-center gap-2">
                    <PhoneScannerLink variant="page" />
                    <ChatAddButton :label="t('lab.scanTicket')" icon="qr_code_scanner" @click="openScanner" />
                </div>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <ChatSearch v-model="search" :placeholder="t('patientReg.searchPlaceholder')" @submit="go({})" />

                <!-- Status tabs: scroll sideways on phones -->
                <div class="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
                    <button
                        v-for="tab in statusTabs"
                        :key="tab.key"
                        type="button"
                        @click="go({ status: tab.key, page: undefined })"
                        class="inline-flex shrink-0 items-center gap-2 whitespace-nowrap rounded-full px-4 py-1.5 text-sm font-medium shadow-sm transition"
                        :class="filters.status === tab.key ? 'bg-indigo-600 text-white' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-gray-50'"
                    >
                        {{ tab.label() }}
                        <span class="rounded-full px-2 text-xs" :class="filters.status === tab.key ? 'bg-white/20' : 'bg-gray-100'">{{ countFor(tab.key) }}</span>
                    </button>
                </div>

                <ChatListCard :empty="registrations.data.length === 0" :empty-text="t('lab.empty')" empty-icon="coronavirus">
                    <ChatListRow
                        v-for="r in registrations.data"
                        :key="r.id"
                        :title="r.name"
                        :subtitle="r.phone"
                        :tone="statusTone(r.screening_status)"
                        :icon="statusIcon(r.screening_status)"
                        class="cursor-pointer hover:bg-gray-50"
                        @click="selected = r; feePendingStatus = null"
                    >
                        <template #meta>
                            <ChatChip :icon="statusIcon(r.screening_status)" :tone="statusTone(r.screening_status)">{{ statusLabel(r.screening_status) }}</ChatChip>
                            <ChatChip v-if="canReuse(r)" icon="verified" tone="emerald">{{ t('lab.previousValidBadge') }}</ChatChip>
                            <ChatChip v-else :icon="isPaid(r) ? 'paid' : 'money_off'" :tone="isPaid(r) ? 'sky' : 'gray'">{{ isPaid(r) ? t('lab.paid') : t('lab.unpaid') }}</ChatChip>
                            <ChatChip icon="location_on">{{ placeAndDay(r) }}</ChatChip>
                            <ChatChip icon="schedule">{{ fmtDate(r.created_at) }}</ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction
                                v-if="r.screening_status === 'pending'"
                                icon="science"
                                :label="t('lab.startTest')"
                                @click="(e) => { e?.stopPropagation(); startTest(r.id); }"
                            />
                        </template>
                    </ChatListRow>
                    <template #footer>
                        <ChatPager :links="registrations.links ?? []" />
                    </template>
                </ChatListCard>
            </div>
        </div>

        <!-- Scanner -->
        <Modal :show="scanning" @close="closeScanner">
            <div class="p-4 sm:p-6">
                <h3 class="mb-3 flex items-center gap-2 text-lg font-semibold text-gray-800">
                    <Icon name="qr_code_scanner" />{{ t('lab.scanTicket') }}
                </h3>
                <div v-if="scanError" class="mb-3 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ scanError }}</div>
                <QrScanner ref="scannerRef" @decoded="onDecoded" />
            </div>
        </Modal>

        <!-- Result -->
        <Modal :show="!!selected" @close="selected = null; feePendingStatus = null">
            <div v-if="selected" class="flex flex-col gap-4 p-4 sm:p-6">
                <div class="flex items-center gap-3">
                    <div
                        class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-gradient-to-br text-white"
                        :class="{ clear: 'from-emerald-500 to-teal-500', flagged: 'from-rose-500 to-red-500' }[selected.screening_status] ?? 'from-amber-500 to-orange-500'"
                    >
                        <Icon :name="statusIcon(selected.screening_status)" size="text-[24px]" />
                    </div>
                    <div class="min-w-0">
                        <h3 class="truncate text-lg font-semibold text-gray-900">{{ selected.name }}</h3>
                        <p class="text-sm text-gray-500" dir="ltr" style="text-align: right">{{ selected.phone }}</p>
                        <p class="text-xs text-gray-400">{{ placeAndDay(selected) }}</p>
                    </div>
                </div>

                <div v-if="canReuse(selected)" class="flex flex-col gap-3 rounded-xl bg-green-50 p-3 text-sm text-green-800">
                    <span>
                        <Icon name="verified" class="ml-1" />
                        {{ t('lab.previousValid', { date: fmtDate(selected.previous_screening.checked_at), days: validityDays }) }}
                    </span>
                    <span
                        v-if="selected.previous_screening.name"
                        class="rounded-lg px-2 py-1 text-xs"
                        :class="selected.previous_screening.matched_by === 'name' ? 'bg-amber-100 text-amber-900' : 'bg-green-100'"
                    >
                        {{ t(selected.previous_screening.matched_by === 'name' ? 'lab.matchedByName' : 'lab.matchedByPhone', { name: selected.previous_screening.name, phone: selected.previous_screening.phone }) }}
                    </span>
                    <button
                        v-if="canConfirm"
                        type="button"
                        :disabled="submitting"
                        @click="reuse()"
                        class="rounded-xl bg-green-700 px-4 py-3 text-sm font-semibold text-white hover:bg-green-800 disabled:opacity-50"
                    >
                        <Icon name="print" class="ml-1" />{{ t('lab.reusePrint') }}
                    </button>
                </div>

                <div v-if="!canReuse(selected) && hasLabFee" class="flex items-center gap-1 rounded-xl p-3 text-sm font-semibold" :class="isPaid(selected) ? 'bg-sky-50 text-sky-800' : 'bg-amber-50 text-amber-800'">
                    <Icon :name="isPaid(selected) ? 'paid' : 'payments'" class="ml-1" />
                    <span>{{ isPaid(selected) ? t('lab.paid') : t('lab.feeWithResult') }}</span>
                    <span class="font-normal" dir="ltr">({{ labFeeText(selected) }})</span>
                    <span v-if="labDiscountText(selected)" class="font-normal" dir="ltr">· {{ labDiscountText(selected) }}</span>
                    <span v-else-if="selected.discount_eligible" class="font-normal">· {{ t('patientReg.studentDiscountApplied') }}</span>
                </div>

                <div class="rounded-xl p-3 text-sm font-semibold" :class="badgeClass(selected.screening_status)">
                    {{ t('lab.currentStatus') }} {{ statusLabel(selected.screening_status) }}
                    <span v-if="selected.screening_checked_by?.full_name" class="block text-xs font-normal opacity-80">
                        {{ selected.screening_checked_by.full_name }} · {{ fmtDate(selected.screening_checked_at) }}
                    </span>
                </div>

                <div v-if="resultError" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ resultError }}</div>

                <button
                    v-if="selected.screening_status === 'pending'"
                    type="button"
                    @click="startTest(selected.id)"
                    class="rounded-xl border-2 border-indigo-300 bg-indigo-50 px-4 py-3 text-sm font-semibold text-indigo-800 hover:bg-indigo-100"
                >
                    <Icon name="science" class="ml-1" />{{ t('lab.startTest') }}
                    <span class="block text-xs font-normal opacity-80">{{ t('lab.startTestHint') }}</span>
                </button>

                <template v-if="canConfirm">
                    <h4 v-if="canReuse(selected)" class="text-xs text-gray-500">{{ t('lab.orScreenAgain') }}</h4>
                    <h4 v-else class="text-sm font-medium text-gray-700">{{ t('lab.resultHeading') }}</h4>
                    <div class="grid grid-cols-2 gap-3">
                        <button
                            type="button"
                            :disabled="submitting"
                            @click="record('clear')"
                            class="rounded-xl bg-green-700 px-4 py-3 text-sm font-semibold text-white hover:bg-green-800 disabled:opacity-50"
                        >
                            <Icon name="check_circle" class="ml-1" />{{ t('patientReg.screeningClear') }}
                            <span v-if="feeDue(selected)" class="block text-xs font-normal opacity-90">{{ t('lab.payAndPrint') }}</span>
                        </button>
                        <button
                            type="button"
                            :disabled="submitting"
                            @click="record('flagged')"
                            class="rounded-xl bg-red-700 px-4 py-3 text-sm font-semibold text-white hover:bg-red-800 disabled:opacity-50"
                        >
                            <Icon name="cancel" class="ml-1" />{{ t('patientReg.screeningFlagged') }}
                            <span v-if="feeDue(selected)" class="block text-xs font-normal opacity-90">{{ t('lab.payAndPrint') }}</span>
                        </button>
                    </div>
                    <div v-if="feePendingStatus" class="flex flex-col gap-3 rounded-xl border-2 border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
                        <span class="font-semibold">
                            <Icon name="payments" class="ml-1" />{{ t('lab.feeConfirmQuestion', { amount: labFeeText(selected) }) }}
                        </span>
                        <div class="grid grid-cols-2 gap-3">
                            <button
                                type="button"
                                :disabled="submitting"
                                @click="record(feePendingStatus, { feeConfirmed: true })"
                                class="rounded-xl bg-green-700 px-4 py-2 font-semibold text-white hover:bg-green-800 disabled:opacity-50"
                            >
                                {{ t('lab.feeConfirmYes') }}
                            </button>
                            <button
                                type="button"
                                @click="feePendingStatus = null"
                                class="rounded-xl border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-700 hover:bg-gray-50"
                            >
                                {{ t('lab.feeConfirmNo') }}
                            </button>
                        </div>
                    </div>
                </template>
                <p v-else-if="!canConfirm" class="text-sm text-gray-500">{{ t('lab.noConfirmPermission') }}</p>

                <button
                    v-if="selected.screening_status !== 'pending'"
                    type="button"
                    @click="printSlip(selected.id)"
                    class="rounded-xl border border-gray-200 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                    <Icon name="print" class="ml-1" />{{ t('lab.printResult') }}
                </button>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
