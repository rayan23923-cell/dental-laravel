<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import QrScanner from '@/Components/QrScanner.vue';
import PhoneScannerLink from '@/Components/PhoneScannerLink.vue';
import { onRemoteScan } from '@/remoteScanner';
import Icon from '@/Components/Icon.vue';
import { Head, useForm, usePage } from '@inertiajs/vue3';
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';

const { t } = useI18n();
const props = defineProps({
    appointments: Array,
    labFee: { type: [Number, String], default: null },
    currency: { type: String, default: '' },
});

const page = usePage();

// A payment settles either an appointment or a reception-desk
// registration — never both (see PaymentController::validatePayment()'s
// required_without/prohibits pair). This toggle keeps the form from ever
// submitting both at once by clearing the other field on switch.
const source = ref('appointment');

const form = useForm({
    appointment_id: '',
    patient_registration_id: '',
    amount: '',
    paid_by: '',
});

watch(source, (value) => {
    if (value === 'appointment') {
        form.patient_registration_id = '';
        clearRegistration();
    } else {
        form.appointment_id = '';
    }
});

// --- Find a registered patient: scan their ticket QR, or search by
// name/phone (2026-08-26) — replaces a `<select>` that loaded every
// registration into the page at once, which the user asked to fix. Scan
// reuses the exact same `Components/QrScanner.vue` + `patient-registrations
// .scan` round-trip already used elsewhere (TaskProgress's start-task
// modal); search hits the new lightweight `patient-registrations.search`
// endpoint instead of `index()`'s full paginated page.
const selectedRegistration = ref(null);

const scanning = ref(false);
const scannerRef = ref(null);
const scanError = ref('');

const openScanner = async () => {
    scanError.value = '';
    scanning.value = true;
    await nextTick();
    scannerRef.value?.start();
};

const onDecoded = async (text) => {
    scanError.value = '';
    try {
        const { data } = await axios.post(route('patient-registrations.scan'), { payload: text });
        selectedRegistration.value = { ...data.data.registration, lab_paid: data.data.lab_paid };
        form.patient_registration_id = data.data.registration.id;
        scannerRef.value?.stop();
        scanning.value = false;
    } catch (e) {
        scanError.value = e?.response?.data?.message ?? t('payments.qrReadFailed');
    }
};

// A phone paired as a scanner (2026-10-12) picks the registration too.
onRemoteScan(onDecoded, () => !scannerRef.value?.scanning);

const registrationSearch = ref('');
const registrationResults = ref([]);
const searching = ref(false);
let searchTimer;

const onSearchInput = () => {
    clearTimeout(searchTimer);
    if (!registrationSearch.value.trim()) {
        registrationResults.value = [];
        return;
    }
    searchTimer = setTimeout(async () => {
        searching.value = true;
        try {
            const { data } = await axios.get(route('patient-registrations.search'), { params: { q: registrationSearch.value } });
            registrationResults.value = data.data;
        } finally {
            searching.value = false;
        }
    }, 300);
};

const selectRegistration = (r) => {
    selectedRegistration.value = r;
    form.patient_registration_id = r.id;
    registrationSearch.value = '';
    registrationResults.value = [];
};

// Screening confirmation (2026-08-29) — previously this form only found
// out a patient wasn't clear when `PatientScreeningGate` rejected the
// whole submit server-side (a generic flash-error banner, after the
// clerk had already typed an amount). Both `scan()`'s and now
// `search()`'s registration payload carry `screening_status`, so this
// checks it the moment a patient is resolved instead. `isScreeningClear`
// mirrors the Flutter `PatientRegistration.isScreeningClear` getter.
const isScreeningClear = (registration) => registration?.screening_status === 'clear';

// Blocks the amount/submit section outright when the source is a
// registration that isn't screening-clear — the banner above already
// explains why; server-side `PatientScreeningGate` would reject it
// anyway, this just surfaces it before the clerk types an amount.
const registrationBlocked = computed(
    () => source.value === 'registration' && selectedRegistration.value && !isScreeningClear(selectedRegistration.value),
);

const clearRegistration = () => {
    selectedRegistration.value = null;
    form.patient_registration_id = '';
    registrationSearch.value = '';
    registrationResults.value = [];
    scanError.value = '';
};

// --- Quick-digit amount entry — matches the Flutter payment screen's
// "0"/"00"/"000" append buttons (2026-08-26), same reasoning: a clerk
// types "5" then taps "000" for 5000 instead of typing every digit.
const appendDigits = (digits) => {
    form.amount = `${form.amount ?? ''}${digits}`;
};
const clearAmount = () => {
    form.amount = '';
};

