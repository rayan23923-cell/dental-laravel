<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import BarChart from '@/Components/BarChart.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    payments: Object,
    filters: { type: Object, default: () => ({}) },
    periods: { type: Object, default: () => ({}) },
    daily: { type: Array, default: () => [] },
    monthly: { type: Array, default: () => [] },
    filteredTotal: { type: Number, default: 0 },
    bySource: { type: Array, default: () => [] },
    currency: { type: String, default: '' },
});

// Income overview (2026-10-12, by request).
const money = (v) => `${Number(v).toLocaleString('en-US', { maximumFractionDigits: 2 })} ${props.currency ?? ''}`.trim();
const plain = (v) => Number(v).toLocaleString('en-US', { maximumFractionDigits: 0 });
const periodCards = computed(() => [
    { key: 'today', label: t('payments.today') },
    { key: 'week', label: t('payments.thisWeek') },
    { key: 'month', label: t('payments.thisMonth') },
    { key: 'year', label: t('payments.thisYear') },
]);
const sourceLabel = (s) => ({ registration: t('payments.registrationSource'), lab: t('payments.labFee'), appointment: t('payments.appointmentSource') })[s];
const sourceMax = computed(() => Math.max(1, ...props.bySource.map((s) => s.total)));
const hasFilters = computed(() => !!(props.filters.search || props.filters.from || props.filters.to || props.filters.source));

// Printable report with the same filters; the browser's print dialog
// also saves it as PDF.
const reportUrl = computed(() =>
    route('payments.report', {
        ...(props.filters.search ? { search: props.filters.search } : {}),
        ...(props.filters.from ? { from: props.filters.from } : {}),
        ...(props.filters.to ? { to: props.filters.to } : {}),
        ...(props.filters.source ? { source: props.filters.source } : {}),
        autoprint: 1,
    }),
);

const page = usePage();

// Lets a person's whole payment history — appointment- or
// registration-sourced alike — surface in one search, regardless of
// which of the two a given payment settled.
const search = ref(props.filters.search ?? '');

// Filtering (2026-08-29) — date range on `paid_at` (the only date this
// table has) and which of the two mutually-exclusive sources a payment
// settled. No doctor or paid/unpaid filter exists — see
// Api\PaymentController::index()'s matching comment for why not.
const from = ref(props.filters.from ?? '');
const to = ref(props.filters.to ?? '');
const source = ref(props.filters.source ?? '');

const applyFilters = () => {
    router.get(
        route('payments.index'),
        {
            search: search.value || undefined,
            from: from.value || undefined,
            to: to.value || undefined,
            source: source.value || undefined,
        },
        { preserveState: true, replace: true },
    );
};

const personName = (payment) => payment.patient_registration?.name ?? payment.appointment?.full_name ?? '—';

const destroy = (payment) => {
    if (confirm(t('payments.deleteConfirm', { amount: payment.amount }))) {
        router.delete(route('payments.destroy', payment.id));
    }
};
</script>

