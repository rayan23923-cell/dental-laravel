<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { toneFor } from '@/Components/ChatList/tones';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import StructureTabs from '@/Components/StructureTabs.vue';

const { t, locale } = useI18n();
defineProps({
    caseSheetTypes: Array,
});

const page = usePage();

// Chat-list style (2026-10-13, by request): the name in the viewer's
// language is the row title, the other language sits under it.
const isAr = () => String(locale.value).startsWith('ar');
const titleOf = (type) => (isAr() ? type.name_ar : type.name_en) || type.name_ar || type.name_en || type.type_code;
const subtitleOf = (type) => (isAr() ? type.name_en : type.name_ar) || '';

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

</script>

<template>
    <Head :title="t('caseSheetTypesAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('caseSheetTypesAdmin.title') }}</h2>
                <ChatAddButton :label="t('caseSheetTypesAdmin.addTitle')" @click="showCreate = true" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <StructureTabs />

                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <ChatListCard :empty="caseSheetTypes.length === 0" :empty-text="t('caseSheetTypesAdmin.emptyList')" empty-icon="description">
                    <ChatListRow
                        v-for="type in caseSheetTypes"
                        :key="type.id"
                        :title="titleOf(type)"
                        :subtitle="subtitleOf(type)"
                        icon="description"
                        :tone="type.is_active ? toneFor(type.id) : 'gray'"
                    >
                        <template #meta>
                            <ChatChip icon="tag" tone="gray"><span dir="ltr">{{ type.type_code }}</span></ChatChip>
                            <ChatChip icon="assignment" tone="indigo">{{ type.tasks_count ?? 0 }} {{ t('caseSheetTypesAdmin.tasksCol') }}</ChatChip>
                            <ChatChip v-if="type.is_active" icon="check_circle" tone="emerald">{{ t('caseSheetTypesAdmin.active') }}</ChatChip>
                            <ChatChip v-else icon="block" tone="gray">{{ t('caseSheetTypesAdmin.inactive') }}</ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction icon="edit" :label="t('common.edit')" @click="openEdit(type)" />
                        </template>
                    </ChatListRow>
                </ChatListCard>
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
