<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import DataTable from '@/Components/DataTable.vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
defineProps({
    users: Array,
});

const page = usePage();

const columns = [
    { key: 'full_name', label: t('profile.name'), sortable: true },
    { key: 'role', label: t('common.role'), sortable: true },
    { key: 'actions', label: t('doctorsAdmin.actionsCol'), align: 'right' },
];
</script>

<template>
    <Head :title="t('permissionsAdmin.indexTitle')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('permissionsAdmin.indexTitle') }}</h2>
                <div class="flex items-center gap-4">
                    <Link :href="route('users.create')" class="text-sm text-indigo-600 hover:underline">{{ t('permissionsAdmin.addUserLink') }}</Link>
                    <Link :href="route('department-roles.index')" class="text-sm text-indigo-600 hover:underline">{{ t('permissionsAdmin.departmentRolesLink') }}</Link>
                </div>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <p class="text-sm text-gray-600">
                    {{ t('permissionsAdmin.grantsDescription') }}
                </p>

                <DataTable
                    :columns="columns"
                    :rows="users"
                    searchable
                    :search-placeholder="t('permissionsAdmin.searchPlaceholder')"
                    :empty-text="t('permissionsAdmin.emptyUsers')"
                >
                    <template #cell-actions="{ row: user }">
                        <Link :href="route('permissions.edit', user.id)" class="text-indigo-600 hover:text-indigo-900">{{ t('permissionsAdmin.manageLink') }}</Link>
                    </template>
                </DataTable>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
