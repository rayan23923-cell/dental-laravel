<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';
import ChatPager from '@/Components/ChatList/ChatPager.vue';
import BarChart from '@/Components/BarChart.vue';
import Icon from '@/Components/Icon.vue';
import PeriodChips from '@/Components/PeriodChips.vue';
import { Head, router, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { paymentsTitleFor } from '@/paymentsTitle';

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
    // The payments permissions (2026-10-24): report and delete.
    can: { type: Object, default: () => ({ export: true, delete: true }) },
    // The sources this account sees (2026-10-26): null for all, ['lab'] for
    // the lab, ['registration'] for the ticket desk.
    scope: { type: Array, default: null },
});

const title = computed(() => paymentsTitleFor(t, props.scope));
const sourceOptions = computed(() => ['registration', 'lab'].filter((s) => !props.scope || props.scope.includes(s)));

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
const hasFilters = computed(() => !!(props.filters.search || props.filters.from || props.filters.to || (props.filters.source && sourceOptions.value.length > 1)));

const activityUrl = computed(() =>
    route('payments.activity', { from: props.filters.from || undefined, to: props.filters.to || undefined, autoprint: 1 }),
);
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

// Today / this week / this month (2026-11-01, by request).
const setPeriod = (range) => {
    from.value = range.from;
    to.value = range.to;
    applyFilters();
};
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

// Chat-list style (2026-10-13, by request): the table became chat-list
// rows; each payment's source picks the avatar icon and colour.
const sourceOf = (payment) => (payment.type === 'lab' ? 'lab' : payment.appointment_id ? 'appointment' : 'registration');
const sourceIcon = (s) => ({ lab: 'science', appointment: 'event', registration: 'how_to_reg' })[s];
const sourceTone = (s) => ({ lab: 'sky', appointment: 'indigo', registration: 'teal' })[s];
const fmtPaidAt = (value) => new Date(value).toLocaleString();
const receiptUrl = (payment) => route('payments.receipt', { payment: payment.id, autoprint: 1 });

const personName = (payment) => payment.patient_registration?.name ?? payment.appointment?.full_name ?? '—';

const destroy = (payment) => {
    if (confirm(t('payments.deleteConfirm', { amount: payment.amount }))) {
        router.delete(route('payments.destroy', payment.id));
    }
};
</script>

