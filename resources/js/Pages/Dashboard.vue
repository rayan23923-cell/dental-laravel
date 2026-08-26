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
import axios from 'axios';
import Icon from '@/Components/Icon.vue';

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
    <Head title="لوحة التحكم" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">لوحة التحكم</h2>
        </template>

        <div class="py-8">
            <div class="mx-auto max-w-7xl space-y-6 px-4 sm:px-6 lg:px-8">
                <div v-if="currentSession" class="flex items-center gap-2 rounded-lg border border-indigo-200 bg-indigo-50 p-3 text-sm text-indigo-900">
                    <Icon name="calendar_month" class="ml-1" />
                    العام الدراسي النشط: <strong>{{ currentSession.name }}</strong>
                </div>

                <!-- Headline counters -->
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                    <div class="rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 p-6 text-center text-white shadow">
                        <div class="text-3xl"><Icon name="stethoscope" class="ml-1" /></div>
                        <div class="mt-2 text-3xl font-bold">{{ stats.doctors }}</div>
                        <p class="text-sm opacity-90">عدد الأطباء</p>
                    </div>
                    <div class="rounded-lg bg-gradient-to-br from-sky-500 to-cyan-600 p-6 text-center text-white shadow">
                        <div class="text-3xl"><Icon name="diversity_3" class="ml-1" /></div>
                        <div class="mt-2 text-3xl font-bold">{{ stats.patients }}</div>
                        <p class="text-sm opacity-90">عدد المراجعين</p>
                    </div>
                    <div class="rounded-lg bg-gradient-to-br from-emerald-500 to-green-600 p-6 text-center text-white shadow">
                        <div class="text-3xl"><Icon name="assignment" class="ml-1" /></div>
                        <div class="mt-2 text-3xl font-bold">{{ stats.tasks }}</div>
                        <p class="text-sm opacity-90">عدد المهام</p>
                    </div>
                </div>

                <!-- المهام المنجزة مقابل غير المنجزة -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <div class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="text-sm font-semibold text-gray-800">المهام المنجزة مقابل غير المنجزة</h3>
                        <div class="mt-3 h-5 overflow-hidden rounded-full bg-gray-100">
                            <div class="flex h-full items-center justify-center bg-green-500 text-xs font-medium text-white" :style="{ width: donePct + '%' }">
                                {{ donePct }}%
                            </div>
                        </div>
                        <div class="mt-3 flex justify-between text-sm">
                            <span class="text-green-700">منجزة: <strong>{{ stats.tasks_done }}</strong></span>
                            <span class="text-gray-600">غير منجزة: <strong>{{ stats.tasks_not_done }}</strong></span>
                        </div>
                    </div>

                    <div class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="text-sm font-semibold text-gray-800">حالات المهام</h3>
                        <div class="mt-3 grid grid-cols-3 gap-2 text-center">
                            <div class="rounded-md bg-green-50 p-3">
                                <div class="text-xl font-bold text-green-700">{{ stats.instances_completed }}</div>
                                <div class="text-xs text-gray-500">مكتملة</div>
                            </div>
                            <div class="rounded-md bg-amber-50 p-3">
                                <div class="text-xl font-bold text-amber-700">{{ stats.instances_assigned }}</div>
                                <div class="text-xs text-gray-500">قيد التنفيذ</div>
                            </div>
                            <div class="rounded-md bg-gray-100 p-3">
                                <div class="text-xl font-bold text-gray-700">{{ stats.instances_pending }}</div>
                                <div class="text-xs text-gray-500">معلقة</div>
                            </div>
                        </div>
                        <p class="mt-2 text-xs text-gray-400">الإجمالي: {{ instanceTotal }} حالة</p>
                    </div>
                </div>

                <!-- Quick access -->
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <Link v-if="can.task_progress" :href="route('task-progress.index')" class="block rounded-lg bg-sky-600 p-5 text-center text-white shadow transition hover:bg-sky-700">
                        <div class="text-2xl"><Icon name="assignment" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">إدارة تقدم المهام</h3>
                        <p class="mt-1 text-xs opacity-90">تخصيص وإدارة مهام الأطباء</p>
                    </Link>
                    <Link v-if="can.doctors" :href="route('doctors.index')" class="block rounded-lg bg-emerald-600 p-5 text-center text-white shadow transition hover:bg-emerald-700">
                        <div class="text-2xl"><Icon name="stethoscope" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">عرض تقدم الأطباء</h3>
                        <p class="mt-1 text-xs opacity-90">مراقبة تقدم مهام الأطباء الفردي</p>
                    </Link>
                    <Link v-if="can.patients" :href="route('patient-registrations.create')" class="block rounded-lg bg-indigo-600 p-5 text-center text-white shadow transition hover:bg-indigo-700">
                        <div class="text-2xl"><Icon name="add" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">تسجيل مريض جديد</h3>
                        <p class="mt-1 text-xs opacity-90">تسجيل مرضى جدد بسهولة</p>
                    </Link>
                    <Link v-if="can.settings" :href="route('clinic-settings.edit')" class="block rounded-lg bg-slate-700 p-5 text-center text-white shadow transition hover:bg-slate-800">
                        <div class="text-2xl"><Icon name="settings" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">الإعدادات</h3>
                        <p class="mt-1 text-xs opacity-90">بيانات العيادة والبريد الإلكتروني</p>
                    </Link>
                    <!-- Infectious-disease screening gate (2026-08-25) had no
                         dashboard entry point at all — added (2026-08-26). -->
                    <Link v-if="can.patient_screening" :href="route('patient-registrations.index')" class="block rounded-lg bg-rose-600 p-5 text-center text-white shadow transition hover:bg-rose-700">
                        <div class="text-2xl"><Icon name="coronavirus" class="ml-1" /></div>
                        <h3 class="mt-2 font-semibold">المختبر</h3>
                        <p class="mt-1 text-xs opacity-90">تسجيل نتيجة فحص السلامة من الأمراض المعدية</p>
                    </Link>
                </div>

                <!-- Latest lists -->
                <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <div class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <h3 class="border-b border-gray-100 px-5 py-3 text-sm font-semibold text-gray-800">أحدث الأطباء</h3>
                        <table class="min-w-full divide-y divide-gray-200">
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="d in latestDoctors" :key="d.id">
                                    <td class="px-5 py-2 text-sm font-medium text-gray-900">{{ d.name }}</td>
                                    <td class="px-5 py-2 text-sm text-gray-500">{{ d.education_type ?? '—' }}</td>
                                    <td class="px-5 py-2 text-left text-xs text-gray-400">{{ fmt(d.created_at) }}</td>
                                </tr>
                                <tr v-if="latestDoctors.length === 0">
                                    <td colspan="3" class="px-5 py-6 text-center text-sm text-gray-500">لا يوجد أطباء بعد.</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>

                    <div class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <h3 class="border-b border-gray-100 px-5 py-3 text-sm font-semibold text-gray-800">أحدث المراجعين</h3>
                        <table class="min-w-full divide-y divide-gray-200">
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="p in latestPatients" :key="p.id">
                                    <td class="px-5 py-2 text-sm font-medium text-gray-900">{{ p.name }}</td>
                                    <td class="px-5 py-2 text-sm text-gray-500">{{ p.phone ?? '—' }}</td>
                                    <td class="px-5 py-2 text-left text-xs text-gray-400">{{ fmt(p.created_at) }}</td>
                                </tr>
                                <tr v-if="latestPatients.length === 0">
                                    <td colspan="3" class="px-5 py-6 text-center text-sm text-gray-500">لا يوجد مراجعون بعد.</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>

                <!-- المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة -->
                <div class="overflow-hidden rounded-lg bg-white shadow-sm">
                    <h3 class="border-b border-gray-100 bg-sky-600 px-5 py-3 text-sm font-semibold text-white">
                        المهام المطلوبة لكل قسم ومرحلة حسب نوع الدراسة
                    </h3>
                    <div class="p-5">
                        <div class="max-w-xs">
                            <InputLabel value="اختر نوع الدراسة" />
                            <select v-model="selectedEduType" @change="loadTasksByDept" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">-- اختر --</option>
                                <option v-for="t in educationTypes" :key="t.id" :value="t.id">{{ t.name }}</option>
                            </select>
                        </div>

                        <div v-if="loadingDepts" class="py-6 text-center text-sm text-gray-500">جاري التحميل...</div>

                        <div v-else-if="departments && departments.length === 0" class="py-6 text-center text-sm text-gray-500">
                            لا توجد مهام لنوع الدراسة المحدد.
                        </div>

                        <div v-else-if="departments" class="mt-4 space-y-3">
                            <div v-for="dept in departments" :key="dept.department + dept.stage" class="rounded-lg border border-gray-200">
                                <div class="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 bg-gray-50 px-4 py-2">
                                    <span class="font-medium text-gray-900">
                                        <Icon name="folder" class="ml-1" />{{ dept.department }}
                                        <span class="mr-1 text-xs text-gray-500">({{ dept.stage ?? '—' }})</span>
                                    </span>
                                    <span class="flex gap-1 text-xs">
                                        <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">المطلوب: {{ dept.required }}</span>
                                        <span class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">مكتملة: {{ dept.completed }}</span>
                                    </span>
                                </div>
                                <table class="min-w-full divide-y divide-gray-200">
                                    <thead class="bg-gray-50">
                                        <tr>
                                            <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">المهمة</th>
                                            <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">المطلوب</th>
                                            <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">مكتملة</th>
                                            <th class="px-4 py-2 text-center text-xs font-medium uppercase text-gray-500">المتبقي</th>
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
