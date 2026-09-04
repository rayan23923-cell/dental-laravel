<script setup>
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import { Head } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';

const { t } = useI18n();
defineProps({
    stats: Object,
    tasks: Array,
});

const statusLabel = (s) => ({ completed: t('dashboard.completed'), assigned: t('dashboard.inProgress'), pending: t('dashboard.pending') }[s] ?? s);
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
    <Head :title="t('doctorProgress.title')" />

    <DoctorLayout>
        <h2 class="text-lg font-semibold text-gray-800"><Icon name="trending_up" class="ml-1" />{{ t('doctorProgress.title') }}</h2>

        <div class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-gray-900">{{ stats.total }}</div>
                <div class="text-xs text-gray-500">{{ t('doctorProgress.totalCases') }}</div>
            </div>
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-green-700">{{ stats.completed }}</div>
                <div class="text-xs text-gray-500">{{ t('dashboard.completed') }}</div>
            </div>
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-amber-700">{{ stats.assigned }}</div>
                <div class="text-xs text-gray-500">{{ t('dashboard.inProgress') }}</div>
            </div>
            <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                <div class="text-2xl font-bold text-gray-600">{{ stats.pending }}</div>
                <div class="text-xs text-gray-500">{{ t('dashboard.pending') }}</div>
            </div>
        </div>

        <div class="mt-4 rounded-lg bg-white p-4 shadow-sm">
            <div class="flex items-center justify-between text-sm text-gray-600">
                <span>{{ t('doctorProgress.overallProgress') }}</span>
                <span>{{ t('doctorProgress.completedOfTotal', { completed: stats.completed, total: stats.total }) }}</span>
            </div>
            <div class="mt-2 h-4 overflow-hidden rounded-full bg-gray-100">
                <div class="h-full rounded-full bg-green-500 transition-all" :style="{ width: pct(stats.completed, stats.total) + '%' }"></div>
            </div>
        </div>

        <div v-if="tasks.length === 0" class="mt-4 rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
            {{ t('doctorProgress.noTasksAssignedYet') }}
        </div>

        <div v-for="task in tasks" :key="task.task_id" class="mt-4 overflow-hidden rounded-lg bg-white shadow-sm">
            <div class="border-b border-gray-100 p-4">
                <div class="flex flex-wrap items-center justify-between gap-2">
                    <h3 class="font-medium text-gray-900">
                        {{ task.title }}
                        <span v-if="task.case_sheet" class="mr-1 rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ task.case_sheet }}</span>
                    </h3>
                    <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ t('doctorProgress.casesCount', { n: task.instances.length }) }}</span>
                </div>
                <div class="mt-1 flex flex-wrap gap-x-4 text-xs text-gray-500">
                    <span>{{ t('doctorDashboard.department') }}: {{ task.department ?? '—' }}</span>
                    <span>{{ t('dashboard.requiredLabel') }}: {{ task.required_count }}</span>
                    <span class="font-medium text-amber-700">{{ t('dashboard.remainingCol') }}: {{ task.remaining }}</span>
                </div>
                <div class="mt-2 h-2 overflow-hidden rounded-full bg-gray-100">
                    <div class="h-full rounded-full bg-green-500" :style="{ width: pct(task.completed, task.instances.length) + '%' }"></div>
                </div>
            </div>

            <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                    <tr>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">{{ t('doctorProgress.statusCol') }}</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">{{ t('doctorProgress.assignedDateCol') }}</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">{{ t('doctorProgress.completionDateCol') }}</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">{{ t('doctorDashboard.grade') }}</th>
                        <th class="px-4 py-2 text-right text-xs font-medium uppercase text-gray-500">{{ t('doctorProgress.notesCol') }}</th>
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
