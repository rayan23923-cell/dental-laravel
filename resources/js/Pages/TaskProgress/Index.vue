<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import QrScanner from '@/Components/QrScanner.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import Icon from '@/Components/Icon.vue';

const { t } = useI18n();
const props = defineProps({
    days: Array,
    educationTypes: Array,
    stages: Array,
    groups: Array,
    filters: Object,
    currentSession: Object,
});

const page = usePage();

// --- Filters (day / education type / stage), reloading the page like the
// original's GET-based filter form ---
const day = ref(props.filters.day ?? '');
const educationType = ref(props.filters.education_type ?? '');
const stage = ref(props.filters.stage ?? '');

const applyFilters = () => {
    router.get(
        route('task-progress.index'),
        {
            ...(day.value ? { day: day.value } : {}),
            ...(educationType.value ? { education_type: educationType.value } : {}),
            ...(stage.value ? { stage: stage.value } : {}),
        },
        { preserveState: false }
    );
};

const onEducationTypeChange = () => {
    stage.value = '';
    applyFilters();
};

const clearFilters = () => {
    day.value = '';
    educationType.value = '';
    stage.value = '';
    router.get(route('task-progress.index'));
};

// --- Group detail (department-tabbed doctor matrix), loaded on demand ---
const loading = ref(false);
const detail = ref(null);
const activeDepartmentId = ref(null);
const search = ref('');
const expandedDoctors = ref(new Set());
const statusFilter = ref('all');

const STATUS_FILTERS = computed(() => [
    { key: 'all', label: t('taskProgressAdmin.filterAll') },
    { key: 'not-started', label: t('taskProgressAdmin.filterNotStarted') },
    { key: 'started', label: t('taskProgressAdmin.statusInProgress') },
    { key: 'finished', label: t('taskProgressAdmin.statusCompleted') },
]);

const loadGroup = async (groupId) => {
    loading.value = true;
    detail.value = null;
    try {
        const { data } = await axios.get(route('task-progress.group', groupId));
        detail.value = data;
        activeDepartmentId.value = data.departments[0]?.id ?? null;
        expandedDoctors.value = new Set();
    } finally {
        loading.value = false;
    }
};

const reloadGroup = () => {
    if (detail.value) {
        const expanded = new Set(expandedDoctors.value);
        const active = activeDepartmentId.value;
        loadGroup(detail.value.group.id).then(() => {
            expandedDoctors.value = expanded;
            activeDepartmentId.value = active;
        });
    }
};

const activeDepartment = computed(
    () => detail.value?.departments.find((d) => d.id === activeDepartmentId.value) ?? null
);

const visibleDoctors = computed(() => {
    if (!activeDepartment.value) return [];
    const term = search.value.toLowerCase().trim();
    if (!term) return activeDepartment.value.doctors;
    return activeDepartment.value.doctors.filter(
        (d) => d.name.toLowerCase().includes(term) || (d.username ?? '').toLowerCase().includes(term)
    );
});

// Maps a task card's status to the original's four filter buckets:
// 'unassigned' and 'pending' both count as "not started".
const statusCategory = (status) =>
    ({ completed: 'finished', assigned: 'started', pending: 'not-started', unassigned: 'not-started' }[status] ??
    'not-started');

const filteredTasks = (tasks) =>
    statusFilter.value === 'all' ? tasks : tasks.filter((t) => statusCategory(t.status) === statusFilter.value);

const toggleDoctor = (doctorId) => {
    const next = new Set(expandedDoctors.value);
    next.has(doctorId) ? next.delete(doctorId) : next.add(doctorId);
    expandedDoctors.value = next;
};

const statusLabel = (status) =>
    ({
        completed: t('taskProgressAdmin.statusCompleted'),
        assigned: t('taskProgressAdmin.statusInProgress'),
        pending: t('taskProgressAdmin.statusPending'),
        unassigned: t('taskProgressAdmin.statusNotStarted'),
    }[status] ?? status);

const statusClass = (status) =>
    ({
        completed: 'bg-green-100 text-green-800',
        assigned: 'bg-yellow-100 text-yellow-800',
        pending: 'bg-gray-200 text-gray-700',
        unassigned: 'bg-gray-100 text-gray-500',
    }[status] ?? 'bg-gray-100 text-gray-500');

