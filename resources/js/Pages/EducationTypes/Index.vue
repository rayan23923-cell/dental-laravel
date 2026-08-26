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
    if (confirm(`Delete "${type.name}"? This will also delete related departments and doctors (cascade).`)) {
        router.delete(route('education-types.destroy', type.id));
    }
};
</script>

<template>
    <Head title="Education Types" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                Education Types
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
                            <TextInput v-model="createForm.name" type="text" placeholder="New education type name" class="block w-full" required />
                            <InputError class="mt-2" :message="createForm.errors.name" />
                        </div>
                        <PrimaryButton :disabled="createForm.processing">Add</PrimaryButton>
                    </form>
                </div>

                <div class="flex gap-2 rounded-lg bg-white p-4 shadow-sm">
                    <input
                        v-model="search"
                        @keyup.enter="applySearch"
                        type="text"
                        placeholder="ابحث بالاسم..."
                        class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    />
                    <SecondaryButton @click="applySearch">بحث</SecondaryButton>
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Name</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Stages</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="type in educationTypes" :key="type.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ type.name }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ type.stages_count }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <button @click="openEdit(type)" class="text-indigo-600 hover:text-indigo-900">Edit</button>
                                    <button @click="destroy(type)" class="ml-4 text-red-600 hover:text-red-900">Delete</button>
                                </td>
                            </tr>
                            <tr v-if="educationTypes.length === 0">
                                <td colspan="3" class="px-6 py-8 text-center text-sm text-gray-500">
                                    {{ search ? 'لا توجد نتائج مطابقة.' : 'No education types yet.' }}
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">Edit Education Type</h2>
                <div class="mt-4">
                    <InputLabel for="edit-name" value="Name" />
                    <TextInput id="edit-name" v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name" />
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">Cancel</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">Save</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