// --- Lab screening fee (2026-10-11) — its own payment, payable before
// screening (the lab is paid first), with a printed receipt. The receipt
// tab is opened inside the click so it isn't blocked as a pop-up.
const hasLabFee = computed(() => props.labFee !== null && props.labFee !== '');
const labFeeText = computed(() => `${Number(props.labFee).toLocaleString()} ${props.currency ?? ''}`.trim());
const payingLab = ref(false);
const labError = ref('');
const payLabFee = async () => {
    labError.value = '';
    payingLab.value = true;
    const receiptWindow = window.open('', '_blank');
    try {
        const { data } = await axios.post(route('payments.store-lab'), {
            patient_registration_id: selectedRegistration.value.id,
            paid_by: form.paid_by || null,
        });
        selectedRegistration.value = { ...selectedRegistration.value, lab_paid: true };
        if (receiptWindow) receiptWindow.location.href = data.data.receipt_url;
        else window.open(data.data.receipt_url, '_blank');
    } catch (e) {
        receiptWindow?.close();
        labError.value = e?.response?.data?.message ?? t('payments.labFeeFailed');
    } finally {
        payingLab.value = false;
    }
};

const submit = () => {
    form.post(route('payments.store'));
};
</script>

<template>
    <Head :title="t('payments.recordPayment')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('payments.recordPayment') }}</h2>
        </template>

        <!-- Restyled to match the chat-list pages (2026-10-13, by request). -->
        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl px-4 sm:px-6 lg:px-8">
                <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100 sm:p-6">
                    <!-- Surfaces PatientScreeningGate's refusal (2026-08-26) —
                         this form previously had no flash-message display at
                         all, so `back()->with('error', ...)` from the
                         screening gate (or anything else) went unseen. -->
                    <div v-if="page.props.flash?.error" class="mb-6 rounded-xl bg-red-50 p-4 text-sm text-red-700">
                        {{ page.props.flash.error }}
                    </div>
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel :value="t('payments.paymentType')" />
                            <div class="mt-2 flex items-center gap-6">
                                <label class="flex items-center gap-2 text-sm text-gray-700">
                                    <input type="radio" value="appointment" v-model="source" class="border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                                    {{ t('payments.appointmentSource') }}
                                </label>
                                <label class="flex items-center gap-2 text-sm text-gray-700">
                                    <input type="radio" value="registration" v-model="source" class="border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                                    {{ t('payments.registrationSource') }}
                                </label>
                            </div>
                        </div>

                        <div v-if="source === 'appointment'">
                            <InputLabel for="appointment_id" :value="t('payments.appointmentLabel')" />
                            <select id="appointment_id" v-model="form.appointment_id" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>{{ t('payments.selectAppointment') }}</option>
                                <option v-for="a in appointments" :key="a.id" :value="a.id">{{ a.full_name }} — {{ a.appointment_date }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.appointment_id" />
                        </div>

                        <div v-else>
                            <InputLabel :value="t('appointments.registeredPatient')" />

                            <!-- A patient was found (scan or search) but
                                 isn't screening-clear — block here rather
                                 than let the clerk fill an amount only to
                                 have PatientScreeningGate reject it at
                                 submit. Mirrors the reception-desk
                                 Flutter screen's _ScreeningBlockedBanner. -->
                            <div
                                v-if="selectedRegistration && !isScreeningClear(selectedRegistration)"
                                class="mt-1 rounded-xl border border-red-200 bg-red-50 p-3"
                            >
                                <div class="flex items-start justify-between gap-2">
                                    <div>
                                        <p class="text-sm font-medium text-gray-900">{{ selectedRegistration.name }}</p>
                                        <p class="text-xs text-gray-500" dir="ltr">{{ selectedRegistration.phone }}</p>
                                    </div>
                                    <button type="button" class="text-sm text-indigo-600 hover:underline" @click="clearRegistration">{{ t('payments.change') }}</button>
                                </div>
                                <p class="mt-2 text-sm text-red-700">
                                    {{
                                        selectedRegistration.screening_status === 'flagged'
                                            ? t('payments.screeningBlockedFlagged')
                                            : t('payments.screeningBlockedNotChecked')
                                    }}
                                </p>
                            </div>

                            <!-- A patient was found (scan or search) and is screening-clear -->
                            <div
                                v-else-if="selectedRegistration"
                                class="mt-1 flex items-center justify-between rounded-xl border border-green-200 bg-green-50 p-3"
                            >
                                <div>
                                    <p class="text-sm font-medium text-gray-900">{{ selectedRegistration.name }}</p>
                                    <p class="text-xs text-gray-500" dir="ltr">{{ selectedRegistration.phone }}</p>
                                </div>
                                <button type="button" class="text-sm text-indigo-600 hover:underline" @click="clearRegistration">{{ t('payments.change') }}</button>
                            </div>

                            <!-- Not found yet: scan or search -->
                            <div v-else class="mt-1 space-y-3">
                                <div v-if="!scanning" class="flex flex-wrap items-center gap-2">
                                    <SecondaryButton type="button" class="rounded-full" @click="openScanner">
                                        <Icon name="qr_code_scanner" class="ml-1" />{{ t('payments.scanPatientCode') }}
                                    </SecondaryButton>
                                    <PhoneScannerLink variant="page" />
                                </div>
                                <QrScanner v-else ref="scannerRef" @decoded="onDecoded" />
                                <div v-if="scanError" class="rounded-xl bg-red-50 p-2 text-sm text-red-700">{{ scanError }}</div>

                                <div class="relative">
                                    <TextInput
                                        v-model="registrationSearch"
                                        @input="onSearchInput"
                                        type="text"
                                        :placeholder="t('payments.orSearchPlaceholder')"
                                        class="block w-full rounded-full"
                                    />
                                    <div v-if="registrationResults.length" class="absolute z-10 mt-1 w-full overflow-hidden rounded-xl border border-gray-200 bg-white shadow-lg">
                                        <button
                                            v-for="r in registrationResults"
                                            :key="r.id"
                                            type="button"
                                            class="block w-full px-4 py-2 text-right text-sm hover:bg-gray-50"
                                            @click="selectRegistration(r)"
                                        >
                                            {{ r.name }} — <span dir="ltr">{{ r.phone }}</span>
                                        </button>
                                    </div>
                                    <p v-else-if="searching" class="mt-1 text-xs text-gray-400">{{ t('payments.searching') }}</p>
                                    <p v-else-if="registrationSearch.trim()" class="mt-1 text-xs text-gray-400">{{ t('patientReg.noMatchingResults') }}</p>
                                </div>
                            </div>
                            <InputError class="mt-2" :message="form.errors.patient_registration_id" />

                            <!-- Lab screening fee -->
                            <div v-if="selectedRegistration && hasLabFee" class="mt-3 rounded-xl border p-3" :class="selectedRegistration.lab_paid ? 'border-sky-200 bg-sky-50' : 'border-amber-200 bg-amber-50'">
                                <div class="flex flex-wrap items-center justify-between gap-2">
                                    <p class="text-sm font-medium text-gray-900">
                                        <Icon name="science" class="ml-1" />{{ t('payments.labFee') }}: <span dir="ltr">{{ labFeeText }}</span>
                                    </p>
                                    <span v-if="selectedRegistration.lab_paid" class="text-sm font-semibold text-sky-700">
                                        <Icon name="check_circle" class="ml-1" />{{ t('payments.labFeePaid') }}
                                    </span>
                                    <button
                                        v-else
                                        type="button"
                                        :disabled="payingLab"
                                        @click="payLabFee"
                                        class="rounded-full bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-amber-700 disabled:opacity-50"
                                    >
                                        <Icon name="print" class="ml-1" />{{ t('payments.payLabFee') }}
                                    </button>
                                </div>
                                <p v-if="labError" class="mt-2 text-sm text-red-700">{{ labError }}</p>
                            </div>
                        </div>

                        <template v-if="!registrationBlocked">
                            <div>
                                <InputLabel for="amount" :value="t('payments.amountCol')" />
                                <TextInput id="amount" v-model="form.amount" type="text" inputmode="decimal" class="mt-1 block w-full rounded-xl" dir="ltr" required autofocus />
                                <div class="mt-2 flex flex-wrap gap-2">
                                    <button
                                        v-for="digits in ['0', '00', '000']"
                                        :key="digits"
                                        type="button"
                                        class="rounded-full border border-gray-300 px-4 py-1 text-sm text-gray-700 hover:bg-gray-50"
                                        @click="appendDigits(digits)"
                                    >
                                        {{ digits }}
                                    </button>
                                    <button type="button" class="rounded-full border border-gray-300 px-4 py-1 text-sm text-gray-700 hover:bg-gray-50" @click="clearAmount">
                                        {{ t('payments.clearAmount') }}
                                    </button>
                                </div>
                                <InputError class="mt-2" :message="form.errors.amount" />
                            </div>

                            <div>
                                <InputLabel for="paid_by" :value="t('payments.paidByCol')" />
                                <TextInput id="paid_by" v-model="form.paid_by" type="text" class="mt-1 block w-full rounded-xl" />
                                <InputError class="mt-2" :message="form.errors.paid_by" />
                            </div>

                            <div class="flex justify-end">
                                <PrimaryButton class="rounded-full" :disabled="form.processing">{{ t('payments.savePayment') }}</PrimaryButton>
                            </div>
                        </template>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
