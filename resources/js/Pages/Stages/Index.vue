<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import StructureTabs from '@/Components/StructureTabs.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';

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
    if (confirm(`Delete "${stage.name}"?`)) {
        router.delete(route('stages.destroy', stage.id));
    }
};
</script>

<template>
    <Head title="Stages" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                Stages
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
                            <TextInput v-model="createForm.name" type="text" placeholder="New stage name" class="block w-full" required />
                            <InputError class="mt-2" :message="createForm.errors.name" />
                        </div>
                        <div class="w-56">
                            <select v-model="createForm.education_type_id" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">No education type</option>
                                <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
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
                        @change="applyFilters"
                        class="w-56 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">كل أنواع التعليم</option>
                        <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                    </select>
                    <SecondaryButton @click="applyFilters">بحث</SecondaryButton>
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Name</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Education Type</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Departments</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="stage in stages" :key="stage.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ stage.name }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ stage.education_type?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ stage.departments_count }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <button @click="openEdit(stage)" class="text-indigo-600 hover:text-indigo-900">Edit</button>
                                    <button @click="destroy(stage)" class="ml-4 text-red-600 hover:text-red-900">Delete</button>
                                </td>
                            </tr>
                            <tr v-if="stages.length === 0">
                                <td colspan="4" class="px-6 py-8 text-center text-sm text-gray-500">
                                    {{ search || filterEducationTypeId ? 'لا توجد نتائج مطابقة.' : 'No stages yet.' }}
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">Edit Stage</h2>
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
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">Cancel</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">Save</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
