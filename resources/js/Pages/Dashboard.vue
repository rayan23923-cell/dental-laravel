<script setup>
/**
 * Admin dashboard, in the chat-list style of the other pages (2026-10-13,
 * by request): small counter tiles, the quick-access links as rows (with
 * payments), "أحدث المراجعين" from the patient registry with each row
 * opening it in سجل المرضى, the latest payments, the latest doctors and
 * the per-education-type department/stage task section, loaded on demand.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import { toneFor } from '@/Components/ChatList/tones';
import { Head, Link } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import Icon from '@/Components/Icon.vue';
import { useLiveRegistrations } from '@/Composables/useLiveRegistrations';

const { t } = useI18n();
const props = defineProps({
    stats: Object,
    latestDoctors: Array,
    latestPatients: Array,
    latestPayments: { type: Array, default: () => [] },
    income: { type: Object, default: null },
    currency: { type: String, default: '' },
    educationTypes: Array,
    can: Object,
    currentSession: Object,
});

// The counters, latest patients and payments follow new registrations by themselves (2026-10-19, by request).
if (props.can?.patients) useLiveRegistrations(['stats', 'latestPatients', 'latestPayments', 'income']);

const donePct = computed(() => {
    const total = props.stats.tasks_done + props.stats.tasks_not_done;
    return total > 0 ? Math.round((props.stats.tasks_done / total) * 100) : 0;
});

const instanceTotal = computed(
    () => props.stats.instances_completed + props.stats.instances_assigned + props.stats.instances_pending
);

const plain = (v) => Number(v ?? 0).toLocaleString('en-US', { maximumFractionDigits: 0 });
const fmtDate = (v) => (v ? new Date(v).toLocaleString('ar-IQ', { dateStyle: 'medium', timeStyle: 'short' }) : '—');

const tiles = computed(() => [
    { label: t('dashboard.doctorsCount'), value: plain(props.stats.doctors), icon: 'stethoscope', gradient: 'from-indigo-500 to-purple-500', href: props.can.doctors ? route('doctors.index') : null },
    {
        label: t('dashboard.patientsCount'),
        value: plain(props.stats.registrations),
        hint: t('dashboard.todayCount', { n: plain(props.stats.registrations_today) }),
        icon: 'how_to_reg',
        gradient: 'from-sky-500 to-cyan-500',
        href: props.can.patients ? route('patient-registrations.index') : null,
    },
    { label: t('dashboard.tasksCount'), value: plain(props.stats.tasks), hint: `${donePct.value}% ${t('dashboard.done')}`, icon: 'assignment', gradient: 'from-emerald-500 to-teal-500', href: props.can.task_progress ? route('task-progress.index') : null },
    ...(props.can.payments && props.income
        ? [{
            label: t('dashboard.todayIncome'),
            value: `${plain(props.income.today.total)} ${props.currency ?? ''}`.trim(),
            hint: t('dashboard.monthIncome', { amount: `${plain(props.income.month.total)} ${props.currency ?? ''}`.trim() }),
            icon: 'payments',
            gradient: 'from-amber-500 to-orange-500',
            href: route('payments.index'),
        }]
        : []),
]);

const shortcuts = computed(() => [
    props.can.patients && { title: t('nav.patientRegistrations'), subtitle: t('dashboard.registerPatientDesc'), icon: 'how_to_reg', tone: 'indigo', href: route('patient-registrations.index') },
    props.can.payments && { title: t('nav.payments'), subtitle: t('dashboard.paymentsDesc'), icon: 'payments', tone: 'amber', href: route('payments.index') },
    props.can.patient_screening && { title: t('dashboard.lab'), subtitle: t('dashboard.labDesc'), icon: 'coronavirus', tone: 'rose', href: route('lab.index') },
    props.can.task_progress && { title: t('dashboard.taskProgressMgmt'), subtitle: t('dashboard.taskProgressMgmtDesc'), icon: 'fact_check', tone: 'sky', href: route('task-progress.index') },
    props.can.doctors && { title: t('dashboard.doctorsProgress'), subtitle: t('dashboard.doctorsProgressDesc'), icon: 'stethoscope', tone: 'emerald', href: route('doctors.index') },
    props.can.settings && { title: t('nav.settingsGroup'), subtitle: t('dashboard.settingsDesc'), icon: 'settings', tone: 'gray', href: route('clinic-settings.edit') },
].filter(Boolean));

// Each latest registration opens سجل المرضى searched to that patient.
const registrationHref = (p) => (props.can.patients ? route('patient-registrations.index', { search: p.name }) : null);
const screeningTone = (s) => ({ clear: 'emerald', flagged: 'rose' }[s] ?? 'amber');
const screeningIcon = (s) => ({ clear: 'verified_user', flagged: 'gpp_bad' }[s] ?? 'hourglass_top');
const screeningLabel = (s) => ({ clear: t('patientReg.screeningClear'), flagged: t('patientReg.screeningFlagged') }[s] ?? t('patientReg.screeningPending'));

const sourceIcon = (s) => ({ lab: 'science', appointment: 'event', registration: 'how_to_reg' })[s];
const sourceTone = (s) => ({ lab: 'sky', appointment: 'indigo', registration: 'teal' })[s];
const sourceLabel = (s) => ({ registration: t('payments.registrationSource'), lab: t('payments.labFee'), appointment: t('payments.appointmentSource') })[s];

// --- المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة ---
const selectedEduType = ref('');
const loadingDepts = ref(false);
const departments = ref(null);
const openDept = ref(null);

const loadTasksByDept = async (id) => {
    selectedEduType.value = id;
    openDept.value = null;
    loadingDepts.value = true;
    try {
        const { data } = await axios.get(route('dashboard.tasks-by-education-type', id));
        departments.value = data.departments;
    } finally {
        loadingDepts.value = false;
    }
};
</script>

<template>
    <Head :title="t('dashboard.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex flex-wrap items-center justify-between gap-2">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('dashboard.title') }}</h2>
                <ChatChip v-if="currentSession" icon="calendar_month" tone="indigo">{{ currentSession.name }}</ChatChip>
            </div>
        </template>

        <div class="py-6">
            <div class="mx-auto max-w-5xl space-y-5 px-4 sm:px-6 lg:px-8">
                <!-- Counters -->
                <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
                    <component
                        :is="tile.href ? Link : 'div'"
                        v-for="tile in tiles"
                        :key="tile.label"
                        :href="tile.href ?? undefined"
                        class="flex items-center gap-3 rounded-2xl bg-white p-3 shadow-sm ring-1 ring-gray-100 transition"
                        :class="tile.href ? 'hover:bg-gray-50' : ''"
                    >
                        <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-gradient-to-br text-white" :class="tile.gradient">
                            <Icon :name="tile.icon" size="text-[22px]" />
                        </div>
                        <div class="min-w-0">
                            <div class="text-base font-bold leading-tight text-gray-900 sm:text-lg">{{ tile.value }}</div>
                            <div class="truncate text-xs text-gray-500">{{ tile.label }}</div>
                            <div v-if="tile.hint" class="truncate text-[11px] text-gray-400">{{ tile.hint }}</div>
                        </div>
                    </component>
                </div>

                <!-- Quick access -->
                <ChatListCard v-if="shortcuts.length">
                    <ChatListRow
                        v-for="s in shortcuts"
                        :key="s.href"
                        :title="s.title"
                        :subtitle="s.subtitle"
                        :icon="s.icon"
                        :tone="s.tone"
                        :href="s.href"
                    />
                </ChatListCard>

                <div class="grid grid-cols-1 gap-5 lg:grid-cols-2">
                    <!-- أحدث المراجعين -->
                    <section v-if="can.patients">
                        <div class="mb-2 flex items-center justify-between px-1">
                            <h3 class="text-sm font-semibold text-gray-700">{{ t('dashboard.latestPatients') }}</h3>
                            <Link v-if="can.patients" :href="route('patient-registrations.index')" class="text-xs font-medium text-indigo-600 hover:underline">{{ t('dashboard.viewAll') }}</Link>
                        </div>
                        <ChatListCard :empty="latestPatients.length === 0" :empty-text="t('dashboard.noPatientsYet')" empty-icon="person_off">
                            <ChatListRow
                                v-for="p in latestPatients"
                                :key="p.id"
                                :title="p.name"
                                :tone="toneFor(p.id)"
                                :href="registrationHref(p)"
                            >
                                <template #meta>
                                    <ChatChip v-if="p.phone" icon="call">{{ p.phone }}</ChatChip>
                                    <ChatChip v-if="p.service" icon="medical_services" tone="sky">{{ p.service }}</ChatChip>
                                    <ChatChip :icon="screeningIcon(p.screening_status)" :tone="screeningTone(p.screening_status)">{{ screeningLabel(p.screening_status) }}</ChatChip>
                                    <ChatChip icon="schedule">{{ fmtDate(p.created_at) }}</ChatChip>
                                </template>
                            </ChatListRow>
                        </ChatListCard>
                    </section>

                    <!-- أحدث المدفوعات -->
                    <section v-if="can.payments">
                        <div class="mb-2 flex items-center justify-between px-1">
                            <h3 class="text-sm font-semibold text-gray-700">{{ t('dashboard.latestPayments') }}</h3>
                            <Link :href="route('payments.index')" class="text-xs font-medium text-indigo-600 hover:underline">{{ t('dashboard.viewAll') }}</Link>
                        </div>
                        <ChatListCard :empty="latestPayments.length === 0" :empty-text="t('dashboard.noPaymentsYet')" empty-icon="payments">
                            <ChatListRow
                                v-for="pay in latestPayments"
                                :key="pay.id"
                                :title="pay.name ?? '—'"
                                :icon="sourceIcon(pay.source)"
                                :tone="sourceTone(pay.source)"
                                :href="route('payments.index', { search: pay.name ?? undefined })"
                            >
                                <template #meta>
                                    <ChatChip icon="payments" tone="emerald" class="font-bold">{{ plain(pay.amount) }} {{ currency }}</ChatChip>
                                    <ChatChip :icon="sourceIcon(pay.source)" :tone="sourceTone(pay.source)">{{ sourceLabel(pay.source) }}</ChatChip>
                                    <ChatChip icon="schedule">{{ fmtDate(pay.paid_at) }}</ChatChip>
                                </template>
                            </ChatListRow>
                        </ChatListCard>
                    </section>

                    <!-- أحدث الأطباء -->
                    <section>
                        <div class="mb-2 flex items-center justify-between px-1">
                            <h3 class="text-sm font-semibold text-gray-700">{{ t('dashboard.latestDoctors') }}</h3>
                            <Link v-if="can.doctors" :href="route('doctors.index')" class="text-xs font-medium text-indigo-600 hover:underline">{{ t('dashboard.viewAll') }}</Link>
                        </div>
                        <ChatListCard :empty="latestDoctors.length === 0" :empty-text="t('dashboard.noDoctorsYet')" empty-icon="stethoscope">
                            <ChatListRow
                                v-for="d in latestDoctors"
                                :key="d.id"
                                :title="d.name"
                                :tone="toneFor(d.id)"
                                :href="can.doctors ? route('doctors.index', { search: d.name }) : null"
                            >
                                <template #meta>
                                    <ChatChip v-if="d.education_type" icon="school" tone="violet">{{ d.education_type }}</ChatChip>
                                    <ChatChip icon="schedule">{{ fmtDate(d.created_at) }}</ChatChip>
                                </template>
                            </ChatListRow>
                        </ChatListCard>
                    </section>

                    <!-- حالات المهام -->
                    <section>
                        <div class="mb-2 px-1">
                            <h3 class="text-sm font-semibold text-gray-700">{{ t('dashboard.taskStatuses') }}</h3>
                        </div>
                        <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                            <div class="flex items-center justify-between text-xs text-gray-500">
                                <span>{{ t('dashboard.doneVsNotDone') }}</span>
                                <span class="font-semibold text-emerald-700">{{ donePct }}%</span>
                            </div>
                            <div class="mt-2 h-2 overflow-hidden rounded-full bg-gray-100">
                                <div class="h-full rounded-full bg-gradient-to-l from-emerald-500 to-teal-500" :style="{ width: donePct + '%' }" />
                            </div>
                            <div class="mt-2 flex flex-wrap gap-1.5">
                                <ChatChip icon="task_alt" tone="emerald">{{ t('dashboard.done') }}: {{ stats.tasks_done }}</ChatChip>
                                <ChatChip icon="radio_button_unchecked">{{ t('dashboard.notDone') }}: {{ stats.tasks_not_done }}</ChatChip>
                            </div>
                            <div class="mt-4 flex flex-wrap gap-1.5 border-t border-gray-100 pt-3">
                                <ChatChip icon="check_circle" tone="emerald">{{ t('dashboard.completed') }}: {{ stats.instances_completed }}</ChatChip>
                                <ChatChip icon="pending" tone="amber">{{ t('dashboard.inProgress') }}: {{ stats.instances_assigned }}</ChatChip>
                                <ChatChip icon="hourglass_empty">{{ t('dashboard.pending') }}: {{ stats.instances_pending }}</ChatChip>
                                <span class="text-[11px] text-gray-400">{{ t('dashboard.totalCases', { n: instanceTotal }) }}</span>
                            </div>
                        </div>
                    </section>
                </div>

                <!-- المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة: by permission, within the account's scope -->
                <section v-if="can.tasks_by_department && educationTypes.length">
                    <div class="mb-2 px-1">
                        <h3 class="text-sm font-semibold text-gray-700">{{ t('dashboard.tasksByEduType') }}</h3>
                    </div>
                    <div class="mb-3 flex flex-wrap gap-2">
                        <button
                            v-for="eduType in educationTypes"
                            :key="eduType.id"
                            type="button"
                            class="inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-sm font-medium transition"
                            :class="selectedEduType === eduType.id ? 'bg-indigo-600 text-white shadow' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-gray-50'"
                            @click="loadTasksByDept(eduType.id)"
                        >
                            <Icon name="school" size="text-[16px]" />
                            {{ eduType.name }}
                        </button>
                    </div>

                    <ChatListCard
                        v-if="loadingDepts || departments"
                        :empty="!loadingDepts && departments?.length === 0"
                        :empty-text="t('dashboard.noTasksForEduType')"
                        empty-icon="assignment"
                    >
                        <div v-if="loadingDepts" class="py-8 text-center text-sm text-gray-500">{{ t('common.loading') }}</div>
                        <template v-else>
                            <template v-for="(dept, i) in departments" :key="dept.department + dept.stage">
                                <!-- The whole row toggles its tasks (a row action would fold behind ⋮ on phones). -->
                                <div class="cursor-pointer" @click="openDept = openDept === i ? null : i">
                                    <ChatListRow :title="dept.department" :subtitle="dept.stage ?? '—'" icon="folder" :tone="toneFor(i)">
                                        <template #meta>
                                            <ChatChip icon="flag" tone="indigo">{{ t('dashboard.requiredLabel') }}: {{ dept.required }}</ChatChip>
                                            <ChatChip icon="check_circle" tone="emerald">{{ t('dashboard.completed') }}: {{ dept.completed }}</ChatChip>
                                            <ChatChip :icon="openDept === i ? 'expand_less' : 'expand_more'">{{ dept.tasks.length }}</ChatChip>
                                        </template>
                                    </ChatListRow>
                                </div>
                                <div v-if="openDept === i" class="border-b border-gray-100 bg-gray-50/60 px-4 py-2">
                                    <div v-for="task in dept.tasks" :key="task.id" class="flex flex-wrap items-center justify-between gap-2 py-1.5 text-sm">
                                        <span class="text-gray-800">{{ task.title }}</span>
                                        <span class="flex gap-1">
                                            <ChatChip tone="indigo">{{ task.required }}</ChatChip>
                                            <ChatChip tone="emerald">{{ task.completed }}</ChatChip>
                                            <ChatChip tone="amber">{{ t('dashboard.remainingCol') }}: {{ task.remaining }}</ChatChip>
                                        </span>
                                    </div>
                                </div>
                            </template>
                        </template>
                    </ChatListCard>
                </section>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