const borderClass = (status) =>
    ({
        completed: 'border-r-4 border-green-500',
        assigned: 'border-r-4 border-yellow-400',
        pending: 'border-r-4 border-gray-400',
        unassigned: 'border-r-4 border-indigo-500',
    }[status] ?? 'border-r-4 border-indigo-500');

// --- Start task ---
// No patient QR (2026-10-12, by request): a task starts from the case QR or
// by picking the doctor and task here.
const startForm = useForm({ doctor_id: null, task_id: null, notes: '' });
const startTarget = ref(null);
const openStart = (doctor, card) => {
    startTarget.value = { doctor, card };
    startForm.doctor_id = doctor.id;
    startForm.task_id = card.task_id;
    startForm.notes = '';
};
const submitStart = () => {
    startForm.post(route('task-progress.start'), {
        preserveScroll: true,
        onSuccess: () => {
            startTarget.value = null;
            reloadGroup();
        },
    });
};

// --- Complete task ---
const completeForm = useForm({ grade: '', notes: '' });
const completeTarget = ref(null);
const openComplete = (card) => {
    completeTarget.value = card;
    // Matches the original: pre-fill with the instance's own grade if it has
    // one, otherwise suggest the task's grade.
    completeForm.grade = card.grade ?? card.task_grade ?? '';
    completeForm.notes = card.notes ?? '';
};
const submitComplete = () => {
    completeForm.put(route('task-progress.complete', completeTarget.value.instance_id), {
        preserveScroll: true,
        onSuccess: () => {
            completeTarget.value = null;
            reloadGroup();
        },
    });
};

// --- Edit instance (notes + grade) ---
const editForm = useForm({ grade: '', notes: '' });
const editTarget = ref(null);
const openEdit = (card) => {
    editTarget.value = card;
    editForm.grade = card.grade ?? '';
    editForm.notes = card.notes ?? '';
};
const submitEdit = () => {
    editForm.put(route('task-progress.update-instance', editTarget.value.instance_id), {
        preserveScroll: true,
        onSuccess: () => {
            editTarget.value = null;
            reloadGroup();
        },
    });
};

const fmtDate = (value) => (value ? new Date(value).toLocaleDateString() : null);

// --- QR scanner (ported from the original's scanner modal) ---
const scannerOpen = ref(false);
const scannerRef = ref(null);
const scanResult = ref(null);
const scanError = ref('');

const openScanner = async () => {
    scanResult.value = null;
    scanError.value = '';
    scannerOpen.value = true;
    await nextTick();
    scannerRef.value?.start();
};

const closeScanner = () => {
    scannerRef.value?.stop();
    scannerOpen.value = false;
};

const onDecoded = async (text) => {
    scanError.value = '';
    try {
        const { data } = await axios.post(route('task-progress.scan'), { payload: text });
        scanResult.value = data;
    } catch (e) {
        scanError.value = e?.response?.data?.message ?? t('patientReg.qrReadFailed');
    }
};

const rescan = async () => {
    scanResult.value = null;
    scanError.value = '';
    await nextTick();
    scannerRef.value?.start();
};

// A pending_task scan identifies a doctor+task with no instance yet — the
// same "start this task for this doctor" action the cards offer. Routes
// through the same start-task modal (2026-08-26) rather than submitting
// directly, so the patient-screening scan step still applies here too.
const startFromScan = () => {
    closeScanner();
    openStart({ id: scanResult.value.doctor.id, name: scanResult.value.doctor.name }, {
        task_id: scanResult.value.task.id,
        task_title: scanResult.value.task.title,
    });
};
</script>

