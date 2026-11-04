<script setup>
/**
 * Chat-list style (2026-10-13, by request): the registrations table became
 * chat-list rows (checkbox, initial avatar, name + phone, chips for
 * service/day/date/screening) with icon actions; filters are pills.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Modal from '@/Components/Modal.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import Icon from '@/Components/Icon.vue';
import PeriodChips from '@/Components/PeriodChips.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import ChatPager from '@/Components/ChatList/ChatPager.vue';
import { toneFor } from '@/Components/ChatList/tones';
import { Head, router, usePage } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { printInFrame } from '@/printInFrame';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import { useLiveRegistrations } from '@/Composables/useLiveRegistrations';
import { DIAGNOSIS_CODES, DIAGNOSIS_LABELS, diagnosisText } from '@/screeningDiagnosis';

const { t } = useI18n();
const props = defineProps({
    can: { type: Object, default: () => ({ archive: true, settings: true, screening: true }) },
    registrations: Object,
    services: { type: Array, default: () => [] },
    filters: Object,
});

// New and changed registrations show up by themselves (2026-10-19, by request).
useLiveRegistrations(['registrations']);

const page = usePage();

// A patient just registered: their ticket prints straight away.
watch(
    () => page.props.flash?.print_ticket,
    (id) => {
        if (id) printInFrame(route('patient-registrations.print', { patientRegistration: id, autoprint: 1 }));
    },
    { immediate: true },
);
const search = ref(props.filters.search || '');
const from = ref(props.filters.from ?? '');
const to = ref(props.filters.to ?? '');
const serviceId = ref(props.filters.service_id ?? '');
// Archive tab (2026-10-12): deleting archives a registration instead of
// removing it, so its payments stay; archived ones are listed here and
// can be restored.
const archived = computed(() => ['1', 1, true, 'true'].includes(props.filters.archived));

const applyFilters = () => {
    router.get(
        route('patient-registrations.index'),
        {
            ...(search.value ? { search: search.value } : {}),
            ...(from.value ? { from: from.value } : {}),
            ...(to.value ? { to: to.value } : {}),
            ...(serviceId.value ? { service_id: serviceId.value } : {}),
            ...(archived.value ? { archived: 1 } : {}),
        },
        { preserveState: true, replace: true }
    );
};

const showArchive = (value) => {
    selected.value = [];
    router.get(route('patient-registrations.index'), value ? { archived: 1 } : {});
};

let searchTimer;
const runSearch = () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(applyFilters, 300);
};

// Today / this week / this month (2026-11-01, by request).
const setPeriod = (range) => {
    from.value = range.from;
    to.value = range.to;
    applyFilters();
};
const hasFilters = computed(() => !!(search.value || from.value || to.value || serviceId.value));

const clearFilters = () => {
    search.value = '';
    from.value = '';
    to.value = '';
    serviceId.value = '';
    router.get(route('patient-registrations.index'), archived.value ? { archived: 1 } : {});
};

// --- Selection + bulk delete (2026-10-11), same as the doctors table ---
const selected = ref([]);
const allOnPageSelected = computed(
    () => props.registrations.data.length > 0 && selected.value.length === props.registrations.data.length
);
const toggleAll = () => {
    selected.value = allOnPageSelected.value ? [] : props.registrations.data.map((r) => r.id);
};
const currentFilters = () => ({
    ...(search.value ? { search: search.value } : {}),
    ...(from.value ? { from: from.value } : {}),
    ...(to.value ? { to: to.value } : {}),
    ...(serviceId.value ? { service_id: serviceId.value } : {}),
});
// Archiving is the plain archive again (2026-11-04, by request): payments
// kept, restorable from the archive tab. "From where" moved to the
// permanent delete there.
const archiveAsk = ref(null); // { ids } or { all, n }
const destroySelected = () => {
    if (!selected.value.length) return;
    archiveAsk.value = { ids: [...selected.value], n: selected.value.length };
};
const archiveScopeOf = (r) => {
    // One part deleted for good (2026-11-04): only the other is archived.
    if (r.registry_deleted_at) return 'lab';
    if (r.lab_deleted_at) return 'patients';
    if (r.deleted_at || (r.registry_archived_at && r.lab_archived_at)) return 'both';
    if (r.registry_archived_at) return 'patients';
    return r.lab_archived_at ? 'lab' : null;
};
const confirmArchive = () => {
    const ask = archiveAsk.value;
    if (!ask) return;
    archiveAsk.value = null;
    router.delete(route('patient-registrations.destroy-many'), {
        data: ask.all ? { all: true, ...currentFilters() } : { ids: ask.ids },
        preserveScroll: true,
        onSuccess: () => (selected.value = []),
    });
};
const restoreSelected = () => {
    if (!selected.value.length) return;
    router.post(route('patient-registrations.restore-many'), { ids: selected.value }, {
        preserveScroll: true,
        onSuccess: () => (selected.value = []),
    });
};
// Permanent delete from the archive (2026-11-02, by request): asks for the
// user's own password; payments go with the registration.
const purgeAsk = ref(null); // { ids, n } or { all, n }
const purgePassword = ref('');
const purgeError = ref('');
const purgeBusy = ref(false);
// From the patients list, the lab list, or both (2026-11-04, by request).
const purgeScope = ref('both');
const openPurge = (all) => {
    purgeScope.value = 'both';
    purgePassword.value = '';
    purgeError.value = '';
    purgeAsk.value = all ? { all: true, n: props.registrations.total } : { ids: [...selected.value], n: selected.value.length };
};
const confirmPurge = () => {
    const ask = purgeAsk.value;
    if (!ask || !purgePassword.value) return;
    purgeBusy.value = true;
    purgeError.value = '';
    router.delete(route('patient-registrations.purge-many'), {
        data: ask.all
            ? { all: true, password: purgePassword.value, scope: purgeScope.value, ...currentFilters() }
            : { ids: ask.ids, password: purgePassword.value, scope: purgeScope.value },
        preserveScroll: true,
        onSuccess: () => {
            purgeAsk.value = null;
            selected.value = [];
        },
        onError: (errors) => (purgeError.value = errors.password ?? Object.values(errors)[0] ?? t('patientReg.purgeFailed')),
        onFinish: () => {
            purgeBusy.value = false;
            purgePassword.value = '';
        },
    });
};
const destroyAll = () => {
    const n = props.registrations.total;
    if (!n) return;
    archiveAsk.value = { all: true, n };
};

// The desk-payment QR, viewable on screen as well as on the printed
// ticket (Phase 5's plan explicitly calls for both). A plain <img> works
// here — unlike the Flutter client, this page already carries the admin's
// session cookie, so no bearer-token byte-fetch dance is needed.
const qrRegistration = ref(null);

// Infectious-disease screening gate (2026-08-26) — the web twin of
// Flutter's dedicated screening screen. No camera scan needed here: staff
// already see the specific row on screen, so this confirms directly by
// id instead of round-tripping through a QR the desktop browser would
// need a camera for anyway (see `Api\PatientRegistrationQrController`
// docblock / `PatientScreeningGate` on the backend for what this unlocks).
const screeningRegistration = ref(null);
const screeningSubmitting = ref(false);

const screeningLabel = (status) => ({ clear: t('patientReg.screeningClear'), flagged: t('patientReg.screeningFlagged') }[status] ?? t('patientReg.screeningPending'));
const screeningBadgeClass = (status) =>
    ({
        clear: 'bg-green-100 text-green-800',
        flagged: 'bg-red-100 text-red-800',
    }[status] ?? 'bg-amber-100 text-amber-800');
// Chip tone + icon carrying the screening status on each row.
const screeningTone = (status) => ({ clear: 'emerald', flagged: 'rose' }[status] ?? 'amber');
const screeningIcon = (status) => ({ clear: 'verified_user', flagged: 'gpp_bad' }[status] ?? 'hourglass_top');

// "غير سليم" asks which test was positive first (2026-11-03, by request).
const diagnosisPicking = ref(false);
const pickedDiagnoses = ref([]);
const toggleDiagnosis = (code) => {
    pickedDiagnoses.value = pickedDiagnoses.value.includes(code)
        ? pickedDiagnoses.value.filter((c) => c !== code)
        : [...pickedDiagnoses.value, code];
};
const closeScreening = () => {
    screeningRegistration.value = null;
    diagnosisPicking.value = false;
    pickedDiagnoses.value = [];
};

const confirmScreening = async (status, { diagnosed = false } = {}) => {
    if (status === 'flagged' && !diagnosed) {
        pickedDiagnoses.value = [];
        diagnosisPicking.value = true;
        return;
    }
    const diagnoses = status === 'flagged' ? DIAGNOSIS_CODES.filter((c) => pickedDiagnoses.value.includes(c)) : [];
    screeningSubmitting.value = true;
    try {
        const { data } = await axios.post(route('patient-registrations.screening', screeningRegistration.value.id), {
            screening_status: status,
            screening_diagnoses: diagnoses,
        });
        const updated = data.data.registration;
        const row = props.registrations.data.find((r) => r.id === updated.id);
        if (row) {
            row.screening_status = updated.screening_status;
            row.screening_diagnoses = updated.screening_diagnoses;
        }
        closeScreening();
    } finally {
        screeningSubmitting.value = false;
    }
};

// Readable date instead of the raw ISO timestamp, as on the lab page.
const fmtDate = (value) => (value ? new Date(value).toLocaleString('ar-IQ', { dateStyle: 'medium', timeStyle: 'short' }) : '—');
</script>

<template>
    <Head :title="t('patientReg.registryTitle')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('patientReg.registryTitle') }}</h2>
                <div class="flex items-center gap-2">
                    <ChatAddButton v-if="can.settings" :label="t('patientReg.settingsLink')" icon="settings" secondary :href="route('patient-registrations.settings')" />
                    <ChatAddButton :label="t('patientReg.newRegistration')" icon="person_add" :href="route('patient-registrations.create')" />
                </div>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- Current / archive tabs + total -->
                <div class="flex flex-wrap items-center gap-2">
                    <button
                        type="button"
                        @click="showArchive(false)"
                        class="inline-flex items-center gap-1 rounded-full px-4 py-1.5 text-sm font-medium"
                        :class="!archived ? 'bg-indigo-600 text-white shadow-sm' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-gray-50'"
                    >
                        <Icon name="how_to_reg" size="text-[18px]" />{{ t('patientReg.currentTab') }}
                    </button>
                    <button
                        type="button"
                        @click="showArchive(true)"
                        class="inline-flex items-center gap-1 rounded-full px-4 py-1.5 text-sm font-medium"
                        :class="archived ? 'bg-indigo-600 text-white shadow-sm' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-gray-50'"
                    >
                        <Icon name="inventory_2" size="text-[18px]" />{{ t('patientReg.archiveTab') }}
                    </button>
                    <span class="ms-auto text-xs font-medium text-gray-500">{{ t('patientReg.totalCount', { n: registrations.total }) }}</span>
                </div>

                <ChatSearch v-model="search" :placeholder="t('patientReg.searchPlaceholder')" @update:model-value="runSearch" @submit="applyFilters" />

                <!-- Filters (date range, service) + archive all -->
                <PeriodChips :from="from" :to="to" @change="setPeriod" />
                <div class="flex flex-wrap items-center gap-2">
                    <label class="flex items-center gap-1 rounded-full bg-white py-0.5 ps-3 text-xs text-gray-500 shadow-sm ring-1 ring-gray-200">
                        {{ t('payments.fromDate') }}
                        <input v-model="from" type="date" @change="applyFilters" class="rounded-full border-0 bg-transparent py-1 text-sm text-gray-900 focus:ring-2 focus:ring-indigo-500" />
                    </label>
                    <label class="flex items-center gap-1 rounded-full bg-white py-0.5 ps-3 text-xs text-gray-500 shadow-sm ring-1 ring-gray-200">
                        {{ t('payments.toDate') }}
                        <input v-model="to" type="date" @change="applyFilters" class="rounded-full border-0 bg-transparent py-1 text-sm text-gray-900 focus:ring-2 focus:ring-indigo-500" />
                    </label>
                    <select v-model="serviceId" @change="applyFilters" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('patientReg.serviceLabel') }}</option>
                        <option v-for="service in services" :key="service.id" :value="service.id">{{ service.name }}</option>
                    </select>
                    <ChatAction v-if="hasFilters" icon="filter_alt_off" :label="t('patientReg.clearFilters')" @click="clearFilters" />
                    <div v-if="!archived && can.archive && registrations.total" class="ms-auto flex items-center">
                        <ChatAction icon="inventory_2" :label="hasFilters ? t('patientReg.deleteAllFiltered') : t('patientReg.deleteAll')" danger @click="destroyAll" />
                    </div>
                    <div v-if="archived && can.archive && registrations.total" class="ms-auto flex items-center">
                        <ChatAction icon="delete_forever" :label="t('patientReg.purgeAll')" danger @click="openPurge(true)" />
                    </div>
                </div>

                <!-- Bulk bar -->
                <div v-if="selected.length" class="flex items-center justify-between gap-2 rounded-2xl bg-amber-50 px-4 py-2 ring-1 ring-amber-200">
                    <span class="text-sm font-medium text-amber-900">{{ t('doctorsAdmin.selectedCount', { n: selected.length }) }}</span>
                    <div v-if="can.archive" class="flex items-center">
                        <ChatAction v-if="archived" icon="unarchive" :label="t('patientReg.restoreSelected')" @click="restoreSelected" />
                        <ChatAction v-if="archived" icon="delete_forever" :label="t('patientReg.purgeSelected')" danger @click="openPurge(false)" />
                        <ChatAction v-else icon="inventory_2" :label="t('patientReg.archiveSelected')" danger @click="destroySelected" />
                    </div>
                </div>

                <ChatListCard :empty="registrations.data.length === 0" :empty-text="t('patientReg.emptyLog')" empty-icon="how_to_reg">
                    <label v-if="registrations.data.length" class="flex cursor-pointer items-center gap-3 border-b border-gray-100 px-4 py-2 text-xs font-medium text-gray-500">
                        <input type="checkbox" :checked="allOnPageSelected" @change="toggleAll" class="rounded border-gray-300 text-indigo-600" />
                        {{ t('patientReg.selectAll') }}
                    </label>
                    <ChatListRow
                        v-for="r in registrations.data"
                        :key="r.id"
                        :title="r.name"
                        :tone="toneFor(r.id)"
                        :selected="selected.includes(r.id)"
                    >
                        <template #leading>
                            <input type="checkbox" :value="r.id" v-model="selected" class="rounded border-gray-300 text-indigo-600" />
                        </template>
                        <template #meta>
                            <ChatChip v-if="r.phone" icon="call"><span dir="ltr">{{ r.phone }}</span></ChatChip>
                            <ChatChip v-if="r.service" icon="medical_services" tone="sky">{{ r.service.name }}</ChatChip>
                            <ChatChip v-if="r.discount_eligible" :icon="r.discount_type === 'employee' ? 'badge' : 'school'" tone="indigo">
                                {{ [t(r.discount_type === 'employee' ? 'patientReg.discountEmployee' : 'patientReg.discountStudent'), r.discount_person_name, r.discount_stage || r.discount_workplace].filter(Boolean).join(' · ') }}
                            </ChatChip>
                            <ChatChip icon="schedule">{{ fmtDate(r.created_at) }}</ChatChip>
                            <ChatChip :icon="screeningIcon(r.screening_status)" :tone="screeningTone(r.screening_status)">{{ screeningLabel(r.screening_status) }}<template v-if="diagnosisText(r)"> — {{ diagnosisText(r) }}</template></ChatChip>
                            <ChatChip v-if="archiveScopeOf(r)" icon="inventory_2" tone="amber">{{ t('patientReg.archivedFrom.' + archiveScopeOf(r)) }}</ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction icon="qr_code_2" :label="t('patientReg.paymentCodeCol')" @click="qrRegistration = r" />
                            <ChatAction icon="print" :label="t('patientReg.ticketCol')" :href="route('patient-registrations.print', r.id)" external />
                            <ChatAction v-if="can.screening" icon="health_and_safety" :label="t('patientReg.setScreening')" @click="screeningRegistration = r" />
                        </template>
                    </ChatListRow>
                    <template #footer>
                        <ChatPager :links="registrations.links" />
                    </template>
                </ChatListCard>
            </div>
        </div>

        <!-- Archive (plain again, 2026-11-04, by request) -->
        <Modal :show="!!archiveAsk" max-width="md" @close="archiveAsk = null">
            <div v-if="archiveAsk" class="flex flex-col gap-3 p-6">
                <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-800">
                    <Icon name="inventory_2" />{{ t('patientReg.archiveTitle', { n: archiveAsk.n }) }}
                </h3>
                <p class="text-sm text-gray-500">{{ t('patientReg.archiveFromHint') }}</p>
                <div class="grid grid-cols-2 gap-3">
                    <button type="button" @click="confirmArchive" class="rounded-xl bg-amber-600 px-4 py-2.5 font-semibold text-white hover:bg-amber-700">
                        {{ t('patientReg.archiveConfirm') }}
                    </button>
                    <SecondaryButton class="justify-center" @click="archiveAsk = null">{{ t('common.cancel') }}</SecondaryButton>
                </div>
            </div>
        </Modal>

        <!-- Permanent delete, behind the user's password (2026-11-02, by request) -->
        <Modal :show="!!purgeAsk" max-width="md" @close="purgeAsk = null">
            <form v-if="purgeAsk" class="flex flex-col gap-3 p-6" @submit.prevent="confirmPurge">
                <h3 class="flex items-center gap-2 text-lg font-semibold text-red-700">
                    <Icon name="delete_forever" />{{ t('patientReg.purgeTitle', { n: purgeAsk.n }) }}
                </h3>
                <!-- From where (2026-11-04, by request) -->
                <p class="text-sm font-medium text-gray-700">{{ t('patientReg.purgeFromHint') }}</p>
                <label
                    v-for="opt in [
                        { key: 'patients', icon: 'groups', tone: 'border-sky-300 bg-sky-50 text-sky-900' },
                        { key: 'lab', icon: 'science', tone: 'border-emerald-300 bg-emerald-50 text-emerald-900' },
                        { key: 'both', icon: 'delete_forever', tone: 'border-red-300 bg-red-50 text-red-900' },
                    ]"
                    :key="opt.key"
                    class="flex cursor-pointer items-center gap-3 rounded-xl border-2 px-4 py-2.5 font-semibold"
                    :class="purgeScope === opt.key ? opt.tone : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'"
                >
                    <input v-model="purgeScope" type="radio" name="purge-scope" :value="opt.key" class="text-red-600 focus:ring-red-500" />
                    <Icon :name="opt.icon" />
                    <span>{{ t('patientReg.purgeFrom.' + opt.key) }}<span class="block text-xs font-normal opacity-80">{{ t('patientReg.purgeFromDesc.' + opt.key) }}</span></span>
                </label>
                <p class="rounded-xl bg-red-50 p-3 text-sm text-red-800">{{ t('patientReg.purgeWarningFrom.' + purgeScope) }}</p>
                <label class="text-sm font-medium text-gray-700" for="purge-password">{{ t('patientReg.purgePassword') }}</label>
                <input
                    id="purge-password"
                    v-model="purgePassword"
                    type="password"
                    autocomplete="current-password"
                    autofocus
                    class="rounded-xl border-gray-300 focus:border-red-500 focus:ring-red-500"
                />
                <p v-if="purgeError" class="text-sm text-red-600">{{ purgeError }}</p>
                <div class="grid grid-cols-2 gap-3">
                    <button type="submit" :disabled="purgeBusy || !purgePassword" class="rounded-xl bg-red-700 px-4 py-2.5 font-semibold text-white hover:bg-red-800 disabled:opacity-50">
                        {{ t('patientReg.purgeConfirm') }}
                    </button>
                    <SecondaryButton class="justify-center" @click="purgeAsk = null">{{ t('common.cancel') }}</SecondaryButton>
                </div>
            </form>
        </Modal>

        <Modal :show="!!qrRegistration" @close="qrRegistration = null">
            <div class="flex flex-col items-center gap-4 p-6" v-if="qrRegistration">
                <h3 class="text-lg font-semibold text-gray-800">{{ qrRegistration.name }}</h3>
                <img
                    :src="route('patient-registrations.qr', qrRegistration.id)"
                    :alt="t('patientReg.paymentCodeAlt', { name: qrRegistration.name })"
                    class="h-56 w-56 rounded-xl"
                />
                <p class="text-sm text-gray-500">{{ t('patientReg.scanAtPayment') }}</p>
                <SecondaryButton @click="qrRegistration = null">{{ t('common.close') }}</SecondaryButton>
            </div>
        </Modal>

        <!-- Infectious-disease screening gate (2026-08-26) -->
        <Modal :show="!!screeningRegistration" @close="closeScreening()">
            <div class="flex flex-col gap-4 p-6" v-if="screeningRegistration">
                <h3 class="text-lg font-semibold text-gray-800">{{ t('patientReg.screeningModalTitle', { name: screeningRegistration.name }) }}</h3>
                <p class="text-sm text-gray-500">
                    {{ t('patientReg.currentStatus') }}
                    <span class="rounded-full px-2 py-0.5 text-xs font-medium" :class="screeningBadgeClass(screeningRegistration.screening_status)">
                        {{ screeningLabel(screeningRegistration.screening_status) }}
                    </span>
                    <span v-if="diagnosisText(screeningRegistration)" class="mr-1 font-semibold text-red-800">{{ t('lab.diagnosis') }}: {{ diagnosisText(screeningRegistration) }}</span>
                </p>
                <!-- A recorded result is final (2026-11-01, by request). -->
                <p v-if="screeningRegistration.screening_status !== 'pending'" class="rounded-xl bg-gray-50 p-3 text-sm text-gray-600">
                    {{ t('lab.resultLocked') }}
                </p>
                <div v-else class="flex gap-3">
                    <button
                        type="button"
                        :disabled="screeningSubmitting"
                        @click="confirmScreening('clear')"
                        class="flex-1 rounded-xl bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
                    >
                        {{ t('patientReg.screeningClear') }}
                    </button>
                    <button
                        type="button"
                        :disabled="screeningSubmitting"
                        @click="confirmScreening('flagged')"
                        class="flex-1 rounded-xl bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
                    >
                        {{ t('patientReg.screeningFlagged') }}
                    </button>
                </div>
                <div v-if="diagnosisPicking && screeningRegistration.screening_status === 'pending'" class="flex flex-col gap-3 rounded-xl border-2 border-red-300 bg-red-50 p-4 text-sm text-red-900">
                    <span class="font-semibold">{{ t('lab.diagnosisTitle') }}</span>
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
                            {{ code }}
                            <span class="block text-xs font-normal opacity-90">{{ DIAGNOSIS_LABELS[code] }}</span>
                        </button>
                    </div>
                    <button
                        type="button"
                        :disabled="screeningSubmitting || pickedDiagnoses.length === 0"
                        @click="confirmScreening('flagged', { diagnosed: true })"
                        class="rounded-xl bg-red-700 px-4 py-2 font-semibold text-white hover:bg-red-800 disabled:opacity-50"
                    >
                        {{ t('lab.diagnosisConfirm') }}
                    </button>
                </div>
                <SecondaryButton @click="closeScreening()">{{ t('common.close') }}</SecondaryButton>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
