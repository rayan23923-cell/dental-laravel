<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';

defineProps({
    assignments: Array,
    users: Array,
    departments: Array,
    stages: Array,
});

const page = usePage();

const form = useForm({
    user_id: '',
    department_id: '',
    stage_id: '',
    role_type: 'senior',
    notes: '',
});

const assign = () => {
    form.post(route('department-roles.store'), {
        onSuccess: () => form.reset('user_id', 'department_id', 'stage_id', 'notes'),
    });
};

const toggle = (assignment) => {
    router.put(route('department-roles.toggle', assignment.id), {}, { preserveScroll: true });
};

const remove = (assignment) => {
    if (confirm('Remove this role assignment?')) {
        router.delete(route('department-roles.destroy', assignment.id), { preserveScroll: true });
    }
};
</script>

<template>
    <Head title="Department Roles" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">Department Roles (Senior / HR)</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-4 text-sm font-medium text-gray-900">Assign a Role</h3>
                    <form @submit.prevent="assign" class="grid grid-cols-1 gap-4 sm:grid-cols-5">
                        <div>
                            <select v-model="form.user_id" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>User</option>
                                <option v-for="u in users" :key="u.id" :value="u.id">{{ u.full_name }}</option>
                            </select>
                            <InputError :message="form.errors.user_id" />
                        </div>
                        <div>
                            <select v-model="form.department_id" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>Department</option>
                                <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
                            </select>
                            <InputError :message="form.errors.department_id" />
                        </div>
                        <div>
                            <select v-model="form.stage_id" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>Stage</option>
                                <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                            <InputError :message="form.errors.stage_id" />
                        </div>
                        <div>
                            <select v-model="form.role_type" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="senior">Senior</option>
                                <option value="hr">HR</option>
                            </select>
                        </div>
                        <PrimaryButton :disabled="form.processing">Assign</PrimaryButton>
                    </form>
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">User</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Department</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Stage</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Role</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Status</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="a in assignments" :key="a.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ a.user?.full_name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ a.department?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ a.stage?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ a.role_type }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <span class="rounded-full px-2 py-1 text-xs font-medium" :class="a.status === 'active' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-600'">{{ a.status }}</span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <button @click="toggle(a)" class="text-indigo-600 hover:text-indigo-900">
                                        {{ a.status === 'active' ? 'Deactivate' : 'Reactivate' }}
                                    </button>
                                    <button @click="remove(a)" class="ml-4 text-red-600 hover:text-red-900">Remove</button>
                                </td>
                            </tr>
                            <tr v-if="assignments.length === 0">
                                <td colspan="6" class="px-6 py-8 text-center text-sm text-gray-500">No role assignments yet.</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
