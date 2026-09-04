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
    task: Object,
    departments: Array,
    caseSheetTypes: Array,
    stages: Array,
    educationTypes: { type: Array, default: () => [] },
    academicSessions: { type: Array, default: () => [] },
});

const form = useForm({
    title: props.task.title,
    department_id: props.task.department_id,
    case_sheet_type_id: props.task.case_sheet_type_id,
    stage_id: props.task.stage_id,
    required_per_doctor: props.task.required_per_doctor,
    required_count: props.task.required_count,
    notes: props.task.notes ?? '',
    grade: props.task.grade ?? '',
    academic_session_id: props.task.academic_session_id ?? '',
    is_required: props.task.is_required,
});

// A task doesn't store its education type (see Tasks/Create.vue) — derive
// the one implied by its current stage, the same trick Tasks/Index.vue uses
// when a stage filter survives a reload, so the cascade below doesn't open
// looking reset.
const matchedStage = props.stages.find((s) => s.id === props.task.stage_id);
const educationType = ref(matchedStage?.education_type_id ?? '');

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

// See Tasks/Create.vue for why this filters (mirrors the original app's
// stage -> department cascade).
const filteredDepartments = computed(() =>
    form.stage_id
        ? props.departments.filter((d) => d.stage_id === form.stage_id || d.stage_id === null)
        : props.departments
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
    form.put(route('tasks.update', props.task.id));
};
</script>

<template>
    <Head :title="t('tasksAdmin.editTaskTitle')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('tasksAdmin.editTaskTitle') }}</h2>
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
                                <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.stage_id" />
                        </div>

                        <div>
                            <InputLabel for="department_id" :value="t('doctorsAdmin.departmentLabel')" />
                            <select id="department_id" v-model="form.department_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option v-for="d in filteredDepartments" :key="d.id" :value="d.id">{{ d.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.department_id" />
                        </div>

                        <div>
                            <InputLabel for="case_sheet_type_id" :value="t('tasksAdmin.caseSheetTypeLabel')" />
                            <select id="case_sheet_type_id" v-model="form.case_sheet_type_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option v-for="c in caseSheetTypes" :key="c.id" :value="c.id">{{ c.name_en }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.case_sheet_type_id" />
                        </div>

                        <div class="grid grid-cols-2 gap-4">
                            <div>
                                <InputLabel for="required_per_doctor" :value="t('tasksAdmin.requiredPerDoctorLabel')" />
                                <TextInput id="required_per_doctor" v-model="form.required_per_doctor" type="number" min="0" class="mt-1 block w-full" required />
                                <InputError class="mt-2" :message="form.errors.required_per_doctor" />
                            </div>
                            <div>
                                <InputLabel for="required_count" :value="t('tasksAdmin.requiredCountLabel')" />
                                <TextInput id="required_count" v-model="form.required_count" type="number" min="1" class="mt-1 block w-full" required />
                                <InputError class="mt-2" :message="form.errors.required_count" />
                            </div>
                        </div>

                        <div class="grid grid-cols-2 gap-4">
                            <div>
                                <InputLabel for="grade" :value="t('tasksAdmin.gradeLabel')" />
                                <TextInput id="grade" v-model="form.grade" type="number" step="0.01" min="0" max="100" placeholder="0.00 - 100.00" class="mt-1 block w-full" />
                                <InputError class="mt-2" :message="form.errors.grade" />
                            </div>
                            <div v-if="academicSessions.length">
                                <InputLabel for="academic_session_id" :value="t('doctorsAdmin.academicSessionLabel')" />
                                <select id="academic_session_id" v-model="form.academic_session_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                    <option value="">{{ t('doctorsAdmin.unlinkedSessionOption') }}</option>
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
                            <textarea id="notes" v-model="form.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                            <InputError class="mt-2" :message="form.errors.notes" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">{{ t('tasksAdmin.updateTask') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
