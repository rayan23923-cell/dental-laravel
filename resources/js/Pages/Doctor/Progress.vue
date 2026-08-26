<script setup>
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import { Head } from '@inertiajs/vue3';
import Icon from '@/Components/Icon.vue';

defineProps({
    stats: Object,
    tasks: Array,
});

const statusLabel = (s) => ({ completed: 'مكتملة', assigned: 'قيد التنفيذ', pending: 'معلقة' }[s] ?? s);
const statusClass = (s) =>
    ({
        completed: 'bg-green-100 text-green-800',
        assigned: 'bg-amber-100 text-amber-800',
        pending: 'bg-gray-200 text-gray-700',
    }[s] ?? 'bg-gray-100 text-gray-600');

const pct = (done, total) => (total > 0 ? Math.round((done / total) * 100) : 0);
const fmt = (v) => (v ? new Date(v).toLocaleString() : '—');
</script>

<template>
    <Head title="تقدم المهام التفصيلي" />

    <DoctorLayout>
        <h2 class="text-lg font-semibold text-gray-800"><Icon name="trending_up" class="ml-1" />تقدم المهام التفصيلي</h2>

        <div class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-gray-900">{{ stats.total }}</div>
                <div class="text-xs text-gray-500">إجمالي الحالات</div>
            </div>
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-green-700">{{ stats.completed }}</div>
                <div class="text-xs text-gray-500">مكتملة</div>
            </div>
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-amber-700">{{ stats.assigned }}</div>
                <div class="text-xs text-gray-500">قيد التنفيذ</div>
            </div>
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-gray-600">{{ stats.pending }}</div>
                <div class="text-xs text-gray-500">معلقة</div>
            </div>
        </div>

        <div class="mt-4 rounded-lg bg-white p-4 shadow-sm">
            <div class="flex items-center justify-between text-sm text-gray-600">
                <span>التقدم العام</span>
                <span>{{ stats.completed }} من {{ stats.total }} مكتملة</span>
            </div>
            <div class="mt-2 h-4 overflow-hidden rounded-full bg-gray-100">
                <div class="h-full rounded-full bg-green-500 transition-all" :style="{ width: pct(stats.completed, stats.total) + '%' }"></div>
            </div>
        </div>

        <div v-if="tasks.length === 0" class="mt-4 rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
            لم تُخصَّص لك أي مهام بعد.
        </div>

        <div v-for="task in tasks" :key="task.task_id" class="mt-4 overflow-hidden rounded-lg bg-white shadow-sm">
            <div class="border-b border-gray-100 p-4">
                <div class="flex flex-wrap items-center justify-between gap-2">
                    <h3 class="font-medium text-gray-900">
                        {{ task.title }}
                        <span v-if="task.case_sheet" class="mr-1 rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ task.case_sheet }}</span>
                    </h3>
                    <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ task.instances.length }} حالة</span>
                </div>
                <div class="mt-1 flex flex-wrap gap-x-4 text-xs text-gray-500">
                    <span>القسم: {{ task.department ?? '—' }}</span>
                    <span>المطلوب: {{ task.required_count }}</span>
                    <span class="font-medium text-amber-700">المتبقي: {{ task.remaining }}</span>
                </div>
                <div class="mt-2 h-2 overflow-hidden rounded-full bg-gray-100">
                    <div class="h-full rounded-full bg-green-500" :style="{ width: pct(task.completed, task.instances.length) + '%' }"></div>
                </div>
            </div>

            <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                    <tr>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">الحالة</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">تاريخ التخصيص</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">تاريخ الإكمال</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">الدرجة</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">الملاحظات</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-200 bg-white">
                    <tr v-for="i in task.instances" :key="i.id">
                        <td class="whitespace-nowrap px-4 py-2 text-sm">
                            <span class="rounded-full px-2 py-0.5 text-xs" :class="statusClass(i.status)">{{ statusLabel(i.status) }}</span>
                        </td>
                        <td class="whitespace-nowrap px-4 py-2 text-sm text-gray-500">{{ fmt(i.assigned_date) }}</td>
                        <td class="whitespace-nowrap px-4 py-2 text-sm text-gray-500">{{ fmt(i.completion_date) }}</td>
                        <td class="whitespace-nowrap px-4 py-2 text-sm text-gray-500">{{ i.grade ?? '—' }}</td>
                        <td class="px-4 py-2 text-sm text-gray-500">{{ i.notes ?? '—' }}</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </DoctorLayout>
</template>
