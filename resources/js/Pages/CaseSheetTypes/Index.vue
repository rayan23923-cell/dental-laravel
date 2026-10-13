<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import StructureTabs from '@/Components/StructureTabs.vue';

const { t } = useI18n();
defineProps({
    caseSheetTypes: Array,
});

const page = usePage();

const showCreate = ref(false);
const createForm = useForm({ type_code: '', name_ar: '', name_en: '', description: '', is_active: true });
const submitCreate = () => {
    createForm.post(route('case-sheet-types.store'), {
        onSuccess: () => {
            createForm.reset();
            showCreate.value = false;
        },
    });
};

const editing = ref(null);
const editForm = useForm({ name_ar: '', name_en: '', description: '', is_active: true });
const openEdit = (type) => {
    editing.value = type;
    editForm.name_ar = type.name_ar;
    editForm.name_en = type.name_en;
    editForm.description = type.description ?? '';
    editForm.is_active = !!type.is_active;
};
const submitEdit = () => {
    editForm.put(route('case-sheet-types.update', editing.value.id), {
        onSuccess: () => (editing.value = null),
    });
};

const destroy = (type) => {
    if (confirm(t('caseSheetTypesAdmin.deleteConfirm', { name: type.name_en }))) {
        router.delete(route('case-sheet-types.destroy', type.id));
    }
};
</script>

<template>
    <Head :title="t('caseSheetTypesAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('caseSheetTypesAdmin.title') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs />

                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-md bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <div class="flex justify-end">
                    <PrimaryButton @click="showCreate = true">{{ t('caseSheetTypesAdmin.addType') }}</PrimaryButton>
                </div>

                <div class="overflow-x-auto bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('caseSheetTypesAdmin.codeCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('caseSheetTypesAdmin.nameArCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('caseSheetTypesAdmin.nameEnCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('caseSheetTypesAdmin.tasksCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.statusCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.actionsCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="type in caseSheetTypes" :key="type.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ type.type_code }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ type.name_ar }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ type.name_en }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ type.tasks_count }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <span v-if="type.is_active" class="rounded-full bg-green-100 px-2 py-1 text-xs font-medium text-green-700">{{ t('caseSheetTypesAdmin.active') }}</span>
                                    <span v-else class="rounded-full bg-gray-100 px-2 py-1 text-xs font-medium text-gray-600">{{ t('caseSheetTypesAdmin.inactive') }}</span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <button @click="openEdit(type)" class="text-indigo-600 hover:text-indigo-900">{{ t('common.edit') }}</button>
                                    <button @click="destroy(type)" class="ml-4 text-red-600 hover:text-red-900">{{ t('common.delete') }}</button>
                                </td>
                            </tr>
                            <tr v-if="caseSheetTypes.length === 0">
                                <td colspan="6" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('caseSheetTypesAdmin.emptyList') }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <Modal :show="showCreate" @close="showCreate = false">
            <form @submit.prevent="submitCreate" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('caseSheetTypesAdmin.addTitle') }}</h2>
                <div class="mt-4">
                    <InputLabel for="create-code" :value="t('caseSheetTypesAdmin.codeLabel')" />
                    <TextInput id="create-code" v-model="createForm.type_code" type="text" class="mt-1 block w-full" required autofocus />
                    <InputError class="mt-2" :message="createForm.errors.type_code" />
                </div>
                <div class="mt-4">
                    <InputLabel for="create-name-ar" :value="t('caseSheetTypesAdmin.nameArLabel')" />
                    <TextInput id="create-name-ar" v-model="createForm.name_ar" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="createForm.errors.name_ar" />
                </div>
                <div class="mt-4">
                    <InputLabel for="create-name-en" :value="t('caseSheetTypesAdmin.nameEnLabel')" />
                    <TextInput id="create-name-en" v-model="createForm.name_en" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="createForm.errors.name_en" />
                </div>
                <div class="mt-4">
                    <InputLabel for="create-description" :value="t('caseSheetTypesAdmin.descriptionLabel')" />
                    <textarea id="create-description" v-model="createForm.description" rows="2" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                    <InputError class="mt-2" :message="createForm.errors.description" />
                </div>
                <label class="mt-4 flex items-center gap-2 text-sm text-gray-700">
                    <input type="checkbox" v-model="createForm.is_active" class="rounded border-gray-300" />
                    {{ t('caseSheetTypesAdmin.activeLabel') }}
                </label>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="showCreate = false">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="createForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('caseSheetTypesAdmin.editTitle') }}</h2>
                <p class="mt-1 text-xs text-gray-400">{{ t('caseSheetTypesAdmin.codeNotEditable', { code: editing?.type_code }) }}</p>
                <div class="mt-4">
                    <InputLabel for="edit-name-ar" :value="t('caseSheetTypesAdmin.nameArLabel')" />
                    <TextInput id="edit-name-ar" v-model="editForm.name_ar" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name_ar" />
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-name-en" :value="t('caseSheetTypesAdmin.nameEnLabel')" />
                    <TextInput id="edit-name-en" v-model="editForm.name_en" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name_en" />
                </div>
                <div class="mt-4">
                    <InputLabel for="edit-description" :value="t('caseSheetTypesAdmin.descriptionLabel')" />
                    <textarea id="edit-description" v-model="editForm.description" rows="2" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                    <InputError class="mt-2" :message="editForm.errors.description" />
                </div>
                <label class="mt-4 flex items-center gap-2 text-sm text-gray-700">
                    <input type="checkbox" v-model="editForm.is_active" class="rounded border-gray-300" />
                    {{ t('caseSheetTypesAdmin.activeLabel') }}
                </label>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
