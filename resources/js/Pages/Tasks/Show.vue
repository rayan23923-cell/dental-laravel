<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { toneFor } from '@/Components/ChatList/tones';
import { Head, router, usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

// Styled like the other chat-list pages (2026-10-19, by request): the
// task's details as chips, its doctors as rows with icon actions.
const { t } = useI18n();
defineProps({
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

const statusTone = (status) => ({ pending: 'gray', assigned: 'amber', completed: 'emerald' }[status] ?? 'gray');
const statusIcon = (status) => ({ pending: 'schedule', assigned: 'pending_actions', completed: 'check_circle' }[status] ?? 'schedule');
const statusLabel = (status) => (['pending', 'assigned', 'completed'].includes(status) ? t(`doctorDashboard.${status}`) : status);
</script>

<template>
    <Head :title="task.title" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ task.title }}</h2>
                <ChatAddButton :label="t('common.edit')" icon="edit" secondary :href="route('tasks.edit', task.id)" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div class="flex items-start gap-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-purple-500 text-white">
                        <Icon name="assignment" />
                    </span>
                    <div class="min-w-0 flex-1">
                        <div class="font-semibold text-gray-900">{{ task.title }}</div>
                        <div class="mt-2 flex flex-wrap items-center gap-1.5">
                            <ChatChip v-if="task.department" icon="apartment" tone="teal">{{ task.department.name }}</ChatChip>
                            <ChatChip v-if="task.stage" icon="stairs" tone="sky">{{ task.stage.name }}</ChatChip>
                            <ChatChip v-if="task.case_sheet_type" icon="description" tone="amber">{{ task.case_sheet_type.name_en }}</ChatChip>
                            <ChatChip icon="tag" tone="indigo">{{ t('tasksAdmin.requiredCountLabel') }}: {{ task.required_count }}</ChatChip>
                        </div>
                        <p v-if="task.notes" class="mt-3 text-sm text-gray-600">{{ task.notes }}</p>
                    </div>
                </div>

                <h3 class="px-1 text-sm font-semibold text-gray-700">{{ t('patients.doctorCol') }} ({{ task.instances.length }})</h3>

                <ChatListCard :empty="task.instances.length === 0" :empty-text="t('tasksAdmin.noDoctorsAssignedYet')" empty-icon="group">
                    <ChatListRow
                        v-for="instance in task.instances"
                        :key="instance.id"
                        :title="instance.doctor?.name ?? '—'"
                        icon="person"
                        :tone="toneFor(instance.doctor_id ?? instance.id)"
                    >
                        <template #meta>
                            <ChatChip :icon="statusIcon(instance.status)" :tone="statusTone(instance.status)">{{ statusLabel(instance.status) }}</ChatChip>
                            <ChatChip v-if="instance.assigned_date" icon="calendar_month" :title="t('doctorsAdmin.assignedDateCol')">
                                {{ new Date(instance.assigned_date).toLocaleDateString() }}
                            </ChatChip>
                            <ChatChip v-if="instance.grade !== null && instance.grade !== undefined" icon="grade" tone="violet">
                                {{ t('tasksAdmin.gradeColShort') }}: {{ instance.grade }}
                            </ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction icon="qr_code_2" label="QR" :href="route('task-instances.qr', instance.id)" external />
                            <ChatAction
                                v-if="instance.status !== 'completed'"
                                icon="task_alt"
                                :label="t('doctorsAdmin.markComplete')"
                                @click="updateStatus(instance, 'completed')"
                            />
                            <ChatAction icon="delete" :label="t('tasksAdmin.removeAssignmentButton')" danger @click="removeInstance(instance)" />
                        </template>
                    </ChatListRow>
                </ChatListCard>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
