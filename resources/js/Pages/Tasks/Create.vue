<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    departments: Array,
    caseSheetTypes: Array,
    stages: Array,
    educationTypes: { type: Array, default: () => [] },
    academicSessions: { type: Array, default: () => [] },
    // Carried over from Tasks/Index.vue's "Add Task" link when a filter was
    // active there — null when it wasn't, in which case these fields start
    // empty and are picked manually, same as before this existed.
    initialStageId: { type: Number, default: null },
    initialEducationTypeId: { type: Number, default: null },
});

const form = useForm({
    title: '',
    department_id: '',
    case_sheet_type_id: '',
    stage_id: props.initialStageId ?? '',
    required_count: 1,
    notes: '',
    grade: '',
    // Left blank so the controller stamps the session being worked in, the
    // same default as the original's add_task.php.
    academic_session_id: '',
    // Most tasks are mandatory today (there being no other option before
    // this field existed), so new tasks default to أساسية.
    is_required: true,
});

// Education type -> stage cascade (UI-only, mirrors Tasks/Index.vue's own
// cascade exactly — `tasks` has no education_type_id column, so this never
// reaches the backend, it only narrows which stages are selectable below).
const educationType = ref(props.initialEducationTypeId ?? '');

const filteredStages = computed(() =>
    educationType.value ? props.stages.filter((s) => s.education_type_id === Number(educationType.value)) : props.stages
);

let educationTypeInitialized = false;
watch(educationType, () => {
    if (!educationTypeInitialized) {
        educationTypeInitialized = true;
        return;
    }
    if (!filteredStages.value.some((s) => s.id === form.stage_id)) {
        form.stage_id = '';
    }
});

// Mirrors the original app's stage -> department cascade (admin/ajax/get_departments_by_stage.php,
// wired in admin/manage_tasks.php): once a stage is picked, only departments belonging to that
// stage are selectable. departments.stage_id is nullable, so departments with no stage stay
// available regardless of the selected stage (matches the schema, not a restriction to invent).
// Only the chosen stage's own departments (2026-10-13, by request): a task
// must belong to a department of its stage, which TaskController enforces.
const stageDepartments = (stageId) => props.departments.filter((d) => Number(d.stage_id) === stageId);
const filteredDepartments = computed(() =>
    form.stage_id
        ? stageDepartments(Number(form.stage_id))
        : []
);

let initialized = false;
watch(
    () => form.stage_id,
    () => {
        if (!initialized) {
            initialized = true;
            return;
        }
        if (!filteredDepartments.value.some((d) => d.id === form.department_id)) {
            form.department_id = '';
        }
    }
);

const submit = () => {
    form.post(route('tasks.store'));
};
</script>

<template>
    <Head :title="t('tasksAdmin.addTask')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('tasksAdmin.addTask') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="title" :value="t('tasksAdmin.titleLabel')" />
                            <TextInput id="title" v-model="form.title" type="text" class="mt-1 block w-full" required autofocus />
                            <InputError class="mt-2" :message="form.errors.title" />
                        </div>

                        <div>
                            <InputLabel for="education_type_id" :value="t('tasksAdmin.educationTypeFilterPlaceholder')" />
                            <select id="education_type_id" v-model="educationType" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="" disabled>{{ t('doctorsAdmin.selectEducationType') }}</option>
                                <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                            </select>
                        </div>

                        <div>
                            <InputLabel for="stage_id" :value="t('doctorsAdmin.stageCol')" />
                            <select id="stage_id" v-model="form.stage_id" :disabled="!educationType" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100" required>
                                <option value="" disabled>{{ educationType ? t('tasksAdmin.selectStage') : t('doctorsAdmin.selectEducationTypeFirst') }}</option>
                                <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.stage_id" />
                        </div>

                        <div>
                            <InputLabel for="department_id" :value="t('doctorsAdmin.departmentLabel')" />
                            <select id="department_id" v-model="form.department_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" :disabled="!form.stage_id" required>
                                <option value="" disabled>{{ form.stage_id ? t('tasksAdmin.selectDepartment') : t('tasksAdmin.selectStageFirst') }}</option>
                                <option v-for="d in filteredDepartments" :key="d.id" :value="d.id">{{ d.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.department_id" />
                        </div>

                        <div>
                            <InputLabel for="case_sheet_type_id" :value="t('tasksAdmin.caseSheetTypeLabel')" />
                            <select id="case_sheet_type_id" v-model="form.case_sheet_type_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>{{ t('tasksAdmin.selectCaseSheetType') }}</option>
                                <option v-for="c in caseSheetTypes" :key="c.id" :value="c.id">{{ c.name_en }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.case_sheet_type_id" />
                        </div>

                        <div>
                            <InputLabel for="required_count" :value="t('tasksAdmin.requiredCountLabel')" />
                            <TextInput id="required_count" v-model="form.required_count" type="number" min="1" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="form.errors.required_count" />
                        </div>

                        <div class="grid grid-cols-2 gap-4">
                            <div>
                                <InputLabel for="grade" :value="t('tasksAdmin.gradeLabel')" />
                                <TextInput id="grade" v-model="form.grade" type="number" step="0.01" min="0" max="100" placeholder="0.00 - 100.00" class="mt-1 block w-full" required />
                                <InputError class="mt-2" :message="form.errors.grade" />
                            </div>
                            <div v-if="academicSessions.length">
                                <InputLabel for="academic_session_id" :value="t('doctorsAdmin.academicSessionLabel')" />
                                <select id="academic_session_id" v-model="form.academic_session_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                    <option value="">{{ t('tasksAdmin.currentTermOption') }}</option>
                                    <option v-for="s in academicSessions" :key="s.id" :value="s.id">{{ s.name }}</option>
                                </select>
                                <InputError class="mt-2" :message="form.errors.academic_session_id" />
                            </div>
                        </div>

                        <div>
                            <InputLabel :value="t('tasksAdmin.taskTypeLabel')" />
                            <div class="mt-2 flex items-center gap-6">
                                <label class="flex items-center gap-2 text-sm text-gray-700">
                                    <input type="radio" :value="true" v-model="form.is_required" class="border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                                    {{ t('tasksAdmin.required') }}
                                </label>
                                <label class="flex items-center gap-2 text-sm text-gray-700">
                                    <input type="radio" :value="false" v-model="form.is_required" class="border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                                    {{ t('tasksAdmin.optional') }}
                                </label>
                            </div>
                            <InputError class="mt-2" :message="form.errors.is_required" />
                        </div>

                        <div>
                            <InputLabel for="notes" :value="t('tasksAdmin.notesLabel')" />
                            <textarea id="notes" v-model="form.notes" rows="3" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                            <InputError class="mt-2" :message="form.errors.notes" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">{{ t('tasksAdmin.saveTask') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
