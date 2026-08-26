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
import axios from 'axios';
import Icon from '@/Components/Icon.vue';

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

const STATUS_FILTERS = [
    { key: 'all', label: 'الكل' },
    { key: 'not-started', label: 'غير منجزة' },
    { key: 'started', label: 'قيد التنفيذ' },
    { key: 'finished', label: 'مكتملة' },
];

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
    ({ completed: 'مكتملة', assigned: 'قيد التنفيذ', pending: 'معلقة', unassigned: 'لم تبدأ بعد' }[status] ?? status);

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
const startForm = useForm({ doctor_id: null, task_id: null, patient_registration_id: null, notes: '' });
const startTarget = ref(null);
const openStart = (doctor, card) => {
    startTarget.value = { doctor, card };
    startForm.doctor_id = doctor.id;
    startForm.task_id = card.task_id;
    startForm.patient_registration_id = null;
    startForm.notes = '';
    startPatientResult.value = null;
    startPatientError.value = '';
    startPatientScanning.value = false;
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

// --- Patient screening scan, inside the start-task modal (2026-08-26) —
// a task can't be started without first identifying which patient it's
// for and confirming their infectious-disease screening is "سليم". Real
// enforcement is server-side (`PatientScreeningGate`); this just avoids a
// wasted round trip and matches this page's existing `QrScanner.vue`
// pattern (see `onDecoded`/`openScanner` above) rather than a new widget.
const startPatientScannerRef = ref(null);
const startPatientResult = ref(null);
const startPatientError = ref('');
const startPatientScanning = ref(false);

const openStartPatientScanner = async () => {
    startPatientError.value = '';
    startPatientScanning.value = true;
    await nextTick();
    startPatientScannerRef.value?.start();
};

const onStartPatientDecoded = async (text) => {
    startPatientError.value = '';
    try {
        const { data } = await axios.post(route('patient-registrations.scan'), { payload: text });
        startPatientResult.value = data.data.registration;
        startForm.patient_registration_id = data.data.registration.id;
        startPatientScannerRef.value?.stop();
        startPatientScanning.value = false;
    } catch (e) {
        startPatientError.value = e?.response?.data?.message ?? 'تعذر قراءة الرمز.';
    }
};

const rescanStartPatient = () => {
    startPatientResult.value = null;
    startForm.patient_registration_id = null;
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
        scanError.value = e?.response?.data?.message ?? 'تعذر قراءة الرمز.';
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
    <Head title="تقدم المهام" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">إدارة تقدم المهام</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-7xl space-y-4 sm:px-6 lg:px-8">
                <!-- New — this screen previously had no active-year banner
                     at all, unlike Doctors/Groups/Tasks. -->
                <div v-if="currentSession" class="flex items-center gap-2 rounded-lg border border-indigo-200 bg-indigo-50 p-3 text-sm text-indigo-900">
                    <Icon name="calendar_month" class="ml-1" />
                    العام الدراسي النشط: <strong>{{ currentSession.name }}</strong>
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
                            <InputLabel value="اليوم" />
                            <select v-model="day" @change="applyFilters" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">اختر اليوم</option>
                                <option v-for="d in days" :key="d" :value="d">{{ d }}</option>
                            </select>
                        </div>
                        <div>
                            <InputLabel value="نوع التعليم" />
                            <select v-model="educationType" @change="onEducationTypeChange" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">اختر نوع التعليم</option>
                                <option v-for="t in educationTypes" :key="t.id" :value="t.id">{{ t.name }}</option>
                            </select>
                        </div>
                        <div>
                            <InputLabel value="المرحلة" />
                            <select v-model="stage" @change="applyFilters" :disabled="stages.length === 0" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">اختر المرحلة</option>
                                <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                        </div>
                        <div class="flex items-end gap-2">
                            <SecondaryButton @click="clearFilters">مسح الفلاتر</SecondaryButton>
                            <button type="button" @click="openScanner" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-700">
                                <Icon name="qr_code_2" class="ml-1" />مسح رمز QR
                            </button>
                        </div>
                    </div>
                </div>

                <!-- Groups for the selected day -->
                <div v-if="filters.day && groups.length" class="rounded-lg bg-white p-4 shadow-sm">
                    <h3 class="mb-3 text-sm font-semibold text-gray-700">المجموعات المتاحة في يوم {{ filters.day }}</h3>
                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                        <div v-for="g in groups" :key="g.id" class="rounded-lg border border-indigo-200 p-3">
                            <div class="font-medium text-indigo-700">{{ g.name }}</div>
                            <div class="mt-1 text-xs text-gray-500">
                                المرحلة: {{ g.stage_name ?? '—' }}<br />
                                نوع التعليم: {{ g.education_type_name ?? '—' }}
                            </div>
                            <PrimaryButton class="mt-3" @click="loadGroup(g.id)">عرض الأطباء</PrimaryButton>
                        </div>
                    </div>
                </div>
                <div v-else-if="filters.day" class="rounded-md bg-blue-50 p-4 text-sm text-blue-700">
                    لا توجد مجموعات متاحة في يوم {{ filters.day }} بهذه الفلاتر.
                </div>

                <div v-if="loading" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                    جاري التحميل...
                </div>

                <!-- Group detail -->
                <div v-if="detail" class="space-y-4">
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <h3 class="font-medium text-gray-900">أطباء مجموعة: {{ detail.group.name }}</h3>
                        <p class="mt-1 text-xs text-gray-500">
                            المرحلة: {{ detail.group.stage_name ?? '—' }} · نوع التعليم: {{ detail.group.education_type_name ?? '—' }}
                        </p>
                    </div>

                    <div v-if="detail.departments.length === 0" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                        لا توجد أقسام متاحة لهذه المرحلة.
                    </div>

                    <template v-else>
                        <!-- Department tabs -->
                        <div class="flex flex-wrap gap-1 border-b border-gray-200">
                            <button
                                v-for="dept in detail.departments"
                                :key="dept.id"
                                @click="activeDepartmentId = dept.id"
                                class="border-b-2 px-4 py-2 text-sm font-medium"
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
                                    <strong class="text-gray-800">القسم: {{ activeDepartment.name }}</strong>
                                    <span class="ml-2 rounded-full bg-gray-200 px-2 py-0.5 text-xs">{{ activeDepartment.task_count }} مهام</span>
                                    <span class="ml-2 rounded-full bg-blue-200 px-2 py-0.5 text-xs">المطلوب: {{ activeDepartment.total_required }}</span>
                                </div>
                                <div class="flex gap-1 text-xs">
                                    <span class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">مكتملة {{ activeDepartment.totals.completed }}</span>
                                    <span class="rounded-full bg-yellow-100 px-2 py-0.5 text-yellow-800">قيد التنفيذ {{ activeDepartment.totals.assigned }}</span>
                                    <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">متاحة {{ activeDepartment.totals.pending }}</span>
                                    <span class="rounded-full bg-gray-800 px-2 py-0.5 text-white">الإجمالي {{ activeDepartment.totals.total_instances }}</span>
                                </div>
                            </div>

                            <!-- Search + status filter -->
                            <div class="flex flex-wrap items-center justify-between gap-3">
                                <TextInput v-model="search" type="text" placeholder="البحث عن طبيب (الاسم أو اسم المستخدم)..." class="w-full max-w-sm" />
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
                                                <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">الطبيب</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">المطلوب</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">مكتملة</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">قيد التنفيذ</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">معلقة</th>
                                                <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">غير مخصص</th>
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
                                                            لا توجد مهام مطابقة للحالة المحددة
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
                                                                        <span v-if="card.task_notes" class="rounded-full bg-gray-200 px-2 py-0.5 text-gray-700" :title="card.task_notes">ملاحظات المهمة</span>
                                                                        <span v-if="card.task_grade" class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">الدرجة: {{ card.task_grade }}</span>
                                                                        <span v-if="card.notes" class="rounded-full bg-blue-100 px-2 py-0.5 text-blue-800" :title="card.notes">{{ card.notes.slice(0, 30) }}{{ card.notes.length > 30 ? '…' : '' }}</span>
                                                                        <span v-if="card.grade" class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">درجة الحالة: {{ card.grade }}</span>
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
                                                                        فتح النموذج
                                                                    </a>
                                                                    <button v-if="card.status === 'unassigned'" @click.stop="openStart(doctor, card)" class="rounded bg-indigo-600 px-2 py-1 text-white hover:bg-indigo-700">
                                                                        بدء المهمة
                                                                    </button>
                                                                    <button v-if="card.status === 'assigned'" @click.stop="openComplete(card)" class="rounded bg-green-600 px-2 py-1 text-white hover:bg-green-700">
                                                                        تأشير كمكتملة
                                                                    </button>
                                                                    <button v-if="card.instance_id && ['assigned', 'completed'].includes(card.status)" @click.stop="openEdit(card)" class="rounded bg-blue-500 px-2 py-1 text-white hover:bg-blue-600">
                                                                        تعديل
                                                                    </button>
                                                                </div>
                                                            </div>
                                                        </div>
                                                    </td>
                                                </tr>
                                            </template>
                                            <tr v-if="visibleDoctors.length === 0">
                                                <td colspan="6" class="px-4 py-8 text-center text-sm text-gray-500">لا توجد نتائج مطابقة للبحث.</td>
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
                <h2 class="text-lg font-medium text-gray-900"><Icon name="qr_code_2" class="ml-1" />مسح رمز QR</h2>

                <div v-if="!scanResult" class="mt-4">
                    <QrScanner ref="scannerRef" @decoded="onDecoded" />
                    <div v-if="scanError" class="mt-3 rounded-md bg-red-50 p-3 text-sm text-red-700">{{ scanError }}</div>
                </div>

                <!-- Result: an existing assigned case -->
                <div v-else-if="scanResult.kind === 'task_instance'" class="mt-4 space-y-3">
                    <div class="rounded-lg border border-green-200 bg-green-50 p-4">
                        <p class="text-sm text-green-800"><Icon name="check_circle" class="ml-1" />تم التعرف على حالة المهمة رقم {{ scanResult.instance_id }}</p>
                        <dl class="mt-2 space-y-1 text-sm text-gray-700">
                            <div><span class="text-gray-500">الطبيب:</span> {{ scanResult.doctor.name ?? '—' }}</div>
                            <div><span class="text-gray-500">المهمة:</span> {{ scanResult.task.title }}</div>
                            <div><span class="text-gray-500">القسم:</span> {{ scanResult.task.department ?? '—' }}</div>
                            <div><span class="text-gray-500">النموذج:</span> {{ scanResult.task.case_sheet ?? '—' }}</div>
                            <div><span class="text-gray-500">الحالة:</span> {{ statusLabel(scanResult.status) }}</div>
                        </dl>
                    </div>
                    <div class="flex flex-wrap justify-end gap-2">
                        <SecondaryButton @click="rescan">مسح رمز آخر</SecondaryButton>
                        <a :href="scanResult.case_sheet_url" class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                            <Icon name="description" class="ml-1" />فتح النموذج
                        </a>
                    </div>
                </div>

                <!-- Result: a task the doctor hasn't started yet -->
                <div v-else-if="scanResult.kind === 'pending_task'" class="mt-4 space-y-3">
                    <div class="rounded-lg border border-amber-200 bg-amber-50 p-4">
                        <p class="text-sm text-amber-800">مهمة لم تبدأ بعد لهذا الطبيب</p>
                        <dl class="mt-2 space-y-1 text-sm text-gray-700">
                            <div><span class="text-gray-500">الطبيب:</span> {{ scanResult.doctor.name }}</div>
                            <div><span class="text-gray-500">المهمة:</span> {{ scanResult.task.title }}</div>
                            <div><span class="text-gray-500">القسم:</span> {{ scanResult.task.department ?? '—' }}</div>
                            <div><span class="text-gray-500">المطلوب:</span> {{ scanResult.task.required_count }}</div>
                        </dl>
                    </div>
                    <div class="flex flex-wrap justify-end gap-2">
                        <SecondaryButton @click="rescan">مسح رمز آخر</SecondaryButton>
                        <PrimaryButton :disabled="startForm.processing" @click="startFromScan"><Icon name="play_arrow" class="ml-1" />بدء المهمة لهذا الطبيب</PrimaryButton>
                    </div>
                </div>

                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="closeScanner">إغلاق</SecondaryButton>
                </div>
            </div>
        </Modal>

        <!-- Start task modal -->
        <Modal :show="startTarget !== null" @close="startTarget = null">
            <form @submit.prevent="submitStart" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">بدء مهمة للطبيب</h2>
                <p class="mt-1 text-sm text-gray-500">{{ startTarget?.doctor.name }} — {{ startTarget?.card.task_title }}</p>

                <!-- Infectious-disease screening gate (2026-08-26) — must scan
                     the patient's registration ticket QR and confirm their
                     screening is "سليم" before the task can start. -->
                <div class="mt-4">
                    <InputLabel value="المريض" />
                    <div v-if="!startPatientResult" class="mt-1">
                        <SecondaryButton type="button" @click="openStartPatientScanner" v-if="!startPatientScanning">
                            <Icon name="qr_code_scanner" class="ml-1" />امسح رمز المريض
                        </SecondaryButton>
                        <div v-else class="mt-2">
                            <QrScanner ref="startPatientScannerRef" @decoded="onStartPatientDecoded" />
                        </div>
                        <div v-if="startPatientError" class="mt-2 rounded-md bg-red-50 p-2 text-sm text-red-700">{{ startPatientError }}</div>
                    </div>
                    <div v-else class="mt-1 rounded-lg border p-3" :class="startPatientResult.screening_status === 'clear' ? 'border-green-200 bg-green-50' : 'border-red-200 bg-red-50'">
                        <p class="text-sm font-medium text-gray-800">{{ startPatientResult.name }} — {{ startPatientResult.phone }}</p>
                        <p class="mt-1 text-sm" :class="startPatientResult.screening_status === 'clear' ? 'text-green-800' : 'text-red-800'">
                            <template v-if="startPatientResult.screening_status === 'clear'"><Icon name="check_circle" class="ml-1" />الفحص: سليم</template>
                            <template v-else-if="startPatientResult.screening_status === 'flagged'"><Icon name="cancel" class="ml-1" />الفحص: غير سليم — لا يمكن البدء</template>
                            <template v-else><Icon name="hourglass_empty" class="ml-1" />بانتظار فحص المختبر — لا يمكن البدء</template>
                        </p>
                        <button type="button" class="mt-2 text-sm text-indigo-600 hover:underline" @click="rescanStartPatient">مسح رمز آخر</button>
                    </div>
                </div>

                <div class="mt-4">
                    <InputLabel for="start-notes" value="ملاحظات" />
                    <textarea id="start-notes" v-model="startForm.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="startTarget = null">إلغاء</SecondaryButton>
                    <PrimaryButton :disabled="startForm.processing || startPatientResult?.screening_status !== 'clear'">بدء</PrimaryButton>
                </div>
            </form>
        </Modal>

        <!-- Complete task modal -->
        <Modal :show="completeTarget !== null" @close="completeTarget = null">
            <form @submit.prevent="submitComplete" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">تأشير المهمة كمكتملة</h2>
                <p class="mt-1 text-sm text-gray-500">{{ completeTarget?.task_title }}</p>
                <div v-if="completeTarget?.task_notes" class="mt-3 rounded-md bg-blue-50 p-3 text-sm text-blue-800">
                    {{ completeTarget.task_notes }}
                </div>
                <div class="mt-4">
                    <InputLabel for="complete-grade" :value="completeTarget?.task_grade ? `الدرجة (الحد الأقصى: ${completeTarget.task_grade})` : 'الدرجة'" />
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
                        لا يمكن تعيين درجة لأن درجة المهمة غير محددة — يمكن إكمال المهمة بدون درجة.
                    </p>
                </div>
                <div class="mt-4">
                    <InputLabel for="complete-notes" value="ملاحظات الحالة" />
                    <textarea id="complete-notes" v-model="completeForm.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="completeTarget = null">إلغاء</SecondaryButton>
                    <PrimaryButton :disabled="completeForm.processing">تأكيد الإكمال</PrimaryButton>
                </div>
            </form>
        </Modal>

        <!-- Edit instance modal -->
        <Modal :show="editTarget !== null" @close="editTarget = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">تعديل ملاحظات ودرجة المهمة</h2>
                <p class="mt-1 text-sm text-gray-500">{{ editTarget?.task_title }}</p>
                <div class="mt-4">
                    <InputLabel for="edit-grade" :value="editTarget?.task_grade ? `الدرجة (الحد الأقصى: ${editTarget.task_grade})` : 'الدرجة'" />
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
                        لا يمكن تعيين درجة لأن درجة المهمة غير محددة في جدول المهام.
                    </p>
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-notes" value="ملاحظات" />
                    <textarea id="edit-notes" v-model="editForm.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editTarget = null">إلغاء</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">حفظ</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
