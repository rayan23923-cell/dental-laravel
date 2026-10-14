<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import ChatPager from '@/Components/ChatList/ChatPager.vue';
import { toneFor } from '@/Components/ChatList/tones';
import { Head, router, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import StructureTabs from '@/Components/StructureTabs.vue';

const { t } = useI18n();
const props = defineProps({
    tasks: { type: Object, default: null },
    educationTypes: { type: Array, default: () => [] },
    stages: { type: Array, default: () => [] },
    departments: { type: Array, default: () => [] },
    filters: { type: Object, default: () => ({}) },
    currentSession: { type: Object, default: null },
    allSessions: { type: Boolean, default: false },
});

const page = usePage();

// Tasks belong to the academic year they were created in, so the list is
// scoped to the session being worked in; this lifts that to review past years.
const allSessions = ref(props.allSessions);

// Mirrors dental_clinics2/admin/manage_tasks.php exactly: three cascading
// selects (education type -> stage -> department), and the task list is
// hidden entirely — not just narrowed — until a stage AND a department are
// both chosen. Education type has no effect on the server (`tasks` has no
// education_type_id column, same as the original), so it's never sent as a
// query param — it only filters which stages this dropdown offers next.
const educationType = ref('');
const stage = ref(props.filters.stage_id ?? '');
const department = ref(props.filters.department_id ?? '');

// Pre-select the education type implied by the already-chosen stage (e.g.
// after a page reload/back-navigation) so the cascade doesn't visually reset.
if (stage.value) {
    const matchedStage = props.stages.find((s) => s.id === Number(stage.value));
    if (matchedStage?.education_type_id) educationType.value = matchedStage.education_type_id;
}

const filteredStages = computed(() =>
    educationType.value ? props.stages.filter((s) => s.education_type_id === Number(educationType.value)) : props.stages
);

const filteredDepartments = computed(() =>
    stage.value ? props.departments.filter((d) => d.stage_id === Number(stage.value)) : props.departments
);

// Carries the active stage/education-type filter over to the create form
// (see Tasks/Create.vue) — only when a stage is actually selected here, so
// an unfiltered "Add Task" click still opens the form empty, exactly as
// before this existed.
const createTaskHref = computed(() =>
    stage.value
        ? route('tasks.create', { stage_id: stage.value, education_type_id: educationType.value || undefined })
        : route('tasks.create')
);

const applyFilters = () => {
    router.get(
        route('tasks.index'),
        {
            ...(stage.value ? { stage_id: stage.value } : {}),
            ...(department.value ? { department_id: department.value } : {}),
            ...(allSessions.value ? { all_sessions: 1 } : {}),
        },
        { preserveState: true, replace: true }
    );
};

const onEducationTypeChange = () => {
    stage.value = '';
    department.value = '';
    applyFilters();
};

const onStageChange = () => {
    department.value = '';
    applyFilters();
};

const toggleAllSessions = () => applyFilters();

const destroy = (task) => {
    if (confirm(t('tasksAdmin.deleteConfirm', { title: task.title }))) {
        router.delete(route('tasks.destroy', task.id));
    }
};
</script>

<template>
    <Head :title="t('tasksAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('tasksAdmin.title') }}</h2>
                <ChatAddButton :label="t('tasksAdmin.addTask')" :href="createTaskHref" />
            </div>
        </template>

        <!-- Chat-list style (2026-10-13, by request): the table became
             chat-list rows (title, chips, icon actions). -->
        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <StructureTabs />

                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700 whitespace-pre-line">
                    {{ page.props.flash.error }}
                </div>

                <div v-if="currentSession" class="flex flex-wrap items-center justify-between gap-2 rounded-2xl bg-indigo-50 px-4 py-2.5 text-sm text-indigo-900">
                    <span class="flex items-center gap-1.5">
                        <Icon name="calendar_month" size="text-[18px]" />
                        <template v-if="allSessions">{{ t('tasksAdmin.viewingAllSessionsPrefix') }} <strong>{{ t('doctorsAdmin.allAcademicSessions') }}</strong></template>
                        <template v-else>{{ t('tasksAdmin.sessionTasksPrefix') }} <strong>{{ currentSession.name }}</strong></template>
                    </span>
                    <label class="flex cursor-pointer items-center gap-2">
                        <input type="checkbox" v-model="allSessions" @change="toggleAllSessions" class="rounded border-gray-300 text-indigo-600" />
                        {{ t('doctorsAdmin.showAllSessions') }}
                    </label>
                </div>

                <!-- Filters — mirrors admin/manage_tasks.php: education type
                     narrows the stage list, stage narrows the department
                     list, and the task list below only appears once a
                     stage AND a department are both chosen. -->
                <div class="flex flex-wrap items-center gap-2">
                    <select v-model="educationType" @change="onEducationTypeChange" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('tasksAdmin.educationTypeFilterPlaceholder') }}</option>
                        <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                    </select>
                    <select v-model="stage" @change="onStageChange" :disabled="!educationType" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100 disabled:text-gray-400">
                        <option value="">{{ t('doctorsAdmin.stageCol') }}</option>
                        <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>
                    <select v-model="department" @change="applyFilters" :disabled="!stage" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100 disabled:text-gray-400">
                        <option value="">{{ t('tasksAdmin.departmentFilterPlaceholder') }}</option>
                        <option v-for="d in filteredDepartments" :key="d.id" :value="d.id">{{ d.name }}</option>
                    </select>
                </div>

                <ChatListCard v-if="!tasks" empty :empty-text="t('tasksAdmin.emptyPrompt')" empty-icon="filter_list" />

                <ChatListCard v-else :empty="tasks.data.length === 0" :empty-text="t('tasksAdmin.emptyList')" empty-icon="assignment">
                    <ChatListRow
                        v-for="task in tasks.data"
                        :key="task.id"
                        :title="task.title"
                        icon="assignment"
                        :tone="toneFor(task.id)"
                        :href="route('tasks.show', task.id)"
                    >
                        <template #meta>
                            <ChatChip :icon="task.is_required ? 'star' : 'radio_button_unchecked'" :tone="task.is_required ? 'indigo' : 'gray'">
                                {{ task.is_required ? t('tasksAdmin.required') : t('tasksAdmin.optional') }}
                            </ChatChip>
                            <ChatChip v-if="task.department" icon="apartment" tone="teal">{{ task.department.name }}</ChatChip>
                            <ChatChip v-if="task.stage" icon="stairs" tone="sky">{{ task.stage.name }}</ChatChip>
                            <ChatChip v-if="task.case_sheet_type" icon="description" tone="amber">{{ task.case_sheet_type.name_en }}</ChatChip>
                            <ChatChip icon="group" :title="t('tasksAdmin.assignmentsCol')">{{ task.instances_count }}</ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction icon="visibility" :label="t('common.view')" :href="route('tasks.show', task.id)" />
                            <ChatAction icon="edit" :label="t('common.edit')" :href="route('tasks.edit', task.id)" />
                            <ChatAction icon="delete" :label="t('common.delete')" danger @click="destroy(task)" />
                        </template>
                    </ChatListRow>
                    <template #footer>
                        <ChatPager :links="tasks.links" />
                    </template>
                </ChatListCard>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
