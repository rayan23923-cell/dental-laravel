<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import { Head, router, usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    task: Object,
});

const page = usePage();

const updateStatus = (instance, status) => {
    router.put(route('task-instances.update', instance.id), {
        status,
        grade: instance.grade,
        notes: instance.notes,
    }, { preserveScroll: true });
};

const removeInstance = (instance) => {
    if (confirm(t('tasksAdmin.removeAssignmentConfirm'))) {
        router.delete(route('task-instances.destroy', instance.id), { preserveScroll: true });
    }
};

const statusColor = (status) => ({
    pending: 'bg-gray-100 text-gray-700',
    assigned: 'bg-yellow-100 text-yellow-800',
    completed: 'bg-green-100 text-green-800',
}[status] ?? 'bg-gray-100 text-gray-700');
</script>

<template>
    <Head :title="task.title" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ task.title }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-6 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <dl class="grid grid-cols-2 gap-4 text-sm sm:grid-cols-4">
                        <div>
                            <dt class="text-gray-500">{{ t('doctorsAdmin.departmentLabel') }}</dt>
                            <dd class="font-medium text-gray-900">{{ task.department?.name ?? '—' }}</dd>
                        </div>
                        <div>
                            <dt class="text-gray-500">{{ t('tasksAdmin.caseSheetCol') }}</dt>
                            <dd class="font-medium text-gray-900">{{ task.case_sheet_type?.name_en ?? '—' }}</dd>
                        </div>
                        <div>
                            <dt class="text-gray-500">{{ t('doctorsAdmin.stageCol') }}</dt>
                            <dd class="font-medium text-gray-900">{{ task.stage?.name ?? '—' }}</dd>
                        </div>
                        <div>
                            <dt class="text-gray-500">{{ t('tasksAdmin.requiredCountLabel') }}</dt>
                            <dd class="font-medium text-gray-900">{{ task.required_count }}</dd>
                        </div>
                    </dl>
                    <p v-if="task.notes" class="mt-4 text-sm text-gray-600">{{ task.notes }}</p>
                </div>

                <div class="overflow-x-auto bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patients.doctorCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.statusCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.assignedDateCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('tasksAdmin.gradeColShort') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.actionsCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="instance in task.instances" :key="instance.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ instance.doctor?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <span class="rounded-full px-2 py-1 text-xs font-medium" :class="statusColor(instance.status)">{{ instance.status }}</span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ instance.assigned_date ? new Date(instance.assigned_date).toLocaleDateString() : '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ instance.grade ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <a :href="route('task-instances.qr', instance.id)" target="_blank" class="text-gray-600 hover:text-gray-900">QR</a>
                                    <button
                                        v-if="instance.status !== 'completed'"
                                        @click="updateStatus(instance, 'completed')"
                                        class="ml-4 text-green-600 hover:text-green-900"
                                    >
                                        {{ t('doctorsAdmin.markComplete') }}
                                    </button>
                                    <button @click="removeInstance(instance)" class="ml-4 text-red-600 hover:text-red-900">{{ t('tasksAdmin.removeAssignmentButton') }}</button>
                                </td>
                            </tr>
                            <tr v-if="task.instances.length === 0">
                                <td colspan="5" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('tasksAdmin.noDoctorsAssignedYet') }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
