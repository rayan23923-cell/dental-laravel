<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import GradeInput from '@/Components/GradeInput.vue';
import QrScanner from '@/Components/QrScanner.vue';
import PhoneScannerLink from '@/Components/PhoneScannerLink.vue';
import PaperPhotos from '@/Components/PaperPhotos.vue';
import { onRemoteScan } from '@/remoteScanner';
import { Head, Link, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import Icon from '@/Components/Icon.vue';
import ScoreSummary from '@/Components/Tasks/ScoreSummary.vue';
import WorkItemsInput from '@/Components/Tasks/WorkItemsInput.vue';
import TaskStepsList from '@/Components/Tasks/TaskStepsList.vue';
import { stepsFromScoring, workItemsToForm } from '@/Components/Tasks/workItems.js';
import StructureTabs from '@/Components/StructureTabs.vue';
import TaskStartRequestsPanel from '@/Components/TaskStartRequestsPanel.vue';

const { t } = useI18n();
const props = defineProps({
    days: Array,
    educationTypes: Array,
    stages: Array,
    groups: Array,
    filters: Object,
    currentSession: Object,
    // Doctors' requests waiting for a start (2026-10-14) — the tab's badge.
    pendingRequests: { type: Number, default: 0 },
    // "إلغاء بدء المهمة" (2026-10-23): the user's own permission.
    canCancel: { type: Boolean, default: false },
});

// "تقدم المهام" | "الطلبات" (2026-10-14, by request); kept in the URL so a
// reload stays on the same tab.
const mainTab = ref(new URLSearchParams(window.location.search).get('tab') === 'requests' ? 'requests' : 'progress');
const requestCount = ref(props.pendingRequests);

// Keep the requests badge current while on the progress tab (the
// requests panel refreshes itself, and the count with it).
const refreshRequestCount = async () => {
    if (mainTab.value === 'requests' || document.visibilityState !== 'visible') return;
    try {
        requestCount.value = (await axios.get(route('task-progress.requests.index'))).data.pending_count;
    } catch {
        // Keep the last count.
    }
};
let requestCountTimer = null;
onMounted(() => {
    requestCountTimer = setInterval(refreshRequestCount, 30000);
    document.addEventListener('visibilitychange', refreshRequestCount);
});
onBeforeUnmount(() => {
    clearInterval(requestCountTimer);
    document.removeEventListener('visibilitychange', refreshRequestCount);
});
const switchTab = (key) => {
    mainTab.value = key;
    const url = new URL(window.location.href);
    if (key === 'requests') url.searchParams.set('tab', 'requests');
    else url.searchParams.delete('tab');
    window.history.replaceState(window.history.state, '', url);
};

const page = usePage();
// Start, complete and grades switched off for the whole system (2026-10-22).
const switches = computed(() => page.props.taskSwitches ?? {});
const isOn = (key) => switches.value[key] !== false;
// Groups turned off in clinic settings: no day/group step, the chosen
// stage's doctors are shown directly (task-progress.stage).
const groupsEnabled = computed(() => page.props.groupsEnabled !== false);

// --- Filters (education type / stage; the day filter was removed
// 2026-10-13, by request), reloading the page like the
// original's GET-based filter form ---
const educationType = ref(props.filters.education_type ?? '');
const stage = ref(props.filters.stage ?? '');

const applyFilters = () => {
    router.get(
        route('task-progress.index'),
        {
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
        const { data } = await axios.get(groupId ? route('task-progress.group', groupId) : route('task-progress.stage', props.filters.stage));
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
        loadGroup(detail.value.group.id ?? null).then(() => {
            expandedDoctors.value = expanded;
            activeDepartmentId.value = active;
        });
    }
};

if (!groupsEnabled.value && props.filters.stage) loadGroup(null);

// Printable report (2026-10-13, by request) — the whole group/stage, one
// department or one doctor, same three scopes as the app's PDF.
const printUrl = (extra = {}) => route('task-progress.print', {
    ...(detail.value?.group.id ? { group: detail.value.group.id } : { stage: detail.value?.group.stage_id }),
    ...extra,
    autoprint: 1,
});

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
// The steps done at this first session are signed in the same dialog (2026-10-18).
const startForm = useForm({ doctor_id: null, task_id: null, notes: '', steps: [] });
const startTarget = ref(null);
const openStart = (doctor, card) => {
    startTarget.value = { doctor, card };
    startForm.doctor_id = doctor.id;
    startForm.task_id = card.task_id;
    startForm.notes = '';
    startForm.steps = [];
};
const startSteps = computed(() => stepsFromScoring(startTarget.value?.card?.task_scoring));

// --- A started case's steps, signed one after another (2026-10-18) ---
const stepsTarget = ref(null);
const stepsData = ref(null);
const openSteps = async (doctor, card) => {
    stepsTarget.value = { doctor, card };
    stepsData.value = null;
    const { data } = await axios.get(route('case-sheets.instance-work', card.instance_id));
    stepsData.value = data;
};
const closeSteps = () => {
    stepsTarget.value = null;
    reloadGroup();
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
const completeForm = useForm({ grade: '', notes: '', work_items: [] });
const completeTarget = ref(null);
// Kinds of work with points, graded items and checklists (2026-10-14); see App\Support\TaskScoring.
const hasOptions = (card) => !!card?.task_scoring?.options?.length || !!card?.task_scoring?.checklist?.length;
// Stored items keep labels; map them back to the task's indexes (shared with the case sheets).
const itemsFor = (card) => workItemsToForm(card.task_scoring, card.work_items);
const openComplete = (card) => {
    completeTarget.value = card;
    completeForm.work_items = hasOptions(card) ? itemsFor(card) : [];
    // Matches the original: pre-fill with the instance's own grade if it has
    // one, otherwise suggest the task's grade.
    completeForm.grade = card.grade ?? card.task_grade ?? '';
    completeForm.notes = card.notes ?? '';
};
const submitComplete = () => {
    completeForm.transform((data) => (hasOptions(completeTarget.value) ? data : { grade: data.grade, notes: data.notes })).put(route('task-progress.complete', completeTarget.value.instance_id), {
        preserveScroll: true,
        onSuccess: () => {
            completeTarget.value = null;
            reloadGroup();
        },
    });
};

// --- Cancel a start (2026-10-23, by request); see App\Services\TaskCanceller ---
const cancelStart = (card) => {
    if (!window.confirm(t('taskProgressAdmin.cancelStartConfirm', { task: card.task_title }))) return;
    router.delete(route('task-progress.cancel', card.instance_id), {
        preserveScroll: true,
        onSuccess: () => reloadGroup(),
    });
};

// --- Edit instance (notes + grade) ---
const editForm = useForm({ grade: '', notes: '', work_items: [] });
const editTarget = ref(null);
const openEdit = (card) => {
    editTarget.value = card;
    editForm.work_items = hasOptions(card) ? itemsFor(card) : [];
    editForm.grade = card.grade ?? '';
    editForm.notes = card.notes ?? '';
};
const submitEdit = () => {
    editForm.transform((data) => (hasOptions(editTarget.value) ? data : { grade: data.grade, notes: data.notes })).put(route('task-progress.update-instance', editTarget.value.instance_id), {
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

// `typing`: opened from "إدخال الرمز" — the code field, without the camera.
const openScanner = async (typing = false) => {
    scanResult.value = null;
    scanError.value = '';
    typedCode.value = '';
    scannerOpen.value = true;
    await nextTick();
    if (typing === true) document.getElementById('case-code')?.focus();
    else scannerRef.value?.start();
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

// A phone paired as a scanner (2026-10-12): its code opens the scan
// result here even when this computer's camera is not running.
onRemoteScan(
    (text) => {
        scanResult.value = null;
        scannerOpen.value = true;
        onDecoded(text);
    },
    () => !scannerRef.value?.scanning,
);

// Photos of the paper case sheet (2026-10-13): from a card, or straight
// after scanning a case's QR. `card` (when opened from one) gets the new count.
const photosTarget = ref(null);
const openPhotos = (instanceId, title, doctorName, card = null) => {
    photosTarget.value = { instanceId, label: [title, doctorName].filter(Boolean).join(' - '), title, doctorName, card };
};
const photosFromScan = () => {
    const r = scanResult.value;
    closeScanner();
    openPhotos(r.instance_id, r.task.title, r.doctor.name);
};

// Typing the case code instead of scanning (2026-10-30, by request): the
// digits under the case's QR on the student's account; same lookup.
const typedCode = ref('');
const submitTypedCode = () => {
    const code = typedCode.value.trim();
    if (!code) {
        scanError.value = t('caseCode.invalid');
        return;
    }
    onDecoded(code);
};

// A case found by its QR or code gets the matrix card's own actions.
const fromScan = (action) => {
    const r = scanResult.value;
    closeScanner();
    action(r.doctor, r.card);
};

const rescan = async () => {
    scanResult.value = null;
    scanError.value = '';
    typedCode.value = '';
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
        task_scoring: scanResult.value.task.scoring,
    });
};
</script>

<template>
    <Head :title="t('taskProgressAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex flex-wrap items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('taskProgressAdmin.heading') }}</h2>
                <div class="flex items-center gap-2">
                    <!-- "إعدادات النماذج" and the supervisor code (2026-10-22, by request). -->
                    <Link
                        :href="route('form-settings.index')"
                        class="inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-1.5 text-sm font-medium text-indigo-700 shadow-sm ring-1 ring-indigo-200 hover:bg-indigo-50"
                        :title="t('formSettings.open')"
                    >
                        <Icon name="tune" size="text-[18px]" />{{ t('formSettings.open') }}
                    </Link>
                    <PhoneScannerLink variant="page" />
                </div>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-7xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs />

                <!-- Progress | doctors' start requests (2026-10-14) -->
                <div class="flex gap-1 rounded-full bg-white p-1 shadow-sm ring-1 ring-gray-100">
                    <button
                        v-for="item in [{ key: 'progress', icon: 'monitoring', label: t('taskRequests.progressTab') }, { key: 'requests', icon: 'inbox', label: t('taskRequests.requestsTab') }]"
                        :key="item.key"
                        type="button"
                        class="relative flex flex-1 items-center justify-center gap-1.5 rounded-full px-4 py-2 text-sm font-medium transition"
                        :class="mainTab === item.key ? 'bg-indigo-600 text-white shadow' : 'text-gray-600 hover:bg-gray-50'"
                        @click="switchTab(item.key)"
                    >
                        <Icon :name="item.icon" size="text-[18px]" />{{ item.label }}
                        <span
                            v-if="item.key === 'requests' && requestCount > 0"
                            class="min-w-[1.25rem] rounded-full bg-red-500 px-1.5 text-center text-xs font-semibold leading-5 text-white"
                        >{{ requestCount > 99 ? '99+' : requestCount }}</span>
                    </button>
                </div>

                <TaskStartRequestsPanel v-if="mainTab === 'requests'" @count="requestCount = $event" />

                <template v-else>

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
                    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
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
                            <button type="button" @click="openScanner()" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-700">
                                <Icon name="qr_code_2" class="ml-1" />{{ t('taskProgressAdmin.scanQr') }}
                            </button>
                            <button type="button" @click="openScanner(true)" class="rounded-md border border-sky-600 px-4 py-2 text-sm font-medium text-sky-700 hover:bg-sky-50">
                                <Icon name="keyboard" class="ml-1" />{{ t('caseCode.enterButton') }}
                            </button>
                        </div>
                    </div>
                </div>

                <!-- Groups of the selected stage -->
                <div v-if="!filters.stage" class="rounded-md bg-blue-50 p-4 text-sm text-blue-700">
                    {{ t('taskProgressAdmin.chooseStageHint') }}
                </div>
                <template v-else-if="!groupsEnabled"></template>
                <div v-else-if="groups.length" class="rounded-lg bg-white p-4 shadow-sm">
                    <h3 class="mb-3 text-sm font-semibold text-gray-700">{{ t('taskProgressAdmin.groupsHeading') }}</h3>
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
                <div v-else class="rounded-md bg-blue-50 p-4 text-sm text-blue-700">
                    {{ t('taskProgressAdmin.noGroupsForStage') }}
                </div>

                <div v-if="loading" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                    {{ t('common.loading') }}
                </div>

                <!-- Group detail -->
                <div v-if="detail" class="space-y-4">
                    <div class="flex items-start justify-between gap-2 rounded-lg bg-white p-4 shadow-sm">
                        <div>
                        <h3 class="font-medium text-gray-900">{{ detail.group.id ? t('taskProgressAdmin.groupDoctorsHeading', { name: detail.group.name }) : t('taskProgressAdmin.stageDoctorsHeading', { name: detail.group.name }) }}</h3>
                        <p class="mt-1 text-xs text-gray-500">
                            {{ t('doctorsAdmin.stageCol') }}: {{ detail.group.stage_name ?? '—' }} · {{ t('taskProgressAdmin.educationTypeLabel') }}: {{ detail.group.education_type_name ?? '—' }}
                        </p>
                        </div>
                        <a
                            v-if="detail.departments.length"
                            :href="printUrl()"
                            target="_blank"
                            class="inline-flex shrink-0 items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50"
                            :title="t('taskProgressAdmin.printWholeGroupTooltip')"
                        >
                            <Icon name="print" size="text-[18px]" />{{ t('taskProgressAdmin.printButton') }}
                        </a>
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
                                <div class="flex flex-wrap items-center gap-1 text-xs">
                                    <a
                                        :href="printUrl({ department: activeDepartment.id })"
                                        target="_blank"
                                        class="inline-flex items-center rounded-full bg-white p-1 text-gray-600 hover:text-indigo-600"
                                        :title="t('taskProgressAdmin.printDepartmentOnlyTooltip')"
                                    >
                                        <Icon name="print" size="text-[16px]" :label="t('taskProgressAdmin.printDepartmentOnlyTooltip')" />
                                    </a>
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
                                                        <span
                                                            v-if="doctor.score"
                                                            class="mr-1 rounded-full px-2 py-0.5 text-xs"
                                                            :class="doctor.score.passed ? 'bg-green-100 text-green-800' : 'bg-amber-100 text-amber-800'"
                                                        ><span dir="ltr">{{ doctor.score.percent }}%</span></span>
                                                        <a
                                                            :href="printUrl({ department: activeDepartment.id, doctor: doctor.id })"
                                                            target="_blank"
                                                            class="mr-2 inline-flex align-middle text-gray-400 hover:text-indigo-600"
                                                            :title="t('taskProgressAdmin.printDoctorTasksTooltip')"
                                                            @click.stop
                                                        >
                                                            <Icon name="print" size="text-[16px]" :label="t('taskProgressAdmin.printDoctorTasksTooltip')" />
                                                        </a>
                                                    </td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-800">{{ doctor.required }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-green-100 px-2 py-0.5 text-xs text-green-800">{{ doctor.completed }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-yellow-100 px-2 py-0.5 text-xs text-yellow-800">{{ doctor.assigned }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-gray-200 px-2 py-0.5 text-xs text-gray-700">{{ doctor.pending }}</span></td>
                                                    <td class="px-4 py-2 text-center text-sm"><span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600">{{ doctor.unassigned }}</span></td>
                                                </tr>
                                                <tr v-if="expandedDoctors.has(doctor.id) && doctor.tasks.length" class="bg-gray-50">
                                                    <td colspan="6" class="p-3">
                                                        <ScoreSummary v-if="doctor.score" :score="doctor.score" />
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
                                                                        <span v-if="card.points !== null && card.points !== undefined" class="rounded-full bg-indigo-600 px-2 py-0.5 text-white" :title="(card.work_items ?? []).map((w) => `${w.option} ×${w.qty}`).join('، ')">{{ t('taskScoring.pointsValue', { n: card.points }) }}</span>
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
                                                                    <button
                                                                        v-if="card.instance_id && card.steps_count && ['assigned', 'completed'].includes(card.status)"
                                                                        @click.stop="openSteps(doctor, card)"
                                                                        class="rounded px-2 py-1 text-white"
                                                                        :class="card.steps_signed >= card.steps_count ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-amber-500 hover:bg-amber-600'"
                                                                    >
                                                                        <Icon name="checklist" class="ml-1" />{{ t('taskSteps.button', { done: Math.min(card.steps_signed, card.steps_count), total: card.steps_count }) }}
                                                                    </button>
                                                                    <button v-if="card.status === 'unassigned' && isOn('task_start_enabled')" @click.stop="openStart(doctor, card)" class="rounded bg-indigo-600 px-2 py-1 text-white hover:bg-indigo-700">
                                                                        {{ t('taskProgressAdmin.startTask') }}
                                                                    </button>
                                                                    <button
                                                                        v-if="card.status === 'assigned' && isOn('task_finish_enabled')"
                                                                        @click.stop="openComplete(card)"
                                                                        class="rounded px-2 py-1 text-white"
                                                                        :class="card.all_signed ? 'bg-emerald-600 ring-2 ring-emerald-300 hover:bg-emerald-700' : 'bg-green-600 hover:bg-green-700'"
                                                                    >
                                                                        {{ t('taskProgressAdmin.markComplete') }}
                                                                    </button>
                                                                    <button
                                                                        v-if="card.status === 'assigned' && card.instance_id && canCancel && isOn('task_cancel_enabled')"
                                                                        @click.stop="cancelStart(card)"
                                                                        class="rounded bg-red-600 px-2 py-1 text-white hover:bg-red-700"
                                                                    >
                                                                        {{ t('taskProgressAdmin.cancelStart') }}
                                                                    </button>
                                                                    <button v-if="card.instance_id && ['assigned', 'completed'].includes(card.status)" @click.stop="openEdit(card)" class="rounded bg-blue-500 px-2 py-1 text-white hover:bg-blue-600">
                                                                        {{ t('common.edit') }}
                                                                    </button>
                                                                    <button
                                                                        v-if="card.instance_id"
                                                                        @click.stop="openPhotos(card.instance_id, card.task_title, doctor.name, card)"
                                                                        class="rounded px-2 py-1"
                                                                        :class="card.attachments_count ? 'bg-emerald-600 text-white hover:bg-emerald-700' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'"
                                                                    >
                                                                        <Icon name="photo_library" class="ml-1" />{{ t('paperPhotos.button', { count: card.attachments_count ?? 0 }) }}
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
                </template>
            </div>
        </div>

        <!-- QR scanner modal -->
        <Modal :show="scannerOpen" @close="closeScanner" max-width="2xl">
            <div class="p-6">
                <h2 class="text-lg font-medium text-gray-900"><Icon name="qr_code_2" class="ml-1" />{{ t('taskProgressAdmin.scanQr') }}</h2>

                <div v-if="!scanResult" class="mt-4">
                    <QrScanner ref="scannerRef" @decoded="onDecoded" />
                    <form class="mt-4 rounded-lg border border-gray-200 bg-gray-50 p-3" @submit.prevent="submitTypedCode">
                        <InputLabel for="case-code" :value="t('caseCode.orType')" />
                        <div class="mt-1 flex gap-2">
                            <TextInput
                                id="case-code"
                                v-model="typedCode"
                                dir="ltr"
                                inputmode="numeric"
                                autocomplete="off"
                                class="block w-full text-center font-mono text-lg tracking-widest"
                                placeholder="000 000"
                            />
                            <PrimaryButton type="submit"><Icon name="keyboard" class="ml-1" />{{ t('caseCode.open') }}</PrimaryButton>
                        </div>
                        <p class="mt-1 text-xs text-gray-500">{{ t('caseCode.inputHint') }}</p>
                    </form>
                    <div v-if="scanError" class="mt-3 rounded-md bg-red-50 p-3 text-sm text-red-700">{{ scanError }}</div>
                </div>

                <!-- Result: an existing assigned case -->
                <div v-else-if="scanResult.kind === 'task_instance'" class="mt-4 space-y-3">
                    <div class="rounded-lg border border-green-200 bg-green-50 p-4">
                        <p class="text-sm text-green-800"><Icon name="check_circle" class="ml-1" />{{ t('taskProgressAdmin.recognizedInstance', { id: scanResult.instance_id }) }}</p>
                        <dl class="mt-2 space-y-1 text-sm text-slate-700">
                            <div><span class="text-slate-500">{{ t('patients.doctorCol') }}:</span> {{ scanResult.doctor.name ?? '—' }}</div>
                            <div><span class="text-slate-500">{{ t('taskProgressAdmin.taskColonLabel') }}</span> {{ scanResult.task.title }}</div>
                            <div><span class="text-slate-500">{{ t('doctorsAdmin.departmentLabel') }}:</span> {{ scanResult.task.department ?? '—' }}</div>
                            <div><span class="text-slate-500">{{ t('taskProgressAdmin.formColonLabel') }}</span> {{ scanResult.task.case_sheet ?? '—' }}</div>
                            <div><span class="text-slate-500">{{ t('doctorsAdmin.statusCol') }}:</span> {{ statusLabel(scanResult.status) }}</div>
                        </dl>
                    </div>
                    <div v-if="scanResult.card" class="flex flex-wrap justify-end gap-2">
                        <button
                            v-if="scanResult.card.steps_count && ['assigned', 'completed'].includes(scanResult.card.status)"
                            type="button"
                            class="rounded-md px-4 py-2 text-sm font-medium text-white"
                            :class="scanResult.card.steps_signed >= scanResult.card.steps_count ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-amber-500 hover:bg-amber-600'"
                            @click="fromScan(openSteps)"
                        >
                            <Icon name="checklist" class="ml-1" />{{ t('taskSteps.button', { done: Math.min(scanResult.card.steps_signed, scanResult.card.steps_count), total: scanResult.card.steps_count }) }}
                        </button>
                        <button
                            v-if="scanResult.card.status === 'assigned' && isOn('task_finish_enabled')"
                            type="button"
                            class="rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700"
                            @click="fromScan((d, card) => openComplete(card))"
                        >
                            <Icon name="task_alt" class="ml-1" />{{ t('taskProgressAdmin.markComplete') }}
                        </button>
                        <button
                            v-if="['assigned', 'completed'].includes(scanResult.card.status)"
                            type="button"
                            class="rounded-md bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
                            @click="fromScan((d, card) => openEdit(card))"
                        >
                            <Icon name="edit" class="ml-1" />{{ t('common.edit') }}
                        </button>
                        <button
                            v-if="scanResult.card.status === 'assigned' && canCancel && isOn('task_cancel_enabled')"
                            type="button"
                            class="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700"
                            @click="fromScan((d, card) => cancelStart(card))"
                        >
                            <Icon name="undo" class="ml-1" />{{ t('taskProgressAdmin.cancelStart') }}
                        </button>
                    </div>
                    <div class="flex flex-wrap justify-end gap-2">
                        <SecondaryButton @click="rescan">{{ t('taskProgressAdmin.scanAnother') }}</SecondaryButton>
                        <button type="button" class="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700" @click="photosFromScan">
                            <Icon name="add_a_photo" class="ml-1" />{{ t('paperPhotos.attachFromScan') }}
                        </button>
                        <a :href="scanResult.case_sheet_url" class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                            <Icon name="description" class="ml-1" />{{ t('taskProgressAdmin.openForm') }}
                        </a>
                    </div>
                </div>

                <!-- Result: a task the doctor hasn't started yet -->
                <div v-else-if="scanResult.kind === 'pending_task'" class="mt-4 space-y-3">
                    <div class="rounded-lg border border-amber-200 bg-amber-50 p-4">
                        <p class="text-sm text-amber-800">{{ scanResult.card ? t('taskProgressAdmin.pendingTaskMsg') : t('caseCode.noSlotLeft') }}</p>
                        <dl class="mt-2 space-y-1 text-sm text-slate-700">
                            <div><span class="text-slate-500">{{ t('patients.doctorCol') }}:</span> {{ scanResult.doctor.name }}</div>
                            <div><span class="text-slate-500">{{ t('taskProgressAdmin.taskColonLabel') }}</span> {{ scanResult.task.title }}</div>
                            <div><span class="text-slate-500">{{ t('doctorsAdmin.departmentLabel') }}:</span> {{ scanResult.task.department ?? '—' }}</div>
                            <div><span class="text-slate-500">{{ t('doctorsAdmin.requiredLabel') }}:</span> {{ scanResult.task.required_count }}</div>
                        </dl>
                    </div>
                    <div class="flex flex-wrap justify-end gap-2">
                        <SecondaryButton @click="rescan">{{ t('taskProgressAdmin.scanAnother') }}</SecondaryButton>
                        <PrimaryButton v-if="scanResult.card && isOn('task_start_enabled')" :disabled="startForm.processing" @click="startFromScan"><Icon name="play_arrow" class="ml-1" />{{ t('taskProgressAdmin.startTaskForDoctor') }}</PrimaryButton>
                    </div>
                </div>

                <!-- Result: a doctor's ID card (2026-10-14) -->
                <div v-else-if="scanResult.kind === 'doctor'" class="mt-4 space-y-3">
                    <div class="rounded-lg border border-indigo-200 bg-indigo-50 p-4">
                        <dl class="space-y-1 text-sm text-slate-700">
                            <div><span class="text-slate-500">{{ t('patients.doctorCol') }}:</span> {{ scanResult.doctor.name }}</div>
                            <div v-if="scanResult.doctor.stage"><span class="text-slate-500">{{ t('taskProgressAdmin.stageLabel') }}:</span> {{ scanResult.doctor.stage }}</div>
                        </dl>
                    </div>
                    <div class="flex flex-wrap justify-end gap-2">
                        <SecondaryButton @click="rescan">{{ t('taskProgressAdmin.scanAnother') }}</SecondaryButton>
                        <a :href="scanResult.progress_url" class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                            <Icon name="monitoring" class="ml-1" />{{ t('taskProgressAdmin.openDoctorProgress') }}
                        </a>
                    </div>
                </div>

                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="closeScanner">{{ t('common.close') }}</SecondaryButton>
                </div>
            </div>
        </Modal>

        <!-- Paper case sheet photos (2026-10-13) -->
        <Modal :show="photosTarget !== null" @close="photosTarget = null">
            <div v-if="photosTarget" class="p-6">
                <h2 class="text-lg font-medium text-gray-900"><Icon name="photo_library" class="ml-1" />{{ t('paperPhotos.title') }}</h2>
                <p class="mt-1 text-sm text-gray-500">{{ photosTarget.label }}</p>
                <PaperPhotos
                    class="mt-4"
                    mode="staff"
                    :instance-id="photosTarget.instanceId"
                    :label="photosTarget.label"
                    @changed="(n) => photosTarget.card && (photosTarget.card.attachments_count = n)"
                />
                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="photosTarget = null">{{ t('common.close') }}</SecondaryButton>
                </div>
            </div>
        </Modal>

        <!-- Start task modal -->
        <Modal :show="startTarget !== null" @close="startTarget = null">
            <form @submit.prevent="submitStart" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('taskProgressAdmin.startTaskModalTitle') }}</h2>
                <p class="mt-1 text-sm text-gray-500">{{ startTarget?.doctor.name }} — {{ startTarget?.card.task_title }}</p>

                <div v-if="startSteps.length && isOn('steps_enabled')" class="mt-4">
                    <p class="mb-2 text-xs text-gray-500">{{ t('taskSteps.startHint') }}</p>
                    <TaskStepsList v-model="startForm.steps" :scoring="startTarget?.card?.task_scoring" />
                    <InputError class="mt-2" :message="startForm.errors.step ?? startForm.errors.grade" />
                </div>
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

        <!-- A started case's steps -->
        <Modal :show="stepsTarget !== null" @close="closeSteps">
            <div class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('taskSteps.modalTitle') }}</h2>
                <p class="mt-1 text-sm text-gray-500">{{ stepsTarget?.doctor.name }} — {{ stepsTarget?.card.task_title }}</p>
                <div v-if="!stepsData" class="mt-4 text-sm text-gray-500">…</div>
                <div v-else class="mt-4">
                    <TaskStepsList :steps="stepsData.steps" :instance-id="stepsTarget.card.instance_id" :can-sign="stepsData.can_sign" :can-add-step="stepsData.can_add_step ?? stepsData.can_sign" @updated="stepsData = $event" />
                    <p v-if="stepsData.points !== null && stepsData.points !== undefined" class="mt-3 text-sm font-semibold text-indigo-800">
                        {{ t('taskScoring.pointsValue', { n: stepsData.points }) }}
                    </p>
                </div>
                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="closeSteps">{{ t('common.close') }}</SecondaryButton>
                </div>
            </div>
        </Modal>

        <!-- Complete task modal -->
        <Modal :show="completeTarget !== null" @close="completeTarget = null">
            <form @submit.prevent="submitComplete" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('taskProgressAdmin.completeModalTitle') }}</h2>
                <p class="mt-1 text-sm text-gray-500">{{ completeTarget?.task_title }}</p>
                <div v-if="completeTarget?.task_notes" class="mt-3 rounded-md bg-blue-50 p-3 text-sm text-blue-800">
                    {{ completeTarget.task_notes }}
                </div>
                <div v-if="isOn('grade_entry_enabled')" class="mt-4">
                    <InputLabel for="complete-grade" :value="completeTarget?.task_grade ? t('taskProgressAdmin.gradeWithMax', { max: completeTarget.task_grade }) : t('tasksAdmin.gradeColShort')" />
                    <!-- Picked with a tap (2026-10-22, by request). -->
                    <div v-if="completeTarget?.task_grade && isOn('grade_entry_enabled')" class="mt-1">
                        <GradeInput
                            :model-value="completeForm.grade === '' || completeForm.grade === null ? null : Number(completeForm.grade)"
                            :max="Number(completeTarget.task_grade)"
                            :title="completeTarget.task_title"
                            @update:model-value="completeForm.grade = $event ?? ''"
                        />
                    </div>
                    <p v-if="!completeTarget?.task_grade" class="mt-1 text-xs text-gray-500">
                        {{ t('taskProgressAdmin.noGradeHintComplete') }}
                    </p>
                </div>
                <p v-if="completeTarget?.task_scoring?.steps?.length" class="mt-4 rounded-md bg-indigo-50 p-3 text-sm text-indigo-800">{{ t('taskScoring.fromSheet') }}</p>
                <div v-if="hasOptions(completeTarget)" class="mt-4">
                    <WorkItemsInput v-model="completeForm.work_items" :scoring="completeTarget.task_scoring" />
                    <InputError class="mt-2" :message="Object.entries(completeForm.errors).find(([k]) => k.startsWith('work_items'))?.[1]" />
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
                <div v-if="isOn('grade_entry_enabled')" class="mt-4">
                    <InputLabel for="edit-grade" :value="editTarget?.task_grade ? t('taskProgressAdmin.gradeWithMax', { max: editTarget.task_grade }) : t('tasksAdmin.gradeColShort')" />
                    <!-- Picked with a tap (2026-10-22, by request). -->
                    <div v-if="editTarget?.task_grade && isOn('grade_entry_enabled')" class="mt-1">
                        <GradeInput
                            :model-value="editForm.grade === '' || editForm.grade === null ? null : Number(editForm.grade)"
                            :max="Number(editTarget.task_grade)"
                            :title="editTarget.task_title"
                            @update:model-value="editForm.grade = $event ?? ''"
                        />
                    </div>
                    <p v-if="!editTarget?.task_grade" class="mt-1 text-xs text-gray-500">
                        {{ t('taskProgressAdmin.noGradeHintEdit') }}
                    </p>
                </div>
                <div v-if="hasOptions(editTarget)" class="mt-4">
                    <WorkItemsInput v-model="editForm.work_items" :scoring="editTarget.task_scoring" />
                    <InputError class="mt-2" :message="Object.entries(editForm.errors).find(([k]) => k.startsWith('work_items'))?.[1]" />
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