<template>
    <Head :title="t('taskProgressAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('taskProgressAdmin.heading') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-7xl space-y-4 sm:px-6 lg:px-8">
                <!-- New — this screen previously had no active-year banner
                     at all, unlike Doctors/Groups/Tasks. -->
                <div v-if="currentSession" class="flex items-center gap-2 rounded-lg border border-indigo-200 bg-indigo-50 p-3 text-sm text-indigo-900">
                    <Icon name="calendar_month" class="ml-1" />
                    {{ t('common.academicYearActive') }} <strong>{{ currentSession.name }}</strong>
                </div>

                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-md bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <!-- Filters -->
                <div class="rounded-lg bg-white p-4 shadow-sm">
                    <div class="grid grid-cols-1 gap-4 sm:grid-cols-4">
                        <div>
                            <InputLabel :value="t('taskProgressAdmin.dayLabel')" />
                            <select v-model="day" @change="applyFilters" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">{{ t('taskProgressAdmin.chooseDayOption') }}</option>
                                <option v-for="d in days" :key="d" :value="d">{{ d }}</option>
                            </select>
                        </div>
                        <div>
                            <InputLabel :value="t('taskProgressAdmin.educationTypeLabel')" />
                            <select v-model="educationType" @change="onEducationTypeChange" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">{{ t('taskProgressAdmin.chooseEducationTypeOption') }}</option>
                                <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                            </select>
                        </div>
                        <div>
                            <InputLabel :value="t('doctorsAdmin.stageCol')" />
                            <select v-model="stage" @change="applyFilters" :disabled="stages.length === 0" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">{{ t('tasksAdmin.selectStage') }}</option>
                                <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                        </div>
                        <div class="flex items-end gap-2">
                            <SecondaryButton @click="clearFilters">{{ t('taskProgressAdmin.clearFilters') }}</SecondaryButton>
                            <button type="button" @click="openScanner" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-700">
                                <Icon name="qr_code_2" class="ml-1" />{{ t('taskProgressAdmin.scanQr') }}
                            </button>
                        </div>
                    </div>
                </div>

                <!-- Groups for the selected day -->
                <div v-if="filters.day && groups.length" class="rounded-lg bg-white p-4 shadow-sm">
                    <h3 class="mb-3 text-sm font-semibold text-gray-700">{{ t('taskProgressAdmin.groupsAvailableOnDay', { day: filters.day }) }}</h3>
                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                        <div v-for="g in groups" :key="g.id" class="rounded-lg border border-indigo-200 p-3">
                            <div class="font-medium text-indigo-700">{{ g.name }}</div>
                            <div class="mt-1 text-xs text-gray-500">
                                {{ t('doctorsAdmin.stageCol') }}: {{ g.stage_name ?? '—' }}<br />
                                {{ t('taskProgressAdmin.educationTypeLabel') }}: {{ g.education_type_name ?? '—' }}
                            </div>
                            <PrimaryButton class="mt-3" @click="loadGroup(g.id)">{{ t('taskProgressAdmin.viewDoctors') }}</PrimaryButton>
                        </div>
                    </div>
                </div>
                <div v-else-if="filters.day" class="rounded-md bg-blue-50 p-4 text-sm text-blue-700">
                    {{ t('taskProgressAdmin.noGroupsForDay', { day: filters.day }) }}
                </div>

                <div v-if="loading" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                    {{ t('common.loading') }}
                </div>

                <!-- Group detail -->
                <div v-if="detail" class="space-y-4">
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <h3 class="font-medium text-gray-900">{{ t('taskProgressAdmin.groupDoctorsHeading', { name: detail.group.name }) }}</h3>
                        <p class="mt-1 text-xs text-gray-500">
                            {{ t('doctorsAdmin.stageCol') }}: {{ detail.group.stage_name ?? '—' }} · {{ t('taskProgressAdmin.educationTypeLabel') }}: {{ detail.group.education_type_name ?? '—' }}
                        </p>
                    </div>

                    <div v-if="detail.departments.length === 0" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                        {{ t('taskProgressAdmin.noDepartmentsForStage') }}
                    </div>

                    <template v-else>
                        <!-- Department tabs -->
                        <div class="flex gap-1 overflow-x-auto border-b border-gray-200 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                            <button
                                v-for="dept in detail.departments"
                                :key="dept.id"
                                @click="activeDepartmentId = dept.id"
                                class="shrink-0 whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium"
                                :class="dept.id === activeDepartmentId ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
                            >
                                {{ dept.name }}
                                <span class="ml-1 rounded-full bg-gray-200 px-2 py-0.5 text-xs text-gray-700">{{ dept.task_count }}</span>
                            </button>
                        </div>

                        <template v-if="activeDepartment">
                            <!-- Department summary -->
                            <div class="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-blue-50 p-3 text-sm">
                                <div>
                                    <strong class="text-gray-800">{{ t('doctorsAdmin.departmentLabel') }}: {{ activeDepartment.name }}</strong>
                                    <span class="ml-2 rounded-full bg-gray-200 px-2 py-0.5 text-xs">{{ activeDepartment.task_count }} {{ t('taskProgressAdmin.tasksCountSuffix') }}</span>
                                    <span class="ml-2 rounded-full bg-blue-200 px-2 py-0.5 text-xs">{{ t('doctorsAdmin.requiredLabel') }}: {{ activeDepartment.total_required }}</span>
                                </div>
                                <div class="flex gap-1 text-xs">
                                    <span class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">{{ t('taskProgressAdmin.statusCompleted') }} {{ activeDepartment.totals.completed }}</span>
                                    <span class="rounded-full bg-yellow-100 px-2 py-0.5 text-yellow-800">{{ t('taskProgressAdmin.statusInProgress') }} {{ activeDepartment.totals.assigned }}</span>
                                    <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">{{ t('taskProgressAdmin.availablePrefix') }} {{ activeDepartment.totals.pending }}</span>
                                    <span class="rounded-full bg-gray-800 px-2 py-0.5 text-white">{{ t('taskProgressAdmin.totalPrefix') }} {{ activeDepartment.totals.total_instances }}</span>
                                </div>
                            </div>

                            <!-- Search + status filter -->
                            <div class="flex flex-wrap items-center justify-between gap-3">
                                <TextInput v-model="search" type="text" :placeholder="t('taskProgressAdmin.searchDoctorPlaceholder')" class="w-full max-w-sm" />
                                <div class="flex gap-1">
                                    <button
                                        v-for="f in STATUS_FILTERS"
                                        :key="f.key"
                                        @click="statusFilter = f.key"
                                        class="rounded-md border px-3 py-1 text-xs font-medium"
                                        :class="statusFilter === f.key ? 'border-indigo-500 bg-indigo-500 text-white' : 'border-gray-300 text-gray-600 hover:bg-gray-50'"
                                    >
                                        {{ f.label }}
                                    </button>
                                </div>
                            </div>

                            <!-- Doctor matrix -->
                            <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                                <div class="max-h-[600px] overflow-auto">
                                    <table class="min-w-full divide-y divide-gray-200">
                                        <thead class="sticky top-0 bg-gray-50">
                                            <tr>
                                                <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">{{ t('patients.doctorCol') }}</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('doctorsAdmin.requiredLabel') }}</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('taskProgressAdmin.statusCompleted') }}</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('taskProgressAdmin.statusInProgress') }}</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('taskProgressAdmin.statusPending') }}</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('taskProgressAdmin.unassignedCol') }}</th>
                                            </tr>
                                        </thead>
                                        <tbody class="divide-y divide-gray-200 bg-white">
                                            <template v-for="doctor in visibleDoctors" :key="doctor.id">
                                                <tr
                                                    class="cursor-pointer hover:bg-indigo-50"
                                                    :class="doctor.required > 0 ? 'bg-blue-50/50' : ''"
                                                    @click="toggleDoctor(doctor.id)"
                                                >
                                                    <td class="whitespace-nowrap px-4 py-2 text-sm font-medium text-gray-900">
                                                        <span class="mr-2 inline-block text-gray-400">{{ expandedDoctors.has(doctor.id) ? '▾' : '▸' }}</span>
                                                        {{ doctor.name }}
                                                    </td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-800">{{ doctor.required }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-green-100 px-2 py-0.5 text-xs text-green-800">{{ doctor.completed }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-yellow-100 px-2 py-0.5 text-xs text-yellow-800">{{ doctor.assigned }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-gray-200 px-2 py-0.5 text-xs text-gray-700">{{ doctor.pending }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600">{{ doctor.unassigned }}</span></td>
                                                </tr>
                                                <tr v-if="expandedDoctors.has(doctor.id) && doctor.tasks.length" class="bg-gray-50">
                                                    <td colspan="6" class="p-3">
                                                        <div v-if="filteredTasks(doctor.tasks).length === 0" class="rounded-md bg-yellow-50 p-3 text-center text-sm text-yellow-700">
                                                            {{ t('taskProgressAdmin.noMatchingStatusTasks') }}
                                                        </div>
                                                        <div
                                                            v-for="(card, i) in filteredTasks(doctor.tasks)"
                                                            :key="`${card.task_id}-${card.slot}-${i}`"
                                                            class="mb-2 rounded-lg bg-white p-3 shadow-sm"
                                                            :class="borderClass(card.status)"
                                                        >
                                                            <div class="flex flex-wrap items-start gap-3">
                                                                <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-indigo-600 text-sm font-bold text-white">
                                                                    {{ card.slot }}
                                                                </div>
                                                                <div class="flex-grow">
                                                                    <div class="text-sm font-semibold text-gray-800">
                                                                        {{ card.task_title }}
                                                                        <span v-if="card.case_sheet" class="ml-1 rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ card.case_sheet.name }}</span>
                                                                    </div>
                                                                    <div class="mt-1 flex flex-wrap gap-1 text-xs">
                                                                        <span class="rounded-full px-2 py-0.5" :class="statusClass(card.status)">
                                                                            {{ statusLabel(card.status) }}
                                                                            <template v-if="card.status === 'completed' && card.completion_date"> — {{ fmtDate(card.completion_date) }}</template>
                                                                            <template v-else-if="card.status === 'assigned' && card.assigned_date"> — {{ fmtDate(card.assigned_date) }}</template>
                                                                        </span>
                                                                        <span v-if="card.task_notes" class="rounded-full bg-gray-200 px-2 py-0.5 text-gray-700" :title="card.task_notes">{{ t('taskProgressAdmin.taskNotesTitle') }}</span>
                                                                        <span v-if="card.task_grade" class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">{{ t('tasksAdmin.gradeColShort') }}: {{ card.task_grade }}</span>
                                                                        <span v-if="card.notes" class="rounded-full bg-blue-100 px-2 py-0.5 text-blue-800" :title="card.notes">{{ card.notes.slice(0, 30) }}{{ card.notes.length > 30 ? '…' : '' }}</span>
                                                                        <span v-if="card.grade" class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">{{ t('taskProgressAdmin.instanceGradePrefix') }} {{ card.grade }}</span>
                                                        <!-- "كل التواقيع جاهزة" (2026-08-30) — every
                                                             *_signature field on the linked case
                                                             sheet is filled in; just a hint next
                                                             to the existing complete button below,
                                                             never auto-completes anything. -->
                                                        <span v-if="card.all_signed" class="rounded-full bg-emerald-100 px-2 py-0.5 text-emerald-800">
                                                            <Icon name="verified" class="ml-1" />{{ t('taskProgressAdmin.allSigned') }}
                                                        </span>
                                                                    </div>
                                                                </div>
                                                                <div class="flex shrink-0 flex-col gap-1 text-xs">
                                                                    <!-- فتح النموذج — the original shows this on any
                                                                         instance that exists, gated by the
                                                                         task_progress.open_case_sheet permission. -->
                                                                    <a
                                                                        v-if="card.instance_id"
                                                                        :href="route('case-sheet.open', card.instance_id)"
                                                                        class="rounded bg-slate-700 px-2 py-1 text-center text-white hover:bg-slate-800"
                                                                    >
                                                                        {{ t('taskProgressAdmin.openForm') }}
                                                                    </a>
                                                                    <button v-if="card.status === 'unassigned'" @click.stop="openStart(doctor, card)" class="rounded bg-indigo-600 px-2 py-1 text-white hover:bg-indigo-700">
                                                                        {{ t('taskProgressAdmin.startTask') }}
                                                                    </button>
                                                                    <button
                                                                        v-if="card.status === 'assigned'"
                                                                        @click.stop="openComplete(card)"
                                                                        class="rounded px-2 py-1 text-white"
                                                                        :class="card.all_signed ? 'bg-emerald-600 ring-2 ring-emerald-300 hover:bg-emerald-700' : 'bg-green-600 hover:bg-green-700'"
                                                                    >
                                                                        {{ t('taskProgressAdmin.markComplete') }}
                                                                    </button>
                                                                    <button v-if="card.instance_id && ['assigned', 'completed'].includes(card.status)" @click.stop="openEdit(card)" class="rounded bg-blue-500 px-2 py-1 text-white hover:bg-blue-600">
                                                                        {{ t('common.edit') }}
                                                                    </button>
                                                                </div>
                                                            </div>
                                                        </div>
                                                    </td>
                                                </tr>
                                            </template>
                                            <tr v-if="visibleDoctors.length === 0">
                                                <td colspan="6" class="px-4 py-8 text-center text-sm text-gray-500">{{ t('taskProgressAdmin.noSearchResults') }}</td>
                                            </tr>
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        </template>
                    </template>
                </div>
            </div>
        </div>

        <!-- QR scanner modal -->
        <Modal :show="scannerOpen" @close="closeScanner" max-width="2xl">
            <div class="p-6">
                <h2 class="text-lg font-medium text-gray-900"><Icon name="qr_code_2" class="ml-1" />{{ t('taskProgressAdmin.scanQr') }}</h2>

                <div v-if="!scanResult" class="mt-4">
                    <QrScanner ref="scannerRef" @decoded="onDecoded" />
                    <div v-if="scanError" class="mt-3 rounded-md bg-red-50 p-3 text-sm text-red-700">{{ scanError }}</div>
                </div>

                <!-- Result: an existing assigned case -->
                <div v-else-if="scanResult.kind === 'task_instance'" class="mt-4 space-y-3">
                    <div class="rounded-lg border border-green-200 bg-green-50 p-4">
                        <p class="text-sm text-green-800"><Icon name="check_circle" class="ml-1" />{{ t('taskProgressAdmin.recognizedInstance', { id: scanResult.instance_id }) }}</p>
                        <dl class="mt-2 space-y-1 text-sm text-gray-700">
                            <div><span class="text-gray-500">{{ t('patients.doctorCol') }}:</span> {{ scanResult.doctor.name ?? '—' }}</div>
                            <div><span class="text-gray-500">{{ t('taskProgressAdmin.taskColonLabel') }}</span> {{ scanResult.task.title }}</div>
                            <div><span class="text-gray-500">{{ t('doctorsAdmin.departmentLabel') }}:</span> {{ scanResult.task.department ?? '—' }}</div>
                            <div><span class="text-gray-500">{{ t('taskProgressAdmin.formColonLabel') }}</span> {{ scanResult.task.case_sheet ?? '—' }}</div>
                            <div><span class="text-gray-500">{{ t('doctorsAdmin.statusCol') }}:</span> {{ statusLabel(scanResult.status) }}</div>
                        </dl>
                    </div>
                    <div class="flex flex-wrap justify-end gap-2">
                        <SecondaryButton @click="rescan">{{ t('taskProgressAdmin.scanAnother') }}</SecondaryButton>
                        <a :href="scanResult.case_sheet_url" class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                            <Icon name="description" class="ml-1" />{{ t('taskProgressAdmin.openForm') }}
                        </a>
                    </div>
                </div>

                <!-- Result: a task the doctor hasn't started yet -->
                <div v-else-if="scanResult.kind === 'pending_task'" class="mt-4 space-y-3">
                    <div class="rounded-lg border border-amber-200 bg-amber-50 p-4">
                        <p class="text-sm text-amber-800">{{ t('taskProgressAdmin.pendingTaskMsg') }}</p>
                        <dl class="mt-2 space-y-1 text-sm text-gray-700">
                            <div><span class="text-gray-500">{{ t('patients.doctorCol') }}:</span> {{ scanResult.doctor.name }}</div>
                            <div><span class="text-gray-500">{{ t('taskProgressAdmin.taskColonLabel') }}</span> {{ scanResult.task.title }}</div>
                            <div><span class="text-gray-500">{{ t('doctorsAdmin.departmentLabel') }}:</span> {{ scanResult.task.department ?? '—' }}</div>
                            <div><span class="text-gray-500">{{ t('doctorsAdmin.requiredLabel') }}:</span> {{ scanResult.task.required_count }}</div>
                        </dl>
                    </div>
                    <div class="flex flex-wrap justify-end gap-2">
                        <SecondaryButton @click="rescan">{{ t('taskProgressAdmin.scanAnother') }}</SecondaryButton>
                        <PrimaryButton :disabled="startForm.processing" @click="startFromScan"><Icon name="play_arrow" class="ml-1" />{{ t('taskProgressAdmin.startTaskForDoctor') }}</PrimaryButton>
                    </div>
                </div>

                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="closeScanner">{{ t('common.close') }}</SecondaryButton>
                </div>
            </div>
        </Modal>

        <!-- Start task modal -->
        <Modal :show="startTarget !== null" @close="startTarget = null">
            <form @submit.prevent="submitStart" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('taskProgressAdmin.startTaskModalTitle') }}</h2>
                <p class="mt-1 text-sm text-gray-500">{{ startTarget?.doctor.name }} — {{ startTarget?.card.task_title }}</p>

                <div class="mt-4">
                    <InputLabel for="start-notes" :value="t('tasksAdmin.notesLabel')" />
                    <textarea id="start-notes" v-model="startForm.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="startTarget = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="startForm.processing">{{ t('taskProgressAdmin.startButton') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

        <!-- Complete task modal -->
        <Modal :show="completeTarget !== null" @close="completeTarget = null">
            <form @submit.prevent="submitComplete" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('taskProgressAdmin.completeModalTitle') }}</h2>
                <p class="mt-1 text-sm text-gray-500">{{ completeTarget?.task_title }}</p>
                <div v-if="completeTarget?.task_notes" class="mt-3 rounded-md bg-blue-50 p-3 text-sm text-blue-800">
                    {{ completeTarget.task_notes }}
                </div>
                <div class="mt-4">
                    <InputLabel for="complete-grade" :value="completeTarget?.task_grade ? t('taskProgressAdmin.gradeWithMax', { max: completeTarget.task_grade }) : t('tasksAdmin.gradeColShort')" />
                    <TextInput
                        id="complete-grade"
                        v-model="completeForm.grade"
                        type="number"
                        step="0.01"
                        min="0"
                        :max="completeTarget?.task_grade ?? undefined"
                        :disabled="!completeTarget?.task_grade"
                        class="mt-1 block w-full"
                    />
                    <p v-if="!completeTarget?.task_grade" class="mt-1 text-xs text-gray-500">
                        {{ t('taskProgressAdmin.noGradeHintComplete') }}
                    </p>
                </div>
                <div class="mt-4">
                    <InputLabel for="complete-notes" :value="t('taskProgressAdmin.instanceNotesLabel')" />
                    <textarea id="complete-notes" v-model="completeForm.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="completeTarget = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="completeForm.processing">{{ t('taskProgressAdmin.confirmComplete') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

        <!-- Edit instance modal -->
        <Modal :show="editTarget !== null" @close="editTarget = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('taskProgressAdmin.editModalTitle') }}</h2>
                <p class="mt-1 text-sm text-gray-500">{{ editTarget?.task_title }}</p>
                <div class="mt-4">
                    <InputLabel for="edit-grade" :value="editTarget?.task_grade ? t('taskProgressAdmin.gradeWithMax', { max: editTarget.task_grade }) : t('tasksAdmin.gradeColShort')" />
                    <TextInput
                        id="edit-grade"
                        v-model="editForm.grade"
                        type="number"
                        step="0.01"
                        min="0"
                        :max="editTarget?.task_grade ?? undefined"
                        :disabled="!editTarget?.task_grade"
                        class="mt-1 block w-full"
                    />
                    <p v-if="!editTarget?.task_grade" class="mt-1 text-xs text-gray-500">
                        {{ t('taskProgressAdmin.noGradeHintEdit') }}
                    </p>
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-notes" :value="t('tasksAdmin.notesLabel')" />
                    <textarea id="edit-notes" v-model="editForm.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editTarget = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
