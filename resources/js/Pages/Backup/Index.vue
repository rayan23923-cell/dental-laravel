<script setup>
/**
 * Port of admin/backup.php — manual backup button, daily-auto toggle, and
 * a table of the most recent backups with download links. See
 * App\Http\Controllers\BackupController for what's deliberately different
 * from the original (files aren't in a public folder; the daily backup is
 * a real Laravel schedule, not a page-load side effect).
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    enabled: Boolean,
    // The offline package backs up daily whatever the toggle says (2026-10-13).
    alwaysDaily: Boolean,
    folder: String,
    lastBackupAt: String,
    files: { type: Array, default: () => [] },
});

const page = usePage();
const creating = ref(false);

const createBackup = () => {
    creating.value = true;
    router.post(route('backup.store'), {}, {
        preserveScroll: true,
        onFinish: () => (creating.value = false),
    });
};

const toggleForm = useForm({ enabled: props.enabled });
const toggleAuto = (checked) => {
    toggleForm.enabled = checked;
    toggleForm.transform((data) => ({ ...data, _method: 'put' })).post(route('backup.toggle-auto'), {
        preserveScroll: true,
    });
};

const bytesToSize = (bytes) => {
    if (!bytes) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`;
};

const formatDate = (unixSeconds) => new Date(unixSeconds * 1000).toLocaleString('ar');
</script>

<template>
    <Head :title="t('backupAdmin.title')" />

    <AuthenticatedLayout>
        <!-- Chat-list style (2026-10-13, by request): "backup now" is the round
             header button and the backups are a chat-list. -->
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('backupAdmin.title') }}</h2>
                <ChatAddButton
                    :label="creating ? t('backupAdmin.creating') : t('backupAdmin.createNow')"
                    :icon="creating ? 'progress_activity' : 'backup'"
                    :disabled="creating"
                    :class="creating ? 'animate-pulse opacity-70' : ''"
                    @click="createBackup"
                />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div class="flex flex-wrap items-center gap-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <div class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-purple-500 text-white">
                        <Icon name="database" size="text-[24px]" />
                    </div>
                    <div class="min-w-0 flex-1 text-sm font-medium text-gray-800">
                        {{ lastBackupAt ? t('backupAdmin.lastBackupAt', { date: lastBackupAt }) : t('backupAdmin.noPreviousBackup') }}
                    </div>
                    <label class="flex items-center gap-2 rounded-full bg-gray-50 px-3 py-1.5 text-sm text-gray-700">
                        <input
                            type="checkbox"
                            :disabled="alwaysDaily"
                            :checked="enabled || alwaysDaily"
                            class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                            @change="toggleAuto($event.target.checked)"
                        />
                        <Icon name="event_repeat" size="text-[18px]" class="text-indigo-500" />
                        {{ t('backupAdmin.enableDailyAuto') }}
                    </label>
                </div>

                <div class="flex gap-2 rounded-xl bg-sky-50 p-3 text-sm text-sky-800">
                    <Icon name="info" class="shrink-0" />
                    <div class="min-w-0">
                        {{ t('backupAdmin.scheduleNote') }}
                        <p v-if="folder" class="mt-2 break-all">{{ t('backupAdmin.folderNote') }} <span class="font-mono" dir="ltr">{{ folder }}</span></p>
                    </div>
                </div>

                <ChatListCard :empty="files.length === 0" :empty-text="t('backupAdmin.emptyList')" empty-icon="cloud_off">
                    <ChatListRow v-for="f in files" :key="f.name" :title="f.name" icon="folder_zip" tone="indigo">
                        <template #meta>
                            <ChatChip icon="hard_drive" tone="sky">{{ bytesToSize(f.size) }}</ChatChip>
                            <ChatChip icon="schedule">{{ formatDate(f.mtime) }}</ChatChip>
                        </template>
                        <template #actions>
                            <!-- A plain link: the file downloads, no Inertia visit. -->
                            <a
                                :href="route('backup.download', f.name)"
                                :title="t('backupAdmin.download')"
                                class="inline-flex h-9 w-9 items-center justify-center rounded-full text-gray-500 transition hover:bg-gray-100 hover:text-indigo-600"
                            >
                                <Icon name="cloud_download" size="text-[20px]" :label="t('backupAdmin.download')" />
                            </a>
                        </template>
                    </ChatListRow>
                </ChatListCard>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
