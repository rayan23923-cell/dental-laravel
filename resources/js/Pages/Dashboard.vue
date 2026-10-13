<script setup>
/**
 * Admin dashboard — port of dental_clinics2/admin/dashboard.php: headline
 * counters, done-vs-not-done task breakdown, quick-access cards, the two
 * "latest" lists, and the per-education-type department/stage task section
 * that loads on demand.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputLabel from '@/Components/InputLabel.vue';
import { Head, Link } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import Icon from '@/Components/Icon.vue';

const { t } = useI18n();
const props = defineProps({
    stats: Object,
    latestDoctors: Array,
    latestPatients: Array,
    educationTypes: Array,
    can: Object,
    currentSession: Object,
});

const donePct = computed(() => {
    const total = props.stats.tasks_done + props.stats.tasks_not_done;
    return total > 0 ? Math.round((props.stats.tasks_done / total) * 100) : 0;
});

const instanceTotal = computed(
    () => props.stats.instances_completed + props.stats.instances_assigned + props.stats.instances_pending
);

// --- المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة ---
const selectedEduType = ref('');
const loadingDepts = ref(false);
const departments = ref(null);

const loadTasksByDept = async () => {
    if (!selectedEduType.value) {
        departments.value = null;
        return;
    }
    loadingDepts.value = true;
    try {
        const { data } = await axios.get(route('dashboard.tasks-by-education-type', selectedEduType.value));
        departments.value = data.departments;
    } finally {
        loadingDepts.value = false;
    }
};

const fmt = (v) => (v ? new Date(v).toLocaleDateString() : '—');
</script>

<template>
    <Head :title="t('dashboard.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('dashboard.title') }}</h2>
        </template>

        <div class="py-8">
            <div class="mx-auto max-w-7xl space-y-6 px-4 sm:px-6 lg:px-8">
                <div v-if="currentSession" class="flex items-center gap-2 rounded-lg border border-indigo-200 bg-indigo-50 p-3 text-sm text-indigo-900">
                    <Icon name="calendar_month" class="ml-1" />
                    {{ t('common.academicYearActive') }} <strong>{{ currentSession.name }}</strong>
                </div>

                <!-- Headline counters -->
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                    <div class="rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 p-6 text-center text-white shadow">
                        <div class="text-3xl"><Icon name="stethoscope" class="ml-1" /></div>
                        <div class="mt-2 text-3xl font-bold">{{ stats.doctors }}</div>
                        <p class="text-sm opacity-90">{{ t('dashboard.doctorsCount') }}</p>
                    </div>
                    <div class="rounded-lg bg-gradient-to-br from-sky-500 to-cyan-600 p-6 text-center text-white shadow">
                        <div class="text-3xl"><Icon name="diversity_3" class="ml-1" /></div>
                        <div class="mt-2 text-3xl font-bold">{{ stats.patients }}</div>
                        <p class="text-sm opacity-90">{{ t('dashboard.patientsCount') }}</p>
                    </div>
                    <div class="rounded-lg bg-gradient-to-br from-emerald-500 to-green-600 p-6 text-center text-white shadow">
                        <div class="text-3xl"><Icon name="assignment" class="ml-1" /></div>
                        <div class="mt-2 text-3xl font-bold">{{ stats.tasks }}</div>
                        <p class="text-sm opacity-90">{{ t('dashboard.tasksCount') }}</p>
                    </div>
                </div>

                <!-- المهام المنجزة مقابل غير المنجزة -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <div class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="text-sm font-semibold text-gray-800">{{ t('dashboard.doneVsNotDone') }}</h3>
                        <div class="mt-3 h-5 overflow-hidden rounded-full bg-gray-100">
                            <div class="flex h-full items-center justify-center bg-green-500 text-xs font-medium text-white" :style="{ width: donePct + '%' }">
                                {{ donePct }}%
                            </div>
                        </div>
                        <div class="mt-3 flex justify-between text-sm">
                            <span class="text-green-700">{{ t('dashboard.done') }}: <strong>{{ stats.tasks_done }}</strong></span>
                            <span class="text-gray-600">{{ t('dashboard.notDone') }}: <strong>{{ stats.tasks_not_done }}</strong></span>
                        </div>
                    </div>

                    <div class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="text-sm font-semibold text-gray-800">{{ t('dashboard.taskStatuses') }}</h3>
                        <div class="mt-3 grid grid-cols-3 gap-2 text-center">
                            <div class="rounded-md bg-green-50 p-3">
                                <div class="text-xl font-bold text-green-700">{{ stats.instances_completed }}</div>
                                <div class="text-xs text-gray-500">{{ t('dashboard.completed') }}</div>
                            </div>
                            <div class="rounded-md bg-amber-50 p-3">
                                <div class="text-xl font-bold text-amber-700">{{ stats.instances_assigned }}</div>
                                <div class="text-xs text-gray-500">{{ t('dashboard.inProgress') }}</div>
                            </div>
                            <div class="rounded-md bg-gray-100 p-3">
                                <div class="text-xl font-bold text-gray-700">{{ stats.instances_pending }}</div>
                                <div class="text-xs text-gray-500">{{ t('dashboard.pending') }}</div>
                            </div>
                        </div>
                        <p class="mt-2 text-xs text-gray-400">{{ t('dashboard.totalCases', { n: instanceTotal }) }}</p>
                    </div>
                </div>

                <!-- Quick access -->
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <Link v-if="can.task_progress" :href="route('task-progress.index')" class="block rounded-lg bg-sky-600 p-5 text-center text-white shadow transition hover:bg-sky-700">
                        <div class="text-2xl"><Icon name="assignment" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">{{ t('dashboard.taskProgressMgmt') }}</h3>
                        <p class="mt-1 text-xs opacity-90">{{ t('dashboard.taskProgressMgmtDesc') }}</p>
                    </Link>
                    <Link v-if="can.doctors" :href="route('doctors.index')" class="block rounded-lg bg-emerald-600 p-5 text-center text-white shadow transition hover:bg-emerald-700">
                        <div class="text-2xl"><Icon name="stethoscope" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">{{ t('dashboard.doctorsProgress') }}</h3>
                        <p class="mt-1 text-xs opacity-90">{{ t('dashboard.doctorsProgressDesc') }}</p>
                    </Link>
                    <Link v-if="can.patients" :href="route('patient-registrations.index')" class="block rounded-lg bg-indigo-600 p-5 text-center text-white shadow transition hover:bg-indigo-700">
                        <div class="text-2xl"><Icon name="how_to_reg" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">{{ t('nav.patientRegistrations') }}</h3>
                        <p class="mt-1 text-xs opacity-90">{{ t('dashboard.registerPatientDesc') }}</p>
                    </Link>
                    <Link v-if="can.settings" :href="route('clinic-settings.edit')" class="block rounded-lg bg-slate-700 p-5 text-center text-white shadow transition hover:bg-slate-800">
                        <div class="text-2xl"><Icon name="settings" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">{{ t('nav.settingsGroup') }}</h3>
                        <p class="mt-1 text-xs opacity-90">{{ t('dashboard.settingsDesc') }}</p>
                    </Link>
                    <!-- Infectious-disease screening gate (2026-08-25) had no
                         dashboard entry point at all — added (2026-08-26). -->
                    <Link v-if="can.patient_screening" :href="route('lab.index')" class="block rounded-lg bg-rose-600 p-5 text-center text-white shadow transition hover:bg-rose-700">
                        <div class="text-2xl"><Icon name="coronavirus" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">{{ t('dashboard.lab') }}</h3>
                        <p class="mt-1 text-xs opacity-90">{{ t('dashboard.labDesc') }}</p>
                    </Link>
                </div>

                <!-- Latest lists -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <div class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <h3 class="border-b border-gray-100 px-5 py-3 text-sm font-semibold text-gray-800">{{ t('dashboard.latestDoctors') }}</h3>
                        <table class="min-w-full divide-y divide-gray-200">
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="d in latestDoctors" :key="d.id">
                                    <td class="px-5 py-2 text-sm font-medium text-gray-900">{{ d.name }}</td>
                                    <td class="px-5 py-2 text-sm text-gray-500">{{ d.education_type ?? '—' }}</td>
                                    <td class="px-5 py-2 text-left text-xs text-gray-400">{{ fmt(d.created_at) }}</td>
                                </tr>
                                <tr v-if="latestDoctors.length === 0">
                                    <td colspan="3" class="px-5 py-6 text-center text-sm text-gray-500">{{ t('dashboard.noDoctorsYet') }}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>

                    <div class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <h3 class="border-b border-gray-100 px-5 py-3 text-sm font-semibold text-gray-800">{{ t('dashboard.latestPatients') }}</h3>
                        <table class="min-w-full divide-y divide-gray-200">
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="p in latestPatients" :key="p.id">
                                    <td class="px-5 py-2 text-sm font-medium text-gray-900">{{ p.name }}</td>
                                    <td class="px-5 py-2 text-sm text-gray-500">{{ p.phone ?? '—' }}</td>
                                    <td class="px-5 py-2 text-left text-xs text-gray-400">{{ fmt(p.created_at) }}</td>
                                </tr>
                                <tr v-if="latestPatients.length === 0">
                                    <td colspan="3" class="px-5 py-6 text-center text-sm text-gray-500">{{ t('dashboard.noPatientsYet') }}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>

                <!-- المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة -->
                <div class="overflow-hidden rounded-lg bg-white shadow-sm">
                    <h3 class="border-b border-gray-100 bg-sky-600 px-5 py-3 text-sm font-semibold text-white">
                        {{ t('dashboard.tasksByEduType') }}
                    </h3>
                    <div class="p-5">
                        <div class="max-w-xs">
                            <InputLabel :value="t('dashboard.chooseEduType')" />
                            <select v-model="selectedEduType" @change="loadTasksByDept" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">{{ t('dashboard.selectPlaceholder') }}</option>
                                <option v-for="eduType in educationTypes" :key="eduType.id" :value="eduType.id">{{ eduType.name }}</option>
                            </select>
                        </div>

                        <div v-if="loadingDepts" class="py-6 text-center text-sm text-gray-500">{{ t('common.loading') }}</div>

                        <div v-else-if="departments && departments.length === 0" class="py-6 text-center text-sm text-gray-500">
                            {{ t('dashboard.noTasksForEduType') }}
                        </div>

                        <div v-else-if="departments" class="mt-4 space-y-3">
                            <div v-for="dept in departments" :key="dept.department + dept.stage" class="rounded-lg border border-gray-200">
                                <div class="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 bg-gray-50 px-4 py-2">
                                    <span class="font-medium text-gray-900">
                                        <Icon name="folder" class="ml-1" />{{ dept.department }}
                                        <span class="mr-1 text-xs text-gray-500">({{ dept.stage ?? '—' }})</span>
                                    </span>
                                    <span class="flex gap-1 text-xs">
                                        <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">{{ t('dashboard.requiredLabel') }}: {{ dept.required }}</span>
                                        <span class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">{{ t('dashboard.completed') }}: {{ dept.completed }}</span>
                                    </span>
                                </div>
                                <table class="min-w-full divide-y divide-gray-200">
                                    <thead class="bg-gray-50">
                                        <tr>
                                            <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">{{ t('dashboard.taskCol') }}</th>
                                            <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('dashboard.requiredLabel') }}</th>
                                            <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('dashboard.completed') }}</th>
                                            <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">{{ t('dashboard.remainingCol') }}</th>
                                        </tr>
                                    </thead>
                                    <tbody class="divide-y divide-gray-100">
                                        <tr v-for="task in dept.tasks" :key="task.id">
                                            <td class="px-4 py-2 text-sm text-gray-900">{{ task.title }}</td>
                                            <td class="px-4 py-2 text-center text-sm text-gray-500">{{ task.required }}</td>
                                            <td class="px-4 py-2 text-center text-sm text-green-700">{{ task.completed }}</td>
                                            <td class="px-4 py-2 text-center text-sm text-amber-700">{{ task.remaining }}</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
