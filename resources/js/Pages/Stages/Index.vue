<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import DataTable from '@/Components/DataTable.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import StructureTabs from '@/Components/StructureTabs.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    stages: Array,
    educationTypes: Array,
    filters: { type: Object, default: () => ({}) },
});

const page = usePage();

const search = ref(props.filters.search ?? '');
const filterEducationTypeId = ref(props.filters.education_type_id ?? '');
const applyFilters = () => {
    router.get(
        route('stages.index'),
        { search: search.value || undefined, education_type_id: filterEducationTypeId.value || undefined },
        { preserveState: true, replace: true },
    );
};

const createForm = useForm({ name: '', education_type_id: '' });
const submitCreate = () => {
    createForm.post(route('stages.store'), {
        onSuccess: () => createForm.reset(),
    });
};

const editing = ref(null);
const editForm = useForm({ name: '', education_type_id: '' });
const openEdit = (stage) => {
    editing.value = stage;
    editForm.name = stage.name;
    editForm.education_type_id = stage.education_type_id ?? '';
};
const submitEdit = () => {
    editForm.put(route('stages.update', editing.value.id), {
        onSuccess: () => (editing.value = null),
    });
};

const destroy = (stage) => {
    if (confirm(t('stagesAdmin.deleteConfirm', { name: stage.name }))) {
        router.delete(route('stages.destroy', stage.id));
    }
};

const columns = [
    { key: 'name', label: t('profile.name'), sortable: true },
    { key: 'education_type.name', label: t('taxonomyAdmin.educationTypeLabel'), sortable: true },
    { key: 'departments_count', label: t('structureTabs.departments'), sortable: true },
    { key: 'actions', label: t('doctorsAdmin.actionsCol'), align: 'right' },
];
</script>

<template>
    <Head :title="t('structureTabs.stages')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                {{ t('structureTabs.stages') }}
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs active="stages" />

                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submitCreate" class="flex items-start gap-3">
                        <div class="flex-1">
                            <TextInput v-model="createForm.name" type="text" :placeholder="t('stagesAdmin.newNamePlaceholder')" class="block w-full" required />
                            <InputError class="mt-2" :message="createForm.errors.name" />
                        </div>
                        <div class="w-56">
                            <select v-model="createForm.education_type_id" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">{{ t('taxonomyAdmin.noEducationType') }}</option>
                                <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                            </select>
                        </div>
                        <PrimaryButton :disabled="createForm.processing">{{ t('common.add') }}</PrimaryButton>
                    </form>
                </div>

                <div class="flex flex-wrap gap-2 rounded-lg bg-white p-4 shadow-sm">
                    <input
                        v-model="search"
                        @keyup.enter="applyFilters"
                        type="text"
                        :placeholder="t('taxonomyAdmin.searchPlaceholder')"
                        class="block flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        style="min-width: 12rem"
                    />
                    <select
                        v-model="filterEducationTypeId"
                        @change="applyFilters"
                        class="w-56 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">{{ t('taxonomyAdmin.allEducationTypes') }}</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <SecondaryButton @click="applyFilters">{{ t('taxonomyAdmin.searchButton') }}</SecondaryButton>
                </div>

                <DataTable
                    :columns="columns"
                    :rows="stages"
                    :empty-text="search || filterEducationTypeId ? t('taxonomyAdmin.noMatchingResults') : t('stagesAdmin.emptyList')"
                >
                    <template #cell-actions="{ row: stage }">
                        <button @click="openEdit(stage)" class="text-indigo-600 hover:text-indigo-900">{{ t('common.edit') }}</button>
                        <button @click="destroy(stage)" class="ml-4 text-red-600 hover:text-red-900">{{ t('common.delete') }}</button>
                    </template>
                </DataTable>
            </div>
        </div>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('stagesAdmin.editTitle') }}</h2>
                <div class="mt-4">
                    <InputLabel for="edit-name" :value="t('profile.name')" />
                    <TextInput id="edit-name" v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name" />
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-education-type" :value="t('taxonomyAdmin.educationTypeLabel')" />
                    <select id="edit-education-type" v-model="editForm.education_type_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('taxonomyAdmin.noEducationType') }}</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="editForm.errors.education_type_id" />
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
