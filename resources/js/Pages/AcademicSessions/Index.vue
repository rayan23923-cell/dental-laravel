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
import StructureTabs from '@/Components/StructureTabs.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
defineProps({
    sessions: Array,
    selectedSessionId: Number,
});

const page = usePage();

const showCreate = ref(false);
const createForm = useForm({ name: '', start_date: '', end_date: '', is_active: true, is_current: false });
const submitCreate = () => {
    createForm.post(route('academic-sessions.store'), {
        onSuccess: () => {
            createForm.reset();
            showCreate.value = false;
        },
    });
};

const editing = ref(null);
const editForm = useForm({ name: '', start_date: '', end_date: '', is_active: true, is_current: false });
const openEdit = (session) => {
    editing.value = session;
    editForm.name = session.name;
    editForm.start_date = session.start_date;
    editForm.end_date = session.end_date;
    editForm.is_active = !!session.is_active;
    editForm.is_current = !!session.is_current;
};
const submitEdit = () => {
    editForm.put(route('academic-sessions.update', editing.value.id), {
        onSuccess: () => (editing.value = null),
    });
};

const setCurrent = (session) => {
    router.put(route('academic-sessions.set-current', session.id));
};

const selectViewing = (session) => {
    router.post(route('academic-sessions.select'), { academic_session_id: session.id });
};

const destroy = (session) => {
    if (confirm(t('academicSessionsAdmin.deleteConfirm', { name: session.name }))) {
        router.delete(route('academic-sessions.destroy', session.id));
    }
};
</script>

<template>
    <Head :title="t('structureTabs.academicSessions')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('structureTabs.academicSessions') }}</h2>
                <ChatAddButton :label="t('academicSessionsAdmin.addSession')" @click="showCreate = true" />
            </div>
        </template>

        <!-- Chat-list style (2026-10-13, by request): each year is a row with
             date/groups/tasks chips and icon actions instead of a wide table. -->
        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <StructureTabs active="academic-sessions" />

                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <ChatListCard :empty="sessions.length === 0" :empty-text="t('academicSessionsAdmin.emptyList')" empty-icon="calendar_month">
                    <ChatListRow
                        v-for="session in sessions"
                        :key="session.id"
                        :title="session.name"
                        icon="calendar_month"
                        :tone="session.is_current ? 'emerald' : toneFor(session.id)"
                        :href="route('academic-sessions.show', session.id)"
                        :selected="session.id === selectedSessionId"
                    >
                        <template #meta>
                            <ChatChip icon="date_range" tone="gray" :title="t('academicSessionsAdmin.datesCol')"><span dir="ltr">{{ session.start_date }} → {{ session.end_date }}</span></ChatChip>
                            <ChatChip v-if="$page.props.groupsEnabled !== false" icon="groups" tone="sky" :title="t('structureTabs.groups')">{{ session.groups_count ?? 0 }}</ChatChip>
                            <ChatChip icon="assignment" tone="amber" :title="t('academicSessionsAdmin.tasksCol')">{{ session.tasks_count ?? 0 }}</ChatChip>
                            <ChatChip v-if="session.is_current" icon="check_circle" tone="emerald">{{ t('chatList.currentSession') }}</ChatChip>
                            <ChatChip v-if="session.id === selectedSessionId" icon="visibility" tone="indigo">{{ t('chatList.viewingSession') }}</ChatChip>
                        </template>
                        <template #actions>
                            <!-- iOS-style toggle — turning a year on makes it current and
                                 (via AcademicSession::booted()'s saving() hook, see
                                 dental_laravel/README.md) automatically turns every other
                                 year off, so there's no separate "off" action: the only way
                                 to turn the current year off is to turn a different one on.
                                 Matches the same control added to the Flutter admin app. -->
                            <button
                                type="button"
                                :disabled="session.is_current"
                                @click="setCurrent(session)"
                                :title="session.is_current ? t('academicSessionsAdmin.currentAriaActive') : t('academicSessionsAdmin.currentAriaSetActive')"
                                :class="[
                                    'relative mx-1 inline-flex h-6 w-11 flex-shrink-0 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2',
                                    session.is_current ? 'bg-green-500 cursor-default' : 'bg-gray-300 cursor-pointer hover:bg-gray-400',
                                ]"
                                :aria-label="session.is_current ? t('academicSessionsAdmin.currentAriaActive') : t('academicSessionsAdmin.currentAriaSetActive')"
                            >
                                <span
                                    :class="[
                                        'inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform',
                                        session.is_current ? 'translate-x-6' : 'translate-x-1',
                                    ]"
                                />
                            </button>
                            <ChatAction v-if="session.id !== selectedSessionId" icon="visibility" :label="t('academicSessionsAdmin.selectViewing')" @click="selectViewing(session)" />
                            <ChatAction icon="edit" :label="t('common.edit')" @click="openEdit(session)" />
                            <ChatAction v-if="!session.is_current" icon="delete" :label="t('common.delete')" danger @click="destroy(session)" />
                        </template>
                    </ChatListRow>
                </ChatListCard>
            </div>
        </div>

        <Modal :show="showCreate" @close="showCreate = false">
            <form @submit.prevent="submitCreate" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('academicSessionsAdmin.addSession') }}</h2>
                <div class="mt-4">
                    <InputLabel for="create-name" :value="t('profile.name')" />
                    <TextInput id="create-name" v-model="createForm.name" type="text" class="mt-1 block w-full" required autofocus />
                    <InputError class="mt-2" :message="createForm.errors.name" />
                </div>
                <div class="mt-4 grid grid-cols-2 gap-4">
                    <div>
                        <InputLabel for="create-start" :value="t('academicSessionsAdmin.startDateLabel')" />
                        <TextInput id="create-start" v-model="createForm.start_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="createForm.errors.start_date" />
                    </div>
                    <div>
                        <InputLabel for="create-end" :value="t('academicSessionsAdmin.endDateLabel')" />
                        <TextInput id="create-end" v-model="createForm.end_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="createForm.errors.end_date" />
                    </div>
                </div>
                <div class="mt-4 flex gap-6">
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="createForm.is_active" class="rounded border-gray-300" />
                        {{ t('academicSessionsAdmin.activeLabel') }}
                    </label>
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="createForm.is_current" class="rounded border-gray-300" />
                        {{ t('academicSessionsAdmin.setCurrentLabel') }}
                    </label>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="showCreate = false">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="createForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('academicSessionsAdmin.editModalTitle') }}</h2>
                <div class="mt-4">
                    <InputLabel for="edit-name" :value="t('profile.name')" />
                    <TextInput id="edit-name" v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name" />
                </div>
                <div class="mt-4 grid grid-cols-2 gap-4">
                    <div>
                        <InputLabel for="edit-start" :value="t('academicSessionsAdmin.startDateLabel')" />
                        <TextInput id="edit-start" v-model="editForm.start_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="editForm.errors.start_date" />
                    </div>
                    <div>
                        <InputLabel for="edit-end" :value="t('academicSessionsAdmin.endDateLabel')" />
                        <TextInput id="edit-end" v-model="editForm.end_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="editForm.errors.end_date" />
                    </div>
                </div>
                <div class="mt-4 flex gap-6">
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="editForm.is_active" class="rounded border-gray-300" />
                        {{ t('academicSessionsAdmin.activeLabel') }}
                    </label>
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="editForm.is_current" class="rounded border-gray-300" />
                        {{ t('academicSessionsAdmin.setCurrentLabel') }}
                    </label>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
