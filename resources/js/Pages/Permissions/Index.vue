<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import { Head, Link, usePage } from '@inertiajs/vue3';

defineProps({
    users: Array,
});

const page = usePage();
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

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Name</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Role</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="user in users" :key="user.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ user.full_name }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ user.role }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <Link :href="route('permissions.edit', user.id)" class="text-indigo-600 hover:text-indigo-900">Manage</Link>
                                </td>
                            </tr>
                            <tr v-if="users.length === 0">
                                <td colspan="3" class="px-6 py-8 text-center text-sm text-gray-500">No staff users yet.</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
