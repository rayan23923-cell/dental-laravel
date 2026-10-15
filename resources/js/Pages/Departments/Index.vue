<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { toneFor } from '@/Components/ChatList/tones';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import StructureTabs from '@/Components/StructureTabs.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    departments: Array,
    stages: Array,
    educationTypes: Array,
    filters: { type: Object, default: () => ({}) },
});

const page = usePage();

const search = ref(props.filters.search ?? '');
const filterStageId = ref(props.filters.stage_id ?? '');
const filterEducationTypeId = ref(props.filters.education_type_id ?? '');
const applyFilters = () => {
    router.get(
        route('departments.index'),
        {
            search: search.value || undefined,
            stage_id: filterStageId.value || undefined,
            education_type_id: filterEducationTypeId.value || undefined,
        },
        { preserveState: true, replace: true },
    );
};

// Real bug, found live: this used to iterate the full flat `stages` list
// regardless of the education type picked alongside it — same pattern as
// Doctors/Index.vue's own filteredStages, just never ported here.
const filteredStages = computed(() =>
    filterEducationTypeId.value
        ? props.stages.filter((s) => s.education_type_id === Number(filterEducationTypeId.value))
        : props.stages
);
// Reset inline (not via watch) so it's guaranteed to happen before
// applyFilters() reads filterStageId — same reasoning as Groups/Index.vue's
// existing `@change="stage = ''"` on its own education-type filter.
const onFilterEducationTypeChange = () => {
    filterStageId.value = '';
    applyFilters();
};

const createForm = useForm({ name: '', stage_id: '', education_type_id: '' });
const filteredCreateStages = computed(() =>
    createForm.education_type_id
        ? props.stages.filter((s) => s.education_type_id === Number(createForm.education_type_id))
        : props.stages
);
watch(
    () => createForm.education_type_id,
    () => {
        if (!filteredCreateStages.value.some((s) => s.id === Number(createForm.stage_id))) {
            createForm.stage_id = '';
        }
    }
);
// Chat-list style (2026-10-13, by request): adding opens a dialog from
// the round "+" in the header instead of an inline form.
const creating = ref(false);
const openCreate = () => {
    createForm.reset();
    createForm.clearErrors();
    creating.value = true;
};
const submitCreate = () => {
    createForm.post(route('departments.store'), {
        onSuccess: () => {
            createForm.reset();
            creating.value = false;
        },
    });
};

const editing = ref(null);
const editForm = useForm({ name: '', stage_id: '', education_type_id: '' });
const filteredEditStages = computed(() =>
    editForm.education_type_id
        ? props.stages.filter((s) => s.education_type_id === Number(editForm.education_type_id))
        : props.stages
);
watch(
    () => editForm.education_type_id,
    () => {
        if (!filteredEditStages.value.some((s) => s.id === Number(editForm.stage_id))) {
            editForm.stage_id = '';
        }
    }
);
const openEdit = (department) => {
    editing.value = department;
    editForm.name = department.name;
    editForm.stage_id = department.stage_id ?? '';
    editForm.education_type_id = department.education_type_id ?? '';
};
const submitEdit = () => {
    editForm.put(route('departments.update', editing.value.id), {
        onSuccess: () => (editing.value = null),
    });
};

const destroy = (department) => {
    if (confirm(t('departmentsAdmin.deleteConfirm', { name: department.name }))) {
        router.delete(route('departments.destroy', department.id));
    }
};
</script>

<template>
    <Head :title="t('structureTabs.departments')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('structureTabs.departments') }}</h2>
                <ChatAddButton :label="t('chatList.addDepartment')" @click="openCreate" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <StructureTabs active="departments" />

                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700 whitespace-pre-line">
                    {{ page.props.flash.error }}
                </div>

                <ChatSearch v-model="search" :placeholder="t('taxonomyAdmin.searchPlaceholder')" @submit="applyFilters" />

                <div class="flex flex-wrap gap-2">
                    <select
                        v-model="filterEducationTypeId"
                        @change="onFilterEducationTypeChange"
                        :aria-label="t('taxonomyAdmin.educationTypeLabel')"
                        class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">{{ t('taxonomyAdmin.allEducationTypes') }}</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <select
                        v-model="filterStageId"
                        @change="applyFilters"
                        :aria-label="t('doctorsAdmin.stageCol')"
                        class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">{{ t('taxonomyAdmin.allStages') }}</option>
                        <option v-for="stage in filteredStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                    </select>
                </div>

                <ChatListCard
                    :empty="departments.length === 0"
                    :empty-text="search || filterStageId || filterEducationTypeId ? t('taxonomyAdmin.noMatchingResults') : t('departmentsAdmin.emptyList')"
                    empty-icon="apartment"
                >
                    <ChatListRow v-for="department in departments" :key="department.id" :title="department.name" icon="apartment" :tone="toneFor(department.id)">
                        <template #meta>
                            <ChatChip v-if="department.stage?.name" icon="stairs" tone="indigo">{{ department.stage.name }}</ChatChip>
                            <ChatChip v-if="department.education_type?.name" icon="school" tone="sky">{{ department.education_type.name }}</ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction icon="edit" :label="t('common.edit')" @click="openEdit(department)" />
                            <ChatAction icon="delete" :label="t('common.delete')" danger @click="destroy(department)" />
                        </template>
                    </ChatListRow>
                </ChatListCard>
            </div>
        </div>

        <Modal :show="creating" @close="creating = false">
            <form @submit.prevent="submitCreate" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('chatList.addDepartment') }}</h2>
                <div class="mt-4">
                    <InputLabel for="create-name" :value="t('profile.name')" />
                    <TextInput id="create-name" v-model="createForm.name" type="text" :placeholder="t('departmentsAdmin.newNamePlaceholder')" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="createForm.errors.name" />
                </div>
                <div class="mt-4">
                    <InputLabel for="create-education-type" :value="t('taxonomyAdmin.educationTypeLabel')" />
                    <select id="create-education-type" v-model="createForm.education_type_id" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="" disabled>{{ t('departmentsAdmin.chooseEducationType') }}</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="createForm.errors.education_type_id" />
                </div>
                <div class="mt-4">
                    <InputLabel for="create-stage" :value="t('doctorsAdmin.stageCol')" />
                    <select id="create-stage" v-model="createForm.stage_id" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="" disabled>{{ t('departmentsAdmin.chooseStage') }}</option>
                        <option v-for="stage in filteredCreateStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="createForm.errors.stage_id" />
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="creating = false">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="createForm.processing">{{ t('common.add') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('departmentsAdmin.editTitle') }}</h2>
                <div class="mt-4">
                    <InputLabel for="edit-name" :value="t('profile.name')" />
                    <TextInput id="edit-name" v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name" />
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-education-type" :value="t('taxonomyAdmin.educationTypeLabel')" />
                    <select id="edit-education-type" v-model="editForm.education_type_id" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="" disabled>{{ t('departmentsAdmin.chooseEducationType') }}</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="editForm.errors.education_type_id" />
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-stage" :value="t('doctorsAdmin.stageCol')" />
                    <select id="edit-stage" v-model="editForm.stage_id" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="" disabled>{{ t('departmentsAdmin.chooseStage') }}</option>
                        <option v-for="stage in filteredEditStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="editForm.errors.stage_id" />
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