<template>
    <Head :title="t('nav.payments')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('nav.payments') }}</h2>
                <div class="flex flex-wrap items-center gap-2">
                    <a :href="reportUrl" target="_blank" class="inline-flex items-center rounded-md border border-gray-300 bg-white px-4 py-2 text-xs font-semibold uppercase tracking-widest text-gray-700 shadow-sm hover:bg-gray-50">
                        <Icon name="print" class="ml-1" />{{ t('payments.printReport') }}
                    </a>
                    <Link :href="route('payments.create')">
                        <PrimaryButton>{{ t('payments.recordPayment') }}</PrimaryButton>
                    </Link>
                </div>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <!-- Income: today / week / month / year -->
                <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
                    <div v-for="c in periodCards" :key="c.key" class="rounded-lg bg-white p-4 shadow-sm">
                        <div class="text-sm text-gray-500">{{ c.label }}</div>
                        <div class="mt-1 text-2xl font-bold text-gray-900" dir="ltr" style="text-align: right">{{ plain(periods[c.key]?.total ?? 0) }}</div>
                        <div class="mt-1 text-xs text-gray-500">{{ currency }} · {{ t('payments.paymentsCount', { n: periods[c.key]?.count ?? 0 }) }}</div>
                    </div>
                </div>

                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <h3 class="mb-2 text-sm font-semibold text-gray-800">{{ t('payments.dailyChart') }}</h3>
                        <BarChart :data="daily" :format="plain" :aria-label="t('payments.dailyChart')" />
                    </div>
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <h3 class="mb-2 text-sm font-semibold text-gray-800">{{ t('payments.monthlyChart') }}</h3>
                        <BarChart :data="monthly" :format="plain" :aria-label="t('payments.monthlyChart')" />
                    </div>
                </div>

                <div class="flex flex-wrap items-end gap-3 rounded-lg bg-white p-4 shadow-sm">
                    <div class="min-w-[12rem] flex-1">
                        <label class="block text-xs font-medium text-gray-500">{{ t('payments.searchLabel') }}</label>
                        <input
                            v-model="search"
                            @keyup.enter="applyFilters"
                            type="text"
                            :placeholder="t('payments.searchPlaceholder')"
                            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        />
                    </div>
                    <div>
                        <label class="block text-xs font-medium text-gray-500">{{ t('payments.fromDate') }}</label>
                        <input
                            v-model="from"
                            type="date"
                            class="mt-1 block rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        />
                    </div>
                    <div>
                        <label class="block text-xs font-medium text-gray-500">{{ t('payments.toDate') }}</label>
                        <input
                            v-model="to"
                            type="date"
                            class="mt-1 block rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        />
                    </div>
                    <div>
                        <label class="block text-xs font-medium text-gray-500">{{ t('payments.sourceLabel') }}</label>
                        <select
                            v-model="source"
                            class="mt-1 block rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        >
                            <option value="">{{ t('payments.all') }}</option>
                            <option value="appointment">{{ t('payments.appointmentSource') }}</option>
                            <option value="registration">{{ t('payments.registrationSource') }}</option>
                            <option value="lab">{{ t('payments.labFee') }}</option>
                        </select>
                    </div>
                    <button
                        @click="applyFilters"
                        type="button"
                        class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
                    >
                        {{ t('payments.searchLabel') }}
                    </button>
                </div>

                <!-- Total of what the filters show, by source -->
                <div class="rounded-lg bg-white p-4 shadow-sm">
                    <div class="flex flex-wrap items-baseline justify-between gap-2">
                        <span class="text-sm text-gray-600">{{ hasFilters ? t('payments.filteredTotal') : t('payments.allTimeTotal') }}</span>
                        <span class="text-xl font-bold text-gray-900">{{ money(filteredTotal) }}</span>
                    </div>
                    <div class="mt-3 space-y-2">
                        <div v-for="s in bySource" :key="s.source" class="grid grid-cols-[7rem_1fr_auto] items-center gap-3 text-sm">
                            <span class="text-gray-700">{{ sourceLabel(s.source) }}</span>
                            <div class="h-3 rounded-full bg-gray-100">
                                <div class="h-3 rounded-full bg-indigo-500" :style="{ width: `${(s.total / sourceMax) * 100}%` }"></div>
                            </div>
                            <span class="text-gray-900">{{ plain(s.total) }} <span class="text-xs text-gray-500">({{ s.count }})</span></span>
                        </div>
                    </div>
                </div>

                <div class="overflow-x-auto bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('payments.personCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('payments.sourceLabel') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('payments.amountCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('payments.paidByCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('payments.paidAtCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patients.actionsCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="payment in payments.data" :key="payment.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">
                                    {{ personName(payment) }}
                                    <span v-if="payment.patient_registration?.deleted_at" class="mr-1 rounded-full bg-gray-100 px-2 py-0.5 text-xs font-normal text-gray-600">{{ t('payments.archivedPatient') }}</span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ payment.type === 'lab' ? t('payments.labFee') : payment.appointment_id ? t('payments.appointmentSource') : t('payments.registrationSource') }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ plain(payment.amount) }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ payment.paid_by ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ new Date(payment.paid_at).toLocaleString() }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <button @click="destroy(payment)" class="text-red-600 hover:text-red-900">{{ t('common.delete') }}</button>
                                </td>
                            </tr>
                            <tr v-if="payments.data.length === 0">
                                <td colspan="6" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('payments.empty') }}</td>
                            </tr>
                        </tbody>
                    </table>

                    <div class="flex justify-between border-t border-gray-200 p-4">
                        <Link
                            v-for="link in payments.links"
                            :key="link.label"
                            :href="link.url ?? ''"
                            v-html="link.label"
                            class="mx-1 rounded px-3 py-1 text-sm"
                            :class="{
                                'bg-indigo-600 text-white': link.active,
                                'text-gray-400 pointer-events-none': !link.url,
                                'text-gray-700 hover:bg-gray-100': link.url && !link.active,
                            }"
                        />
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
