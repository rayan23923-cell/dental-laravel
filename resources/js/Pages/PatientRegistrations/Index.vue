<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';

const { t } = useI18n();
const props = defineProps({
    can: { type: Object, default: () => ({ archive: true, settings: true, screening: true }) },
    registrations: Object,
    days: { type: Array, default: () => [] },
    filters: Object,
});

const page = usePage();
const search = ref(props.filters.search || '');
const registerDayId = ref(props.filters.register_day_id ?? '');
const serviceId = ref(props.filters.service_id ?? '');
// Archive tab (2026-10-12): deleting archives a registration instead of
// removing it, so its payments stay; archived ones are listed here and
// can be restored.
const archived = computed(() => ['1', 1, true, 'true'].includes(props.filters.archived));

// Day narrows the service dropdown's *options* only — a soft convenience
// cascade, not a hard requirement, since this is a filter (picking a
// service without a day first should still work), unlike the create
// form's picker where day-then-service is actual data entry.
const servicesForSelectedDay = computed(() => {
    if (!registerDayId.value) return props.days.flatMap((d) => d.services ?? []).filter((s, i, arr) => arr.findIndex((x) => x.id === s.id) === i);
    const day = props.days.find((d) => d.id === Number(registerDayId.value));
    return day ? day.services : [];
});

