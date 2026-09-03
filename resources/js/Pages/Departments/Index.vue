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
import { computed, ref, watch } from 'vue';

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
const submitCreate = () => {
    createForm.post(route('departments.store'), {
        onSuccess: () => createForm.reset(),
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
    if (confirm(`Delete "${department.name}"?`)) {
        router.delete(route('departments.destroy', department.id));
    }
};

const columns = [
    { key: 'name', label: 'Name', sortable: true },
    { key: 'stage.name', label: 'Stage', sortable: true },
    { key: 'education_type.name', label: 'Education Type', sortable: true },
    { key: 'actions', label: 'Actions', align: 'right' },
];
</script>

<template>
    <Head title="Departments" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                Departments
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs active="departments" />

                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submitCreate" class="flex flex-wrap items-start gap-3">
                        <div class="flex-1" style="min-width: 12rem">
                            <TextInput v-model="createForm.name" type="text" placeholder="New department name" class="block w-full" required />
                            <InputError class="mt-2" :message="createForm.errors.name" />
                        </div>
                        <div class="w-48">
                            <select v-model="createForm.education_type_id" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">No education type</option>
                                <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                            </select>
                        </div>
                        <div class="w-48">
                            <select v-model="createForm.stage_id" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">No stage</option>
                                <option v-for="stage in filteredCreateStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                            </select>
                        </div>
                        <PrimaryButton :disabled="createForm.processing">Add</PrimaryButton>
                    </form>
                </div>

                <div class="flex flex-wrap gap-2 rounded-lg bg-white p-4 shadow-sm">
                    <input
                        v-model="search"
                        @keyup.enter="applyFilters"
                        type="text"
                        placeholder="ابحث بالاسم..."
                        class="block flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        style="min-width: 12rem"
                    />
                    <select
                        v-model="filterEducationTypeId"
                        @change="onFilterEducationTypeChange"
                        class="w-48 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">كل أنواع التعليم</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <select
                        v-model="filterStageId"
                        @change="applyFilters"
                        class="w-48 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">كل المراحل</option>
                        <option v-for="stage in filteredStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                    </select>
                    <SecondaryButton @click="applyFilters">بحث</SecondaryButton>
                </div>

                <DataTable
                    :columns="columns"
                    :rows="departments"
                    :empty-text="search || filterStageId || filterEducationTypeId ? 'لا توجد نتائج مطابقة.' : 'No departments yet.'"
                >
                    <template #cell-actions="{ row: department }">
                        <button @click="openEdit(department)" class="text-indigo-600 hover:text-indigo-900">Edit</button>
                        <button @click="destroy(department)" class="ml-4 text-red-600 hover:text-red-900">Delete</button>
                    </template>
                </DataTable>
            </div>
        </div>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">Edit Department</h2>
                <div class="mt-4">
                    <InputLabel for="edit-name" value="Name" />
                    <TextInput id="edit-name" v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name" />
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-education-type" value="Education Type" />
                    <select id="edit-education-type" v-model="editForm.education_type_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">No education type</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="editForm.errors.education_type_id" />
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-stage" value="Stage" />
                    <select id="edit-stage" v-model="editForm.stage_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">No stage</option>
                        <option v-for="stage in filteredEditStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="editForm.errors.stage_id" />
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">Cancel</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">Save</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
