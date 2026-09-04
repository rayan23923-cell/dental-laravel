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
    educationTypes: Array,
    filters: { type: Object, default: () => ({}) },
});

const page = usePage();

const search = ref(props.filters.search ?? '');
const applySearch = () => {
    router.get(route('education-types.index'), { search: search.value || undefined }, { preserveState: true, replace: true });
};

const createForm = useForm({ name: '' });
const submitCreate = () => {
    createForm.post(route('education-types.store'), {
        onSuccess: () => createForm.reset(),
    });
};

const editing = ref(null);
const editForm = useForm({ name: '' });
const openEdit = (type) => {
    editing.value = type;
    editForm.name = type.name;
};
const submitEdit = () => {
    editForm.put(route('education-types.update', editing.value.id), {
        onSuccess: () => (editing.value = null),
    });
};

const destroy = (type) => {
    if (confirm(t('educationTypesAdmin.deleteConfirm', { name: type.name }))) {
        router.delete(route('education-types.destroy', type.id));
    }
};

const columns = [
    { key: 'name', label: t('profile.name'), sortable: true },
    { key: 'stages_count', label: t('structureTabs.stages'), sortable: true },
    { key: 'actions', label: t('doctorsAdmin.actionsCol'), align: 'right' },
];
</script>

<template>
    <Head :title="t('structureTabs.educationTypes')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                {{ t('structureTabs.educationTypes') }}
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-3xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs active="education-types" />

                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submitCreate" class="flex items-start gap-3">
                        <div class="flex-1">
                            <TextInput v-model="createForm.name" type="text" :placeholder="t('educationTypesAdmin.newNamePlaceholder')" class="block w-full" required />
                            <InputError class="mt-2" :message="createForm.errors.name" />
                        </div>
                        <PrimaryButton :disabled="createForm.processing">{{ t('common.add') }}</PrimaryButton>
                    </form>
                </div>

                <div class="flex gap-2 rounded-lg bg-white p-4 shadow-sm">
                    <input
                        v-model="search"
                        @keyup.enter="applySearch"
                        type="text"
                        :placeholder="t('taxonomyAdmin.searchPlaceholder')"
                        class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    />
                    <SecondaryButton @click="applySearch">{{ t('taxonomyAdmin.searchButton') }}</SecondaryButton>
                </div>

                <DataTable
                    :columns="columns"
                    :rows="educationTypes"
                    :empty-text="search ? t('taxonomyAdmin.noMatchingResults') : t('educationTypesAdmin.emptyList')"
                >
                    <template #cell-actions="{ row: type }">
                        <button @click="openEdit(type)" class="text-indigo-600 hover:text-indigo-900">{{ t('common.edit') }}</button>
                        <button @click="destroy(type)" class="ml-4 text-red-600 hover:text-red-900">{{ t('common.delete') }}</button>
                    </template>
                </DataTable>
            </div>
        </div>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('educationTypesAdmin.editTitle') }}</h2>
                <div class="mt-4">
                    <InputLabel for="edit-name" :value="t('profile.name')" />
                    <TextInput id="edit-name" v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name" />
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
