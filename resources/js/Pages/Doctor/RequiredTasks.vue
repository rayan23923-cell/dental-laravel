<script setup>
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import { Head, Link } from '@inertiajs/vue3';
import { ref } from 'vue';
import Icon from '@/Components/Icon.vue';

defineProps({
    stage: String,
    departments: Array,
});

const openDepartments = ref(new Set());
const toggle = (name) => {
    const next = new Set(openDepartments.value);
    next.has(name) ? next.delete(name) : next.add(name);
    openDepartments.value = next;
};

const statusLabel = (s) =>
    ({ completed: 'مكتملة', assigned: 'قيد التنفيذ', pending: 'معلقة', unassigned: 'لم تبدأ بعد' }[s] ?? s);

const statusClass = (s) =>
    ({
        completed: 'bg-green-100 text-green-800 border-green-500',
        assigned: 'bg-amber-100 text-amber-800 border-amber-400',
        pending: 'bg-gray-200 text-gray-700 border-gray-400',
        unassigned: 'bg-gray-50 text-gray-500 border-indigo-400',
    }[s] ?? 'bg-gray-50 text-gray-500 border-gray-300');

const fmt = (v) => (v ? new Date(v).toLocaleDateString() : null);
</script>

<template>
    <Head title="المهام المطلوبة حسب الأقسام" />

    <DoctorLayout>
        <h2 class="text-lg font-semibold text-gray-800"><Icon name="assignment" class="ml-1" />المهام المطلوبة حسب الأقسام — مرحلة {{ stage ?? '—' }}</h2>

        <div v-if="departments.length === 0" class="mt-4 rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
            لا توجد مهام في مرحلتك حالياً.
        </div>

        <div v-else class="mt-4 space-y-3">
            <div v-for="dept in departments" :key="dept.name" class="overflow-hidden rounded-lg bg-white shadow-sm">
                <button type="button" class="flex w-full items-center justify-between p-4 text-right hover:bg-gray-50" @click="toggle(dept.name)">
                    <span class="font-semibold text-indigo-700">
                        <span class="ml-1 text-gray-400">{{ openDepartments.has(dept.name) ? '▾' : '▸' }}</span>
                        <Icon name="folder" class="ml-1" />{{ dept.name }}
                    </span>
                    <span class="flex gap-1 text-xs">
                        <span class="rounded-full bg-sky-100 px-2 py-0.5 text-sky-800">{{ dept.tasks.length }} مهمة</span>
                        <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">المطلوب: {{ dept.required }}</span>
                        <span class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">مكتملة: {{ dept.completed }}</span>
                    </span>
                </button>

                <div v-if="openDepartments.has(dept.name)" class="border-t border-gray-100 bg-gray-50 p-4">
                    <div v-for="task in dept.tasks" :key="task.id" class="mb-4 last:mb-0">
                        <div class="flex flex-wrap items-center justify-between gap-2">
                            <h4 class="font-medium text-gray-900">
                                {{ task.title }}
                                <span v-if="task.case_sheet" class="mr-1 rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ task.case_sheet }}</span>
                            </h4>
                            <span class="text-xs text-amber-700">المتبقي: {{ task.remaining }} من {{ task.required_count }}</span>
                        </div>
                        <p v-if="task.notes" class="mt-1 text-xs text-gray-500">{{ task.notes }}</p>

                        <div class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
                            <div
                                v-for="slot in task.slots"
                                :key="slot.slot"
                                class="rounded-lg border-r-4 bg-white p-3 shadow-sm"
                                :class="statusClass(slot.status)"
                            >
                                <div class="flex items-center justify-between">
                                    <span class="flex h-7 w-7 items-center justify-center rounded-full bg-indigo-600 text-xs font-bold text-white">
                                        {{ slot.slot }}
                                    </span>
                                    <span class="rounded-full px-2 py-0.5 text-xs" :class="statusClass(slot.status)">
                                        {{ statusLabel(slot.status) }}
                                    </span>
                                </div>
                                <div class="mt-2 space-y-0.5 text-xs text-gray-500">
                                    <div v-if="slot.assigned_date">بدأت: {{ fmt(slot.assigned_date) }}</div>
                                    <div v-if="slot.completion_date">اكتملت: {{ fmt(slot.completion_date) }}</div>
                                    <div v-if="slot.grade">الدرجة: {{ slot.grade }}</div>
                                    <div v-if="slot.notes" class="text-gray-600">{{ slot.notes }}</div>
                                </div>

                                <!-- فتح النموذج — routes this instance to its case
                                     sheet by the task's case-sheet type. For a
                                     not-yet-started slot (2026-08-28), opens an
                                     optional pre-instance draft instead — see
                                     CaseSheetController::openForTask()'s doc
                                     comment for why this never starts the task
                                     itself (still requires the normal QR-scan/
                                     screening-gated flow). -->
                                <Link
                                    :href="slot.instance_id ? route('doctor.case-sheet', slot.instance_id) : route('doctor.case-sheet.for-task', task.id)"
                                    class="mt-2 block rounded bg-indigo-600 px-2 py-1 text-center text-xs font-medium text-white hover:bg-indigo-700"
                                >
                                    <Icon name="description" class="ml-1" />فتح النموذج
                                </Link>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </DoctorLayout>
</template>
