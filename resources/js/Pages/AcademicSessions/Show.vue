<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import { Head, Link } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
defineProps({
    session: Object,
    stats: Object,
    tasks: Array,
    groups: Array,
});
</script>

<template>
    <Head :title="session.name" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ session.name }}</h2>
                <Link :href="route('academic-sessions.index')" class="text-sm text-indigo-600 hover:underline">{{ t('academicSessionsAdmin.backLink') }}</Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-6xl space-y-6 sm:px-6 lg:px-8">
                <p class="text-sm text-gray-500">{{ session.start_date }} ← {{ session.end_date }}</p>

                <div class="grid grid-cols-2 gap-4 sm:grid-cols-5">
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <div class="text-2xl font-semibold text-gray-900">{{ stats.doctors }}</div>
                        <div class="text-xs text-gray-500">{{ t('academicSessionsAdmin.doctorsStat') }}</div>
                    </div>
                    <div v-if="$page.props.groupsEnabled !== false" class="rounded-lg bg-white p-4 shadow-sm">
                        <div class="text-2xl font-semibold text-gray-900">{{ stats.groups }}</div>
                        <div class="text-xs text-gray-500">{{ t('structureTabs.groups') }}</div>
                    </div>
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <div class="text-2xl font-semibold text-gray-900">{{ stats.requiredTasks }}</div>
                        <div class="text-xs text-gray-500">{{ t('academicSessionsAdmin.requiredTasksStat') }}</div>
                    </div>
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <div class="text-2xl font-semibold text-green-700">{{ stats.doneTasks }}</div>
                        <div class="text-xs text-gray-500">{{ t('academicSessionsAdmin.doneTasksStat') }}</div>
                    </div>
                    <div class="rounded-lg bg-white p-4 shadow-sm">
                        <div class="text-2xl font-semibold text-amber-700">{{ stats.remainingTasks }}</div>
                        <div class="text-xs text-gray-500">{{ t('academicSessionsAdmin.remainingTasksStat') }}</div>
                    </div>
                </div>

                <div v-if="$page.props.groupsEnabled !== false" class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <div class="border-b border-gray-200 px-6 py-4 text-sm font-medium text-gray-700">{{ t('academicSessionsAdmin.groupsInSessionHeading') }}</div>
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('profile.name') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.stageCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('academicSessionsAdmin.doctorsColShow') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="group in groups" :key="group.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ group.name }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ group.stage?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ group.doctors_count }}</td>
                            </tr>
                            <tr v-if="groups.length === 0">
                                <td colspan="3" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('academicSessionsAdmin.noGroupsInSession') }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <div class="border-b border-gray-200 px-6 py-4 text-sm font-medium text-gray-700">{{ t('academicSessionsAdmin.tasksInSessionHeading') }}</div>
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('academicSessionsAdmin.titleColShow') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.departmentLabel') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.requiredLabel') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('academicSessionsAdmin.doneColShow') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.remainingLabel') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="task in tasks" :key="task.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ task.title }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ task.department ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ task.required }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-green-700">{{ task.done }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-amber-700">{{ task.remaining }}</td>
                            </tr>
                            <tr v-if="tasks.length === 0">
                                <td colspan="5" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('academicSessionsAdmin.noTasksInSession') }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
