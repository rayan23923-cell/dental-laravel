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

// Chat-list style (2026-10-13, by request): adding opens a dialog from
// the round "+" in the header instead of an inline form.
const creating = ref(false);
const createForm = useForm({ name: '' });
const openCreate = () => {
    createForm.reset();
    createForm.clearErrors();
    creating.value = true;
};
const submitCreate = () => {
    createForm.post(route('education-types.store'), {
        onSuccess: () => {
            createForm.reset();
            creating.value = false;
        },
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

</script>

<template>
    <Head :title="t('structureTabs.educationTypes')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('structureTabs.educationTypes') }}</h2>
                <ChatAddButton :label="t('chatList.addEducationType')" @click="openCreate" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <StructureTabs />

                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700 whitespace-pre-line">
                    {{ page.props.flash.error }}
                </div>

                <ChatSearch v-model="search" :placeholder="t('taxonomyAdmin.searchPlaceholder')" @submit="applySearch" />

                <ChatListCard
                    :empty="educationTypes.length === 0"
                    :empty-text="search ? t('taxonomyAdmin.noMatchingResults') : t('educationTypesAdmin.emptyList')"
                    empty-icon="school"
                >
                    <ChatListRow v-for="type in educationTypes" :key="type.id" :title="type.name" icon="school" :tone="toneFor(type.id)">
                        <template #meta>
                            <ChatChip icon="stairs" tone="indigo">{{ type.stages_count ?? 0 }} {{ t('structureTabs.stages') }}</ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction icon="edit" :label="t('common.edit')" @click="openEdit(type)" />
                            <ChatAction icon="delete" :label="t('common.delete')" danger @click="destroy(type)" />
                        </template>
                    </ChatListRow>
                </ChatListCard>
            </div>
        </div>

        <Modal :show="creating" @close="creating = false">
            <form @submit.prevent="submitCreate" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('chatList.addEducationType') }}</h2>
                <div class="mt-4">
                    <InputLabel for="create-name" :value="t('profile.name')" />
                    <TextInput id="create-name" v-model="createForm.name" type="text" :placeholder="t('educationTypesAdmin.newNamePlaceholder')" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="createForm.errors.name" />
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="creating = false">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="createForm.processing">{{ t('common.add') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

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
