<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, router } from '@inertiajs/vue3';
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

const actionColor = (a) => ({
    create: 'bg-green-100 text-green-800',
    update: 'bg-amber-100 text-amber-800',
    delete: 'bg-red-100 text-red-800',
}[a] ?? 'bg-gray-100 text-gray-700');
</script>

<template>
    <Head :title="t('activityLogsAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('activityLogsAdmin.title') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-6xl space-y-4 sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <div class="flex flex-wrap gap-3 border-b border-gray-200 p-4">
                        <TextInput v-model="search" type="text" :placeholder="t('activityLogsAdmin.searchPlaceholder')" class="w-full max-w-xs" />
                        <select v-model="module" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                            <option value="">{{ t('activityLogsAdmin.allModules') }}</option>
                            <option v-for="m in modules" :key="m" :value="m">{{ m }}</option>
                        </select>
                        <select v-model="action" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                            <option value="">{{ t('activityLogsAdmin.allActions') }}</option>
                            <option value="create">{{ t('activityLogsAdmin.actionCreate') }}</option>
                            <option value="update">{{ t('activityLogsAdmin.actionUpdate') }}</option>
                            <option value="delete">{{ t('activityLogsAdmin.actionDelete') }}</option>
                        </select>
                    </div>

                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('activityLogsAdmin.whenCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('activityLogsAdmin.userCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('activityLogsAdmin.actionCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('activityLogsAdmin.moduleCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('activityLogsAdmin.descriptionCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="log in logs.data" :key="log.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ new Date(log.created_at).toLocaleString() }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900">{{ log.username }} <span class="text-xs text-gray-400">({{ log.user_role }})</span></td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <span class="rounded-full px-2 py-1 text-xs font-medium" :class="actionColor(log.action)">{{ log.action }}</span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ log.module }}</td>
                                <td class="px-6 py-4 text-sm text-gray-700">{{ log.description }}</td>
                            </tr>
                            <tr v-if="logs.data.length === 0">
                                <td colspan="5" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('activityLogsAdmin.emptyList') }}</td>
                            </tr>
                        </tbody>
                    </table>

                    <div class="flex justify-between border-t border-gray-200 p-4">
                        <Link
                            v-for="link in logs.links"
                            :key="link.label"
                            :href="link.url ?? ''"
                            v-html="link.label"
                            class="mx-1 rounded px-3 py-1 text-sm"
                            :class="{
                                'bg-indigo-600 text-white': link.active,
                                'text-gray-400 pointer-events-none': !link.url,
                                'text-gray-700 hover:bg-gray-100': link.url && !link.active,
                            }"
                        />
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