<template>
    <Head :title="title" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ title }}</h2>
                <div class="flex items-center gap-2">
                    <!-- Who added / changed / deleted payments, printed (2026-11-01, by request). -->
                    <a
                        v-if="can.activity"
                        :href="activityUrl"
                        target="_blank"
                        :title="t('payments.printActivity')"
                        class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200"
                    >
                        <Icon name="history" :label="t('payments.printActivity')" />
                    </a>
                    <a
                        v-if="can.export"
                        :href="reportUrl"
                        target="_blank"
                        :title="t('payments.printReport')"
                        class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200"
                    >
                        <Icon name="print" :label="t('payments.printReport')" />
                    </a>
                </div>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- Income: today / week / month / year -->
                <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
                    <div v-for="c in periodCards" :key="c.key" class="rounded-2xl bg-white p-3 shadow-sm ring-1 ring-gray-100">
                        <div class="text-xs text-gray-500">{{ c.label }}</div>
                        <div class="mt-1 text-xl font-bold text-gray-900" dir="ltr" style="text-align: right">{{ plain(periods[c.key]?.total ?? 0) }}</div>
                        <div class="mt-0.5 text-[11px] text-gray-500">{{ currency }} · {{ t('payments.paymentsCount', { n: periods[c.key]?.count ?? 0 }) }}</div>
                    </div>
                </div>

                <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <h3 class="mb-2 flex items-center gap-1.5 text-sm font-semibold text-gray-800"><Icon name="bar_chart" size="text-[18px]" class="text-indigo-500" />{{ t('payments.dailyChart') }}</h3>
                    <BarChart :data="daily" :format="plain" :aria-label="t('payments.dailyChart')" />
                </div>
                <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <h3 class="mb-2 flex items-center gap-1.5 text-sm font-semibold text-gray-800"><Icon name="calendar_month" size="text-[18px]" class="text-indigo-500" />{{ t('payments.monthlyChart') }}</h3>
                    <BarChart :data="monthly" :format="plain" :aria-label="t('payments.monthlyChart')" />
                </div>

                <ChatSearch v-model="search" :placeholder="t('payments.searchPlaceholder')" @submit="applyFilters" />

                <!-- Filters: paid_at range + source -->
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
                    <select
                        v-if="sourceOptions.length > 1"
                        v-model="source"
                        @change="applyFilters"
                        :title="t('payments.sourceLabel')"
                        class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">{{ t('payments.sourceLabel') }}: {{ t('payments.all') }}</option>
                        <option v-for="s in sourceOptions" :key="s" :value="s">{{ sourceLabel(s) }}</option>
                    </select>
                    <ChatAction icon="search" :label="t('payments.searchLabel')" @click="applyFilters" />
                </div>

                <!-- Total of what the filters show, by source -->
                <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <div class="flex flex-wrap items-baseline justify-between gap-2">
                        <span class="text-sm text-gray-600">{{ hasFilters ? t('payments.filteredTotal') : t('payments.allTimeTotal') }}</span>
                        <span class="text-xl font-bold text-gray-900">{{ money(filteredTotal) }}</span>
                    </div>
                    <div class="mt-3 space-y-2">
                        <div v-for="s in bySource" :key="s.source" class="grid grid-cols-[7rem_1fr_auto] items-center gap-3 text-sm">
                            <span class="flex items-center gap-1 text-gray-700"><Icon :name="sourceIcon(s.source)" size="text-[16px]" class="text-gray-400" />{{ sourceLabel(s.source) }}</span>
                            <div class="h-2.5 rounded-full bg-gray-100">
                                <div class="h-2.5 rounded-full bg-gradient-to-l from-indigo-500 to-pink-500" :style="{ width: `${(s.total / sourceMax) * 100}%` }"></div>
                            </div>
                            <span class="text-gray-900">{{ plain(s.total) }} <span class="text-xs text-gray-500">({{ s.count }})</span></span>
                        </div>
                    </div>
                </div>

                <ChatListCard :empty="payments.data.length === 0" :empty-text="t('payments.empty')" empty-icon="payments">
                    <ChatListRow
                        v-for="payment in payments.data"
                        :key="payment.id"
                        :title="personName(payment)"
                        :subtitle="fmtPaidAt(payment.paid_at)"
                        :icon="sourceIcon(sourceOf(payment))"
                        :tone="sourceTone(sourceOf(payment))"
                    >
                        <template #meta>
                            <template v-if="payment.discount?.percent">
                                <ChatChip icon="sell" :title="t('payments.amountBeforeDiscount')"><span class="line-through">{{ plain(payment.discount.full) }}</span></ChatChip>
                                <ChatChip icon="percent" tone="indigo">{{ t('payments.discountChip', { percent: payment.discount.percent, who: payment.discount.who }) }}</ChatChip>
                            </template>
                            <ChatChip icon="payments" tone="emerald" class="font-bold" :title="payment.discount?.percent ? t('payments.amountAfterDiscount') : null">{{ plain(payment.amount) }} {{ currency }}</ChatChip>
                            <ChatChip :icon="sourceIcon(sourceOf(payment))" :tone="sourceTone(sourceOf(payment))">{{ sourceLabel(sourceOf(payment)) }}</ChatChip>
                            <ChatChip v-if="payment.paid_by" icon="person" :title="t('payments.paidByCol')">{{ payment.paid_by }}</ChatChip>
                            <ChatChip v-if="payment.patient_registration?.deleted_at" icon="inventory_2">{{ t('payments.archivedPatient') }}</ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction icon="receipt_long" :label="t('chatList.printReceipt')" :href="receiptUrl(payment)" external />
                            <ChatAction v-if="can.delete" icon="delete" :label="t('common.delete')" danger @click="destroy(payment)" />
                        </template>
                    </ChatListRow>
                    <template #footer>
                        <ChatPager :links="payments.links" />
                    </template>
                </ChatListCard>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
