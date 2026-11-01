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
const destroySelected = () => {
    if (!selected.value.length) return;
    if (confirm(t('patientReg.deleteSelectedConfirm', { n: selected.value.length }))) {
        router.delete(route('patient-registrations.destroy-many'), {
            data: { ids: selected.value },
            preserveScroll: true,
            onSuccess: () => (selected.value = []),
        });
    }
};
const restoreSelected = () => {
    if (!selected.value.length) return;
    router.post(route('patient-registrations.restore-many'), { ids: selected.value }, {
        preserveScroll: true,
        onSuccess: () => (selected.value = []),
    });
};
const destroyAll = () => {
    const n = props.registrations.total;
    if (!n) return;
    if (confirm(t('patientReg.deleteAllConfirm', { n }))) {
        router.delete(route('patient-registrations.destroy-many'), {
            data: { all: true, ...currentFilters() },
            preserveScroll: true,
            onSuccess: () => (selected.value = []),
        });
    }
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

const confirmScreening = async (status) => {
    screeningSubmitting.value = true;
    try {
        const { data } = await axios.post(route('patient-registrations.screening', screeningRegistration.value.id), {
            screening_status: status,
        });
        const updated = data.data.registration;
        const row = props.registrations.data.find((r) => r.id === updated.id);
        if (row) row.screening_status = updated.screening_status;
        screeningRegistration.value = null;
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
                </div>

                <!-- Bulk bar -->
                <div v-if="selected.length" class="flex items-center justify-between gap-2 rounded-2xl bg-amber-50 px-4 py-2 ring-1 ring-amber-200">
                    <span class="text-sm font-medium text-amber-900">{{ t('doctorsAdmin.selectedCount', { n: selected.length }) }}</span>
                    <div v-if="can.archive" class="flex items-center">
                        <ChatAction v-if="archived" icon="unarchive" :label="t('patientReg.restoreSelected')" @click="restoreSelected" />
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
                            <ChatChip :icon="screeningIcon(r.screening_status)" :tone="screeningTone(r.screening_status)">{{ screeningLabel(r.screening_status) }}</ChatChip>
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
        <Modal :show="!!screeningRegistration" @close="screeningRegistration = null">
            <div class="flex flex-col gap-4 p-6" v-if="screeningRegistration">
                <h3 class="text-lg font-semibold text-gray-800">{{ t('patientReg.screeningModalTitle', { name: screeningRegistration.name }) }}</h3>
                <p class="text-sm text-gray-500">
                    {{ t('patientReg.currentStatus') }}
                    <span class="rounded-full px-2 py-0.5 text-xs font-medium" :class="screeningBadgeClass(screeningRegistration.screening_status)">
                        {{ screeningLabel(screeningRegistration.screening_status) }}
                    </span>
                </p>
                <div class="flex gap-3">
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
                <SecondaryButton @click="screeningRegistration = null">{{ t('common.close') }}</SecondaryButton>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
