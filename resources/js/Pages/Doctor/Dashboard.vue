<script setup>
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import { Head, Link } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';

const { t } = useI18n();
defineProps({
    doctorInfo: Object,
    hasStartedTasks: Boolean,
    stats: Object,
    tasks: Array,
});
</script>

<template>
    <Head :title="t('doctorDashboard.title')" />

    <DoctorLayout>
        <!-- معلومات الطبيب والمجموعة -->
        <div class="rounded-lg bg-white p-4 shadow-sm">
            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                <div>
                    <p class="font-semibold text-green-700"><Icon name="school" class="ml-1" />{{ t('doctorDashboard.educationType') }}: {{ doctorInfo.education_type ?? '—' }}</p>
                    <p class="mt-1 font-medium text-indigo-700"><Icon name="layers" class="ml-1" />{{ t('doctorDashboard.stage') }}: {{ doctorInfo.stage ?? '—' }}</p>
                </div>
                <div v-if="$page.props.groupsEnabled !== false">
                    <template v-if="doctorInfo.group">
                        <p class="font-medium text-sky-700"><Icon name="groups" class="ml-1" />{{ t('doctorDashboard.group') }}: {{ doctorInfo.group }}</p>
                        <div class="mt-2 flex flex-wrap gap-1">
                            <span v-for="(s, i) in doctorInfo.slots" :key="i" class="rounded-full bg-sky-100 px-2 py-1 text-xs text-sky-800">
                                <Icon name="schedule" class="ml-1" />{{ t('doctorDashboard.daySlot', { day: s.day, start: s.start, end: s.end }) }}
                            </span>
                        </div>
                    </template>
                    <p v-else class="text-gray-500"><Icon name="info" class="ml-1" />{{ t('doctorDashboard.noGroup') }}</p>
                </div>
            </div>
        </div>

        <!-- إشعار المهام المخفية -->
        <div v-if="hasStartedTasks" class="mt-4 rounded-md bg-amber-50 p-4 text-sm text-amber-800">
            <strong>{{ t('doctorDashboard.note') }}:</strong> {{ t('doctorDashboard.hiddenTasksNotice') }}
            <div class="mt-1 text-xs">{{ t('doctorDashboard.hiddenTasksNoticeDetail') }}</div>
        </div>

        <!-- إحصائيات المهام -->
        <div class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 p-4 text-center text-white shadow-sm">
                <div class="text-2xl"><Icon name="assignment" class="ml-1" /></div>
                <div class="mt-1 text-2xl font-bold">{{ stats.tasks }}</div>
                <div class="text-xs opacity-90">{{ t('doctorDashboard.tasksShown') }}</div>
            </div>
            <div class="rounded-lg bg-gradient-to-br from-green-500 to-emerald-600 p-4 text-center text-white shadow-sm">
                <div class="text-2xl"><Icon name="check_circle" class="ml-1" /></div>
                <div class="mt-1 text-2xl font-bold">{{ stats.completed }}</div>
                <div class="text-xs opacity-90">{{ t('doctorDashboard.completedCases') }}</div>
            </div>
            <div class="rounded-lg bg-gradient-to-br from-amber-500 to-orange-600 p-4 text-center text-white shadow-sm">
                <div class="text-2xl"><Icon name="schedule" class="ml-1" /></div>
                <div class="mt-1 text-2xl font-bold">{{ stats.assigned }}</div>
                <div class="text-xs opacity-90">{{ t('doctorDashboard.assignedCases') }}</div>
            </div>
            <div class="rounded-lg bg-gradient-to-br from-slate-500 to-slate-700 p-4 text-center text-white shadow-sm">
                <div class="text-2xl"><Icon name="medical_services" class="ml-1" /></div>
                <div class="mt-1 text-2xl font-bold">{{ stats.pending }}</div>
                <div class="text-xs opacity-90">{{ t('doctorDashboard.pendingCases') }}</div>
            </div>
        </div>

        <!-- شريط التقدم -->
        <div v-if="stats.tasks > 0" class="mt-4 rounded-lg bg-white p-4 shadow-sm">
            <h3 class="text-sm font-semibold text-gray-800"><Icon name="trending_up" class="ml-1" />{{ t('doctorDashboard.taskProgress') }}</h3>
            <div class="mt-2 h-5 overflow-hidden rounded-full bg-gray-100">
                <div class="flex h-full items-center justify-center rounded-full bg-green-500 text-xs font-medium text-white transition-all" :style="{ width: stats.progress + '%' }">
                    {{ stats.progress }}%
                </div>
            </div>
            <p class="mt-2 text-xs text-gray-500">
                {{ t('doctorDashboard.progressSummary', { completed: stats.completed, total: stats.total_instances, assigned: stats.assigned, pending: stats.pending }) }}
            </p>
        </div>

        <!-- Quick access -->
        <div class="mt-4 grid grid-cols-1 gap-2 md:grid-cols-2">
            <Link :href="route('doctor.required-tasks')" class="rounded-lg bg-indigo-600 px-4 py-3 text-center text-sm font-medium text-white hover:bg-indigo-700">
                <Icon name="assignment" class="ml-1" />{{ t('doctorLayout.requiredTasks') }}
            </Link>
            <Link :href="route('doctor.progress')" class="rounded-lg bg-sky-600 px-4 py-3 text-center text-sm font-medium text-white hover:bg-sky-700">
                <Icon name="trending_up" class="ml-1" />{{ t('doctorDashboard.viewDetailedProgress') }}
            </Link>
        </div>

        <!-- عرض المهام -->
        <h3 class="mt-6 text-lg font-semibold text-gray-800">
            <Icon name="checklist" class="ml-1" />{{ t('doctorDashboard.requiredTasksInStage', { stage: doctorInfo.stage ?? '—' }) }}
        </h3>

        <div v-if="tasks.length === 0" class="mt-3 rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
            {{ t('doctorDashboard.noTasksAvailable') }}
        </div>

        <div v-else class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-2">
            <div v-for="task in tasks" :key="task.id" class="rounded-lg bg-white p-4 shadow-sm">
                <div class="flex items-start justify-between gap-2">
                    <div>
                        <h4 class="font-semibold text-indigo-700">{{ task.title }}</h4>
                        <p class="mt-0.5 text-xs text-gray-500">{{ t('doctorDashboard.department') }}: {{ task.department ?? '—' }}</p>
                    </div>
                    <span v-if="task.case_sheet" class="shrink-0 rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">
                        {{ task.case_sheet }}
                    </span>
                </div>

                <div class="mt-3 flex flex-wrap gap-1 text-xs">
                    <span class="rounded-full bg-sky-100 px-2 py-0.5 text-sky-800">{{ t('doctorDashboard.required') }}: {{ task.required_count }}</span>
                    <span class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">{{ t('doctorDashboard.completed') }}: {{ task.completed }}</span>
                    <span class="rounded-full bg-amber-100 px-2 py-0.5 text-amber-800">{{ t('doctorDashboard.assigned') }}: {{ task.assigned }}</span>
                    <span class="rounded-full bg-gray-200 px-2 py-0.5 text-gray-700">{{ t('doctorDashboard.pending') }}: {{ task.pending }}</span>
                    <span v-if="task.grade" class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">{{ t('doctorDashboard.grade') }}: {{ task.grade }}</span>
                </div>

                <p v-if="task.notes" class="mt-2 text-xs text-gray-500">{{ task.notes }}</p>
            </div>
        </div>
    </DoctorLayout>
</template>
