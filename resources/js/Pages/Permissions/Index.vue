<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import DataTable from '@/Components/DataTable.vue';
import { Head, Link, usePage } from '@inertiajs/vue3';

defineProps({
    users: Array,
});

const page = usePage();

const columns = [
    { key: 'full_name', label: 'Name', sortable: true },
    { key: 'role', label: 'Role', sortable: true },
    { key: 'actions', label: 'Actions', align: 'right' },
];
</script>

<template>
    <Head title="User Permissions" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">User Permissions</h2>
                <div class="flex items-center gap-4">
                    <Link :href="route('users.create')" class="text-sm text-indigo-600 hover:underline">+ Add User</Link>
                    <Link :href="route('department-roles.index')" class="text-sm text-indigo-600 hover:underline">Department Roles (Senior/HR) &rarr;</Link>
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
                    Grants layer on top of each user's role — <code>super_admin</code> always
                    has every permission. See <code>App\Services\PermissionManager</code>.
                </p>

                <DataTable
                    :columns="columns"
                    :rows="users"
                    searchable
                    search-placeholder="ابحث بالاسم أو الدور..."
                    empty-text="No staff users yet."
                >
                    <template #cell-actions="{ row: user }">
                        <Link :href="route('permissions.edit', user.id)" class="text-indigo-600 hover:text-indigo-900">Manage</Link>
                    </template>
                </DataTable>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
