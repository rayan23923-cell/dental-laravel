<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';
import ChatPager from '@/Components/ChatList/ChatPager.vue';
import { Head, router } from '@inertiajs/vue3';
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    logs: Object,
    filters: Object,
    modules: Array,
});

const search = ref(props.filters.search ?? '');
const module = ref(props.filters.module ?? '');
const action = ref(props.filters.action ?? '');

const applyFilters = () => {
    router.get(route('activity-logs.index'), {
        search: search.value,
        module: module.value,
        action: action.value,
    }, { preserveState: true, replace: true });
};

watch(search, applyFilters);
watch(module, applyFilters);
watch(action, applyFilters);

// Chat-list style (2026-10-13, by request): the action carries the row's
// colour and avatar icon.
const ACTION_STYLE = {
    create: { tone: 'emerald', icon: 'add_circle', label: 'activityLogsAdmin.actionCreate' },
    update: { tone: 'amber', icon: 'edit', label: 'activityLogsAdmin.actionUpdate' },
    delete: { tone: 'rose', icon: 'delete', label: 'activityLogsAdmin.actionDelete' },
};
const actionStyle = (a) => ACTION_STYLE[a] ?? { tone: 'gray', icon: 'history', label: null };
</script>

<template>
    <Head :title="t('activityLogsAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('activityLogsAdmin.title') }}</h2>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <ChatSearch v-model="search" :placeholder="t('activityLogsAdmin.searchPlaceholder')" />

                <div class="flex flex-wrap items-center gap-2">
                    <select v-model="module" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('activityLogsAdmin.allModules') }}</option>
                        <option v-for="m in modules" :key="m" :value="m">{{ m }}</option>
                    </select>
                    <select v-model="action" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('activityLogsAdmin.allActions') }}</option>
                        <option value="create">{{ t('activityLogsAdmin.actionCreate') }}</option>
                        <option value="update">{{ t('activityLogsAdmin.actionUpdate') }}</option>
                        <option value="delete">{{ t('activityLogsAdmin.actionDelete') }}</option>
                    </select>
                </div>

                <ChatListCard :empty="logs.data.length === 0" :empty-text="t('activityLogsAdmin.emptyList')" empty-icon="history">
                    <ChatListRow
                        v-for="log in logs.data"
                        :key="log.id"
                        :title="log.username || '—'"
                        :icon="actionStyle(log.action).icon"
                        :tone="actionStyle(log.action).tone"
                    >
                        <template #meta>
                            <p v-if="log.description" class="w-full break-words text-sm text-gray-600">{{ log.description }}</p>
                            <ChatChip :tone="actionStyle(log.action).tone">
                                {{ actionStyle(log.action).label ? t(actionStyle(log.action).label) : log.action }}
                            </ChatChip>
                            <ChatChip v-if="log.module" icon="folder">{{ log.module }}</ChatChip>
                            <ChatChip v-if="log.user_role" icon="badge">{{ log.user_role }}</ChatChip>
                            <ChatChip icon="schedule">{{ new Date(log.created_at).toLocaleString() }}</ChatChip>
                        </template>
                    </ChatListRow>
                    <template #footer>
                        <ChatPager :links="logs.links" />
                    </template>
                </ChatListCard>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
