<script setup>
import { confirmDialog } from '@/toast';
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
import { DIAGNOSIS_CODES, DIAGNOSIS_LABELS, diagnosisText } from '@/screeningDiagnosis';

const { t } = useI18n();
const props = defineProps({
    registrations: Object,
    counts: { type: Object, default: () => ({}) },
    filters: Object,
    canConfirm: Boolean,
    labFee: { type: [Number, String], default: null },
    currency: { type: String, default: '' },
    validityDays: { type: Number, default: 0 },
    // The lab's own priced services and test-only patients (2026-11-17).
    labServices: { type: Array, default: () => [] },
    labAbilities: { type: Object, default: () => ({ view: false, manage: false, register: false }) },
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
// Each patient's own fee: less the student discount when eligible (2026-10-25),
// or the lab service's price for a test-only patient (2026-11-17).
const feeOf = (r) => Number(r?.lab_fee_due ?? props.labFee ?? 0);
const hasFee = (r) => feeOf(r) > 0 || isPaid(r);
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
const feeDue = (r) => feeOf(r) > 0 && !isPaid(r) && !canReuse(r);
const placeAndDay = (r) => [r.service?.name ?? r.lab_service?.name ?? '—', r.register_day?.name].filter(Boolean).join(' · ');
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

// "استلام النتيجة" (2026-11-02, by request): beside the samples-sheet
// button. The result was already paid and printed when it was recorded;
// this only marks it collected, which takes the patient off the waiting
// screen's green "النتيجة جاهزة".
// Active at any time, like the samples-sheet button (2026-11-02, by request).
const canMarkReceived = (r) => !!r && !r.lab_result_received_at;
const receiving = ref(false);
const markReceived = async (r) => {
    receiving.value = true;
    resultError.value = '';
    try {
        const { data } = await axios.post(route('lab.received', r.id));
        r.lab_result_received_at = data.data.lab_result_received_at;
        if (selected.value?.id === r.id) selected.value.lab_result_received_at = data.data.lab_result_received_at;
        router.reload({ only: ['registrations', 'counts'] });
    } catch (e) {
        resultError.value = e?.response?.data?.message ?? t('lab.resultReceivedFailed');
    } finally {
        receiving.value = false;
    }
};

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
// "غير سليم" asks which test was positive first (2026-11-03, by request):
// B, C, HIV, one or more; printed on the slip and the receipt.
const diagnosisPicking = ref(false);
const pickedDiagnoses = ref([]);
const toggleDiagnosis = (code) => {
    pickedDiagnoses.value = pickedDiagnoses.value.includes(code)
        ? pickedDiagnoses.value.filter((c) => c !== code)
        : [...pickedDiagnoses.value, code];
};
const resetPrompts = () => {
    feePendingStatus.value = null;
    diagnosisPicking.value = false;
    pickedDiagnoses.value = [];
};
const record = async (status, { feeConfirmed = false, diagnosed = false } = {}) => {
    if (status === 'flagged' && !diagnosed) {
        feePendingStatus.value = null;
        pickedDiagnoses.value = [];
        diagnosisPicking.value = true;
        return;
    }
    if (status === 'clear') {
        diagnosisPicking.value = false;
        pickedDiagnoses.value = [];
    }
    if (feeDue(selected.value) && !feeConfirmed) {
        feePendingStatus.value = status;
        return;
    }
    feePendingStatus.value = null;
    diagnosisPicking.value = false;
    const diagnoses = status === 'flagged' ? DIAGNOSIS_CODES.filter((c) => pickedDiagnoses.value.includes(c)) : [];
    submitting.value = true;
    resultError.value = '';
    try {
        const id = selected.value.id;
        await axios.post(route('patient-registrations.screening', id), { screening_status: status, screening_diagnoses: diagnoses });
        printSlip(id);
        // The window stays open on the saved result (2026-11-02), so
        // "استلام النتيجة" is ready when the patient comes for it.
        if (selected.value?.id === id) {
            selected.value = { ...selected.value, screening_status: status, screening_diagnoses: diagnoses, screening_checked_at: new Date().toISOString(), lab_paid: isPaid(selected.value) || feeDue(selected.value) };
        }
        router.reload({ only: ['registrations', 'counts'] });
    } catch (e) {
        resultError.value = e?.response?.data?.message ?? t('lab.recordFailed');
    } finally {
        submitting.value = false;
    }
};

// --- The lab's own services and test-only patients (2026-11-17, by request) ---
const services = ref([...props.labServices]);
watch(() => props.labServices, (v) => { services.value = [...v]; });
const activeServices = computed(() => services.value.filter((s) => s.active));
const money = (v) => `${Number(v ?? 0).toLocaleString()} ${props.currency ?? ''}`.trim();

const walkInOpen = ref(false);
const walkIn = ref({ name: '', phone: '', age: '', lab_service_id: '', paid: true });
const walkInError = ref('');
const walkInSaving = ref(false);
const walkInService = computed(() => services.value.find((s) => s.id === Number(walkIn.value.lab_service_id)));
const openWalkIn = () => {
    walkIn.value = { name: '', phone: '', age: '', lab_service_id: activeServices.value.length === 1 ? activeServices.value[0].id : '', paid: true };
    walkInError.value = '';
    walkInOpen.value = true;
};
const saveWalkIn = async () => {
    walkInSaving.value = true;
    walkInError.value = '';
    try {
        const { data } = await axios.post(route('lab.register'), {
            ...walkIn.value,
            age: walkIn.value.age === '' ? null : Number(walkIn.value.age),
            lab_service_id: Number(walkIn.value.lab_service_id) || null,
        });
        if (data.receipt_url) printInFrame(data.receipt_url);
        walkInOpen.value = false;
        resetPrompts();
        selected.value = data.data;
        router.reload({ only: ['registrations', 'counts', 'labServices'] });
    } catch (e) {
        const errors = e?.response?.data?.errors;
        walkInError.value = (errors && Object.values(errors)[0]?.[0]) ?? e?.response?.data?.message ?? t('lab.walkInFailed');
    } finally {
        walkInSaving.value = false;
    }
};

const servicesOpen = ref(false);
const serviceForm = ref({ id: null, name: '', price: '' });
const serviceError = ref('');
const serviceSaving = ref(false);
const openServices = () => {
    serviceForm.value = { id: null, name: '', price: '' };
    serviceError.value = '';
    servicesOpen.value = true;
};
const editService = (svc) => {
    serviceForm.value = { id: svc.id, name: svc.name, price: svc.price };
    serviceError.value = '';
};
const serviceRequest = async (fn) => {
    serviceSaving.value = true;
    serviceError.value = '';
    try {
        const { data } = await fn();
        services.value = data.data;
        return true;
    } catch (e) {
        const errors = e?.response?.data?.errors;
        serviceError.value = (errors && Object.values(errors)[0]?.[0]) ?? e?.response?.data?.message ?? t('lab.serviceFailed');
        return false;
    } finally {
        serviceSaving.value = false;
    }
};
const saveService = async () => {
    const body = { name: serviceForm.value.name, price: serviceForm.value.price === '' ? null : Number(serviceForm.value.price) };
    const id = serviceForm.value.id;
    const ok = await serviceRequest(() =>
        id ? axios.put(route('lab.services.update', id), body) : axios.post(route('lab.services.store'), body),
    );
    if (ok) serviceForm.value = { id: null, name: '', price: '' };
};
const toggleService = (svc) =>
    serviceRequest(() => axios.put(route('lab.services.update', svc.id), { name: svc.name, price: svc.price, active: !svc.active }));
const deleteService = async (svc) => {
    if (!await confirmDialog(t('lab.serviceDeleteConfirm', { name: svc.name }))) return;
    serviceRequest(() => axios.delete(route('lab.services.destroy', svc.id)));
};
</script>

<template>
    <Head :title="t('dashboard.lab')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('dashboard.lab') }}</h2>
                <div class="flex flex-wrap items-center justify-end gap-2">
                    <button
                        v-if="labAbilities.view"
                        type="button"
                        @click="openServices"
                        class="inline-flex items-center gap-1 rounded-full bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-200 hover:bg-gray-50"
                    >
                        <Icon name="biotech" />{{ t('lab.services') }}
                    </button>
                    <button
                        v-if="labAbilities.register"
                        type="button"
                        @click="openWalkIn"
                        class="inline-flex items-center gap-1 rounded-full bg-violet-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-violet-700"
                    >
                        <Icon name="person_add" />{{ t('lab.walkIn') }}
                    </button>
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
                        @click="selected = r; resetPrompts()"
                    >
                        <template #meta>
                            <ChatChip :icon="statusIcon(r.screening_status)" :tone="statusTone(r.screening_status)">{{ statusLabel(r.screening_status) }}<template v-if="diagnosisText(r)"> — {{ diagnosisText(r) }}</template></ChatChip>
                            <ChatChip v-if="canReuse(r)" icon="verified" tone="emerald">{{ t('lab.previousValidBadge') }}</ChatChip>
                            <ChatChip v-else :icon="isPaid(r) ? 'paid' : 'money_off'" :tone="isPaid(r) ? 'sky' : 'gray'">{{ isPaid(r) ? t('lab.paid') : t('lab.unpaid') }}</ChatChip>
                            <ChatChip v-if="r.lab_result_received_at" icon="how_to_reg" tone="emerald">{{ t('lab.resultReceivedDone') }}</ChatChip>
                            <ChatChip v-else-if="r.screening_status !== 'pending'" icon="hourglass_bottom" tone="amber">{{ t('lab.awaitingCollection') }}</ChatChip>
                            <ChatChip v-if="r.lab_service_id" icon="biotech" tone="violet">{{ t('lab.labOnlyBadge') }}</ChatChip>
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
                            <ChatAction
                                v-if="canConfirm && canMarkReceived(r)"
                                icon="how_to_reg"
                                :label="t('lab.resultReceived')"
                                @click="(e) => { e?.stopPropagation(); markReceived(r); }"
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
        <Modal :show="!!selected" @close="selected = null; resetPrompts()">
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
                        :class="selected.previous_screening.matched_by === 'name_phone' ? 'bg-green-100' : 'bg-amber-100 text-amber-900'"
                    >
                        {{ t({ name_phone: 'lab.matchedByBoth', phone: 'lab.matchedByPhone' }[selected.previous_screening.matched_by] ?? 'lab.matchedByName', { name: selected.previous_screening.name, phone: selected.previous_screening.phone }) }}
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

                <div v-if="!canReuse(selected) && hasFee(selected)" class="flex items-center gap-1 rounded-xl p-3 text-sm font-semibold" :class="isPaid(selected) ? 'bg-sky-50 text-sky-800' : 'bg-amber-50 text-amber-800'">
                    <Icon :name="isPaid(selected) ? 'paid' : 'payments'" class="ml-1" />
                    <span>{{ isPaid(selected) ? t('lab.paid') : t('lab.feeWithResult') }}</span>
                    <span class="font-normal" dir="ltr">({{ labFeeText(selected) }})</span>
                    <span v-if="labDiscountText(selected)" class="font-normal" dir="ltr">· {{ labDiscountText(selected) }}</span>
                    <span v-else-if="selected.discount_eligible" class="font-normal">· {{ t('patientReg.studentDiscountApplied') }}</span>
                </div>

                <div class="rounded-xl p-3 text-sm font-semibold" :class="badgeClass(selected.screening_status)">
                    {{ t('lab.currentStatus') }} {{ statusLabel(selected.screening_status) }}
                    <span v-if="diagnosisText(selected)" class="block">{{ t('lab.diagnosis') }}: {{ diagnosisText(selected) }}</span>
                    <span v-if="selected.screening_checked_by?.full_name" class="block text-xs font-normal opacity-80">
                        {{ selected.screening_checked_by.full_name }} · {{ fmtDate(selected.screening_checked_at) }}
                    </span>
                </div>

                <div v-if="resultError" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ resultError }}</div>

                <!-- The samples sheet, and beside it "استلام النتيجة", active at any
                     time (2026-11-02, by request). -->
                <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <button
                        type="button"
                        :disabled="selected.screening_status !== 'pending'"
                        @click="startTest(selected.id)"
                        class="rounded-xl border-2 border-indigo-300 bg-indigo-50 px-4 py-3 text-sm font-semibold text-indigo-800 hover:bg-indigo-100 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                        <Icon name="science" class="ml-1" />{{ t('lab.startTest') }}
                        <span class="block text-xs font-normal opacity-80">{{ t('lab.startTestHint') }}</span>
                    </button>
                    <button
                        v-if="canConfirm && !selected.lab_result_received_at"
                        type="button"
                        :disabled="receiving"
                        @click="markReceived(selected)"
                        class="rounded-xl border-2 border-emerald-300 bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-800 hover:bg-emerald-100 disabled:opacity-50"
                    >
                        <Icon name="how_to_reg" class="ml-1" />{{ t('lab.resultReceived') }}
                        <span class="block text-xs font-normal opacity-80">{{ t('lab.resultReceivedHint') }}</span>
                    </button>
                    <div v-else-if="selected.lab_result_received_at" class="rounded-xl bg-emerald-50 px-4 py-3 text-sm font-semibold text-emerald-800">
                        <Icon name="how_to_reg" class="ml-1" />{{ t('lab.resultReceivedDone') }}
                        <span class="block text-xs font-normal opacity-80">{{ fmtDate(selected.lab_result_received_at) }}</span>
                    </div>
                </div>

                <!-- A recorded result is final (2026-11-01, by request). -->
                <p v-if="selected.screening_status !== 'pending'" class="rounded-xl bg-gray-50 p-3 text-sm text-gray-600">
                    <Icon name="lock" class="ml-1" />{{ t('lab.resultLocked') }}
                </p>
                <template v-if="canConfirm && selected.screening_status === 'pending'">
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
                    <div v-if="diagnosisPicking" class="flex flex-col gap-3 rounded-xl border-2 border-red-300 bg-red-50 p-4 text-sm text-red-900">
                        <span class="font-semibold"><Icon name="coronavirus" class="ml-1" />{{ t('lab.diagnosisTitle') }}</span>
                        <span>{{ t('lab.diagnosisHint') }}</span>
                        <div class="grid grid-cols-3 gap-2">
                            <button
                                v-for="code in DIAGNOSIS_CODES"
                                :key="code"
                                type="button"
                                @click="toggleDiagnosis(code)"
                                class="rounded-xl border-2 px-3 py-3 text-base font-bold transition"
                                :class="pickedDiagnoses.includes(code) ? 'border-red-700 bg-red-700 text-white' : 'border-red-200 bg-white text-red-800 hover:bg-red-100'"
                            >
                                <Icon :name="pickedDiagnoses.includes(code) ? 'check_box' : 'check_box_outline_blank'" class="ml-1" />{{ code }}
                                <span class="block text-xs font-normal opacity-90">{{ DIAGNOSIS_LABELS[code] }}</span>
                            </button>
                        </div>
                        <div class="grid grid-cols-2 gap-3">
                            <button
                                type="button"
                                :disabled="submitting || pickedDiagnoses.length === 0"
                                @click="record('flagged', { diagnosed: true })"
                                class="rounded-xl bg-red-700 px-4 py-2 font-semibold text-white hover:bg-red-800 disabled:opacity-50"
                            >
                                {{ t('lab.diagnosisConfirm') }}
                            </button>
                            <button
                                type="button"
                                @click="resetPrompts()"
                                class="rounded-xl border border-gray-300 bg-white px-4 py-2 font-semibold text-gray-700 hover:bg-gray-50"
                            >
                                {{ t('lab.diagnosisCancel') }}
                            </button>
                        </div>
                    </div>
                    <div v-if="feePendingStatus" class="flex flex-col gap-3 rounded-xl border-2 border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
                        <span class="font-semibold">
                            <Icon name="payments" class="ml-1" />{{ t('lab.feeConfirmQuestion', { amount: labFeeText(selected) }) }}
                        </span>
                        <div class="grid grid-cols-2 gap-3">
                            <button
                                type="button"
                                :disabled="submitting"
                                @click="record(feePendingStatus, { feeConfirmed: true, diagnosed: true })"
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
                <p v-else-if="!canConfirm && selected.screening_status === 'pending'" class="text-sm text-gray-500">{{ t('lab.noConfirmPermission') }}</p>

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
        <!-- Test-only patient (2026-11-17, by request) -->
        <Modal :show="walkInOpen" @close="walkInOpen = false">
            <form class="flex flex-col gap-4 p-4 sm:p-6" @submit.prevent="saveWalkIn">
                <div>
                    <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-800"><Icon name="person_add" />{{ t('lab.walkInTitle') }}</h3>
                    <p class="mt-1 text-sm text-gray-500">{{ t('lab.walkInHint') }}</p>
                </div>
                <p v-if="activeServices.length === 0" class="rounded-xl bg-amber-50 p-3 text-sm text-amber-800">{{ t('lab.walkInNoServices') }}</p>
                <label class="flex flex-col gap-1 text-sm font-medium text-gray-700">
                    {{ t('lab.walkInService') }}
                    <select v-model="walkIn.lab_service_id" required class="rounded-xl border-gray-300 focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="" disabled>{{ t('lab.walkInPick') }}</option>
                        <option v-for="svc in activeServices" :key="svc.id" :value="svc.id">{{ svc.name }} — {{ money(svc.price) }}</option>
                    </select>
                </label>
                <label class="flex flex-col gap-1 text-sm font-medium text-gray-700">
                    {{ t('lab.walkInName') }}
                    <input v-model="walkIn.name" type="text" required maxlength="255" class="rounded-xl border-gray-300 focus:border-indigo-500 focus:ring-indigo-500" />
                </label>
                <div class="grid grid-cols-2 gap-3">
                    <label class="flex flex-col gap-1 text-sm font-medium text-gray-700">
                        {{ t('lab.walkInPhone') }}
                        <input v-model="walkIn.phone" type="tel" dir="ltr" required maxlength="20" class="rounded-xl border-gray-300 focus:border-indigo-500 focus:ring-indigo-500" />
                    </label>
                    <label class="flex flex-col gap-1 text-sm font-medium text-gray-700">
                        {{ t('lab.walkInAge') }}
                        <input v-model="walkIn.age" type="number" min="0" max="150" class="rounded-xl border-gray-300 focus:border-indigo-500 focus:ring-indigo-500" />
                    </label>
                </div>
                <label v-if="walkInService && Number(walkInService.price) > 0" class="flex items-start gap-2 rounded-xl bg-violet-50 p-3 text-sm text-violet-900">
                    <input v-model="walkIn.paid" type="checkbox" class="mt-0.5 rounded border-gray-300 text-violet-600 focus:ring-violet-500" />
                    <span>
                        <span class="font-semibold">{{ t('lab.walkInPaid', { amount: money(walkInService.price) }) }}</span>
                        <span class="block text-xs opacity-80">{{ t('lab.walkInPaidHint') }}</span>
                    </span>
                </label>
                <div v-if="walkInError" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ walkInError }}</div>
                <button
                    type="submit"
                    :disabled="walkInSaving || activeServices.length === 0"
                    class="rounded-xl bg-violet-600 px-4 py-3 text-sm font-semibold text-white hover:bg-violet-700 disabled:opacity-50"
                >
                    <Icon name="check" class="ml-1" />{{ t('lab.walkInSave') }}
                </button>
            </form>
        </Modal>

        <!-- The lab's own services and prices (2026-11-17, by request) -->
        <Modal :show="servicesOpen" @close="servicesOpen = false">
            <div class="flex flex-col gap-4 p-4 sm:p-6">
                <div>
                    <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-800"><Icon name="biotech" />{{ t('lab.services') }}</h3>
                    <p class="mt-1 text-sm text-gray-500">{{ t('lab.servicesHint') }}</p>
                </div>
                <form v-if="labAbilities.manage" class="grid grid-cols-[1fr_8rem_auto] items-end gap-2" @submit.prevent="saveService">
                    <label class="flex flex-col gap-1 text-xs font-medium text-gray-600">
                        {{ t('lab.serviceName') }}
                        <input v-model="serviceForm.name" type="text" required maxlength="100" class="rounded-xl border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500" />
                    </label>
                    <label class="flex flex-col gap-1 text-xs font-medium text-gray-600">
                        {{ t('lab.servicePrice') }}
                        <input v-model="serviceForm.price" type="number" min="0" step="any" required dir="ltr" class="rounded-xl border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500" />
                    </label>
                    <button type="submit" :disabled="serviceSaving" class="rounded-xl bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-700 disabled:opacity-50">
                        {{ serviceForm.id ? t('lab.serviceSave') : t('lab.serviceAdd') }}
                    </button>
                </form>
                <div v-if="serviceError" class="rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ serviceError }}</div>
                <p v-if="services.length === 0" class="rounded-xl bg-gray-50 p-3 text-center text-sm text-gray-500">{{ t('lab.servicesEmpty') }}</p>
                <ul v-else class="divide-y divide-gray-100 rounded-xl ring-1 ring-gray-200">
                    <li v-for="svc in services" :key="svc.id" class="flex items-center gap-3 px-3 py-2.5" :class="svc.active ? '' : 'opacity-60'">
                        <div class="min-w-0 flex-1">
                            <p class="truncate text-sm font-semibold text-gray-800">{{ svc.name }}</p>
                            <p class="text-xs text-gray-500">
                                <span dir="ltr">{{ money(svc.price) }}</span>
                                · {{ svc.active ? t('lab.serviceActive') : t('lab.serviceInactive') }}
                                <template v-if="svc.patients"> · {{ t('lab.servicePatients', { n: svc.patients }) }}</template>
                            </p>
                        </div>
                        <template v-if="labAbilities.manage">
                            <button type="button" :title="svc.active ? t('lab.serviceInactive') : t('lab.serviceActive')" @click="toggleService(svc)" class="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
                                <Icon :name="svc.active ? 'toggle_on' : 'toggle_off'" :class="svc.active ? 'text-emerald-600' : ''" />
                            </button>
                            <button type="button" :title="t('lab.serviceEdit')" @click="editService(svc)" class="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100"><Icon name="edit" /></button>
                            <button type="button" :title="t('lab.serviceDelete')" @click="deleteService(svc)" class="rounded-lg p-1.5 text-rose-500 hover:bg-rose-50"><Icon name="delete" /></button>
                        </template>
                    </li>
                </ul>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
