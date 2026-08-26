<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';

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
    if (confirm(`Delete task "${task.title}"?`)) {
        router.delete(route('tasks.destroy', task.id));
    }
};
</script>

<template>
    <Head title="Tasks" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">
                    Tasks
                </h2>
                <Link :href="createTaskHref">
                    <PrimaryButton>Add Task</PrimaryButton>
                </Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-7xl space-y-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div v-if="currentSession" class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-indigo-200 bg-indigo-50 p-3">
                    <span class="text-sm text-indigo-900">
                        <Icon name="calendar_month" class="ml-1" />
                        <template v-if="allSessions">عرض مهام <strong>جميع الأعوام الدراسية</strong></template>
                        <template v-else>مهام العام الدراسي <strong>{{ currentSession.name }}</strong></template>
                    </span>
                    <label class="flex cursor-pointer items-center gap-2 text-sm text-indigo-900">
                        <input type="checkbox" v-model="allSessions" @change="toggleAllSessions" class="rounded border-gray-300 text-indigo-600" />
                        عرض جميع الأعوام الدراسية
                    </label>
                </div>

                <!-- Filters — mirrors admin/manage_tasks.php: education type
                     narrows the stage list, stage narrows the department
                     list, and the task table below only appears once a
                     stage AND a department are both chosen. -->
                <div class="grid grid-cols-1 gap-3 rounded-lg bg-white p-4 shadow-sm md:grid-cols-3">
                    <select v-model="educationType" @change="onEducationTypeChange" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">نوع الدراسة</option>
                        <option v-for="t in educationTypes" :key="t.id" :value="t.id">{{ t.name }}</option>
                    </select>

                    <select v-model="stage" @change="onStageChange" :disabled="!educationType" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100">
                        <option value="">المرحلة</option>
                        <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>

                    <select v-model="department" @change="applyFilters" :disabled="!stage" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100">
                        <option value="">القسم</option>
                        <option v-for="d in filteredDepartments" :key="d.id" :value="d.id">{{ d.name }}</option>
                    </select>
                </div>

                <div v-if="!tasks" class="rounded-lg bg-white p-12 text-center text-sm text-gray-500 shadow-sm">
                    اختر نوع الدراسة والمرحلة والقسم لعرض المهام.
                </div>

                <div v-else class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Title</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Department</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Case Sheet</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Stage</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">النوع</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Assignments</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="task in tasks.data" :key="task.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">
                                    <Link :href="route('tasks.show', task.id)" class="hover:underline">{{ task.title }}</Link>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ task.department?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ task.case_sheet_type?.name_en ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ task.stage?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <span
                                        class="rounded-full px-2 py-0.5 text-xs font-medium"
                                        :class="task.is_required ? 'bg-indigo-50 text-indigo-700' : 'bg-gray-100 text-gray-600'"
                                    >
                                        {{ task.is_required ? 'أساسية' : 'اختيارية' }}
                                    </span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ task.instances_count }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <Link :href="route('tasks.show', task.id)" class="text-gray-600 hover:text-gray-900">View</Link>
                                    <Link :href="route('tasks.edit', task.id)" class="ml-4 text-indigo-600 hover:text-indigo-900">Edit</Link>
                                    <button @click="destroy(task)" class="ml-4 text-red-600 hover:text-red-900">Delete</button>
                                </td>
                            </tr>
                            <tr v-if="tasks.data.length === 0">
                                <td colspan="7" class="px-6 py-8 text-center text-sm text-gray-500">No tasks yet.</td>
                            </tr>
                        </tbody>
                    </table>

                    <div class="flex justify-between border-t border-gray-200 p-4">
                        <Link
                            v-for="link in tasks.links"
                            :key="link.label"
                            :href="link.url ?? ''"
                            v-html="link.label"
                            class="mx-1 rounded px-3 py-1 text-sm"
                            :class="{
                                'bg-indigo-600 text-white': link.active,
                                'text-gray-400 pointer-events-none': !link.url,
                                'text-gray-700 hover:bg-gray-100': link.url && !link.active,
                            }"
                        />
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