const applyFilters = () => {
    router.get(
        route('patient-registrations.index'),
        {
            ...(search.value ? { search: search.value } : {}),
            ...(registerDayId.value ? { register_day_id: registerDayId.value } : {}),
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

const onDayChange = () => {
    if (!servicesForSelectedDay.value.some((s) => s.id === Number(serviceId.value))) {
        serviceId.value = '';
    }
    applyFilters();
};

const hasFilters = computed(() => !!(search.value || registerDayId.value || serviceId.value));

const clearFilters = () => {
    search.value = '';
    registerDayId.value = '';
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
    ...(registerDayId.value ? { register_day_id: registerDayId.value } : {}),
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
</script>

<template>
    <Head :title="t('patientReg.registryTitle')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('patientReg.registryTitle') }}</h2>
                <div class="flex items-center gap-4">
                    <Link :href="route('patient-registrations.create')">
                        <PrimaryButton>+ {{ t('patientReg.newRegistration') }}</PrimaryButton>
                    </Link>
                    <Link v-if="can.settings" :href="route('patient-registrations.settings')" class="text-sm text-indigo-600 hover:underline">{{ t('patientReg.settingsLink') }}</Link>
                </div>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div class="grid grid-cols-1 gap-3 rounded-lg bg-white p-4 shadow-sm sm:grid-cols-4">
                    <input
                        v-model="search"
                        @input="runSearch"
                        @keyup.enter="applyFilters"
                        type="text"
                        :placeholder="t('patientReg.searchPlaceholder')"
                        class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    />

                    <select v-model="registerDayId" @change="onDayChange" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('patientReg.dayLabel') }}</option>
                        <option v-for="day in days" :key="day.id" :value="day.id">{{ day.name }}</option>
                    </select>

                    <select v-model="serviceId" @change="applyFilters" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('patientReg.serviceLabel') }}</option>
                        <option v-for="service in servicesForSelectedDay" :key="service.id" :value="service.id">{{ service.name }}</option>
                    </select>

                    <SecondaryButton v-if="hasFilters" @click="clearFilters">{{ t('patientReg.clearFilters') }}</SecondaryButton>
                </div>

                <div class="flex gap-2">
                    <button
                        type="button"
                        @click="showArchive(false)"
                        class="rounded-full px-4 py-1.5 text-sm font-medium"
                        :class="!archived ? 'bg-indigo-600 text-white' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-gray-50'"
                    >
                        {{ t('patientReg.currentTab') }}
                    </button>
                    <button
                        type="button"
                        @click="showArchive(true)"
                        class="rounded-full px-4 py-1.5 text-sm font-medium"
                        :class="archived ? 'bg-indigo-600 text-white' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-gray-50'"
                    >
                        <Icon name="inventory_2" class="ml-1" />{{ t('patientReg.archiveTab') }}
                    </button>
                </div>

                <!-- Bulk bar -->
                <div class="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3" :class="selected.length ? 'border-amber-300 bg-amber-50' : 'border-gray-200 bg-white'">
                    <span class="text-sm text-gray-700">
                        <template v-if="selected.length"><Icon name="warning" class="ml-1" />{{ t('doctorsAdmin.selectedCount', { n: selected.length }) }}</template>
                        <template v-else>{{ t('patientReg.totalCount', { n: registrations.total }) }}</template>
                    </span>
                    <div v-if="archived" class="flex flex-wrap gap-2">
                        <button v-if="can.archive && selected.length" type="button" @click="restoreSelected" class="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700">
                            <Icon name="unarchive" class="ml-1" />{{ t('patientReg.restoreSelected') }}
                        </button>
                    </div>
                    <div v-else class="flex flex-wrap gap-2">
                        <button v-if="can.archive && selected.length" type="button" @click="destroySelected" class="rounded-md bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700">
                            <Icon name="inventory_2" class="ml-1" />{{ t('patientReg.archiveSelected') }}
                        </button>
                        <button v-if="can.archive && registrations.total" type="button" @click="destroyAll" class="rounded-md border border-red-600 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50">
                            <Icon name="inventory_2" class="ml-1" />{{ hasFilters ? t('patientReg.deleteAllFiltered') : t('patientReg.deleteAll') }}
                        </button>
                    </div>
                </div>

                <div class="overflow-x-auto bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-4 py-3">
                                    <input type="checkbox" :checked="allOnPageSelected" @change="toggleAll" :title="t('patientReg.selectAll')" class="rounded border-gray-300" />
                                </th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('profile.name') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patients.phoneCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.serviceLabel') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.dayLabel') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('appointments.dateCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.paymentCodeCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.ticketCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.screeningCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="r in registrations.data" :key="r.id" :class="selected.includes(r.id) ? 'bg-indigo-50' : ''">
                                <td class="px-4 py-4">
                                    <input type="checkbox" :value="r.id" v-model="selected" class="rounded border-gray-300" />
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ r.name }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500" dir="ltr">{{ r.phone }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ r.service?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ r.register_day?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ r.created_at }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <button type="button" class="text-indigo-600 hover:underline" @click="qrRegistration = r">
                                        {{ t('common.view') }}
                                    </button>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <a :href="route('patient-registrations.print', r.id)" target="_blank" class="text-indigo-600 hover:underline">
                                        {{ t('common.print') }}
                                    </a>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <span class="rounded-full px-2 py-0.5 text-xs font-medium" :class="screeningBadgeClass(r.screening_status)">
                                        {{ screeningLabel(r.screening_status) }}
                                    </span>
                                    <button v-if="can.screening" type="button" class="mr-2 text-indigo-600 hover:underline" @click="screeningRegistration = r">{{ t('patientReg.setScreening') }}</button>
                                </td>
                            </tr>
                            <tr v-if="registrations.data.length === 0">
                                <td colspan="9" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('patientReg.emptyLog') }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>

                <div v-if="registrations.links?.length > 3" class="flex flex-wrap gap-1">
                    <Link
                        v-for="(link, i) in registrations.links"
                        :key="i"
                        :href="link.url || '#'"
                        v-html="link.label"
                        class="rounded px-3 py-1 text-sm"
                        :class="link.active ? 'bg-indigo-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'"
                    />
                </div>
            </div>
        </div>

        <Modal :show="!!qrRegistration" @close="qrRegistration = null">
            <div class="flex flex-col items-center gap-4 p-6" v-if="qrRegistration">
                <h3 class="text-lg font-semibold text-gray-800">{{ qrRegistration.name }}</h3>
                <img
                    :src="route('patient-registrations.qr', qrRegistration.id)"
                    :alt="t('patientReg.paymentCodeAlt', { name: qrRegistration.name })"
                    class="h-56 w-56"
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
                        class="flex-1 rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
                    >
                        {{ t('patientReg.screeningClear') }}
                    </button>
                    <button
                        type="button"
                        :disabled="screeningSubmitting"
                        @click="confirmScreening('flagged')"
                        class="flex-1 rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
                    >
                        {{ t('patientReg.screeningFlagged') }}
                    </button>
                </div>
                <SecondaryButton @click="screeningRegistration = null">{{ t('common.close') }}</SecondaryButton>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
