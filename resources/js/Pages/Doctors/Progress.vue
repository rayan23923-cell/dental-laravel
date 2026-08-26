<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';

const props = defineProps({
    doctor: Object,
    stats: Object,
    tasks: Array,
});

const page = usePage();

const statusLabel = (status) => ({
    pending: 'Pending',
    assigned: 'In progress',
    completed: 'Completed',
}[status] ?? status);

const statusColor = (status) => ({
    pending: 'bg-gray-100 text-gray-700',
    assigned: 'bg-yellow-100 text-yellow-800',
    completed: 'bg-green-100 text-green-800',
}[status] ?? 'bg-gray-100 text-gray-700');

const toggle = (instance) => {
    router.put(
        route('task-instances.update', instance.id),
        { status: instance.status === 'completed' ? 'assigned' : 'completed' },
        { preserveScroll: true }
    );
};

const completionPct = (completed, total) => (total > 0 ? Math.round((completed / total) * 100) : 0);
</script>

<template>
    <Head :title="`${doctor.name} — Progress`" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ doctor.name }} — Task Progress</h2>
                <Link :href="route('doctors.index')" class="text-sm text-indigo-600 hover:underline">Back to doctors</Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-6 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <dl class="grid grid-cols-2 gap-4 text-sm sm:grid-cols-4">
                        <div>
                            <dt class="text-gray-500">Username</dt>
                            <dd class="font-medium text-gray-900">{{ doctor.username }}</dd>
                        </div>
                        <div>
                            <dt class="text-gray-500">Stage</dt>
                            <dd class="font-medium text-gray-900">{{ doctor.stage ?? '—' }}</dd>
                        </div>
                        <div>
                            <dt class="text-gray-500">Education Type</dt>
                            <dd class="font-medium text-gray-900">{{ doctor.education_type ?? '—' }}</dd>
                        </div>
                        <div>
                            <dt class="text-gray-500">Group</dt>
                            <dd class="font-medium text-gray-900">{{ doctor.group ?? '—' }}</dd>
                        </div>
                    </dl>
                </div>

                <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
                    <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                        <div class="text-2xl font-semibold text-gray-900">{{ stats.total }}</div>
                        <div class="text-xs text-gray-500">Total cases</div>
                    </div>
                    <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                        <div class="text-2xl font-semibold text-green-700">{{ stats.completed }}</div>
                        <div class="text-xs text-gray-500">Completed</div>
                    </div>
                    <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                        <div class="text-2xl font-semibold text-yellow-700">{{ stats.assigned }}</div>
                        <div class="text-xs text-gray-500">In progress</div>
                    </div>
                    <div class="rounded-lg bg-white p-4 text-center shadow-sm">
                        <div class="text-2xl font-semibold text-gray-600">{{ stats.pending }}</div>
                        <div class="text-xs text-gray-500">Pending</div>
                    </div>
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <div class="flex items-center justify-between text-sm text-gray-600">
                        <span>Overall progress</span>
                        <span>{{ stats.completed }} of {{ stats.total }} completed</span>
                    </div>
                    <div class="mt-2 h-4 overflow-hidden rounded-full bg-gray-100">
                        <div
                            class="h-full rounded-full bg-green-500 transition-all"
                            :style="{ width: completionPct(stats.completed, stats.total) + '%' }"
                        ></div>
                    </div>
                </div>

                <div v-if="tasks.length === 0" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                    No tasks assigned to this doctor yet.
                </div>

                <div v-for="task in tasks" :key="task.task_id" class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <div class="border-b border-gray-200 p-4">
                        <div class="flex items-center justify-between">
                            <h3 class="font-medium text-gray-900">{{ task.title }}</h3>
                            <span class="rounded-full bg-indigo-100 px-2 py-1 text-xs font-medium text-indigo-700">{{ task.instances.length }} case(s)</span>
                        </div>
                        <div class="mt-1 flex flex-wrap gap-x-4 text-xs text-gray-500">
                            <span>Department: {{ task.department ?? '—' }}</span>
                            <span>Stage: {{ task.stage ?? '—' }}</span>
                            <span>Education type: {{ task.education_type ?? '—' }}</span>
                            <span>Required: {{ task.required_count }}</span>
                            <span class="font-medium text-amber-700">Remaining: {{ task.remaining }}</span>
                        </div>
                        <div class="mt-2 h-2 overflow-hidden rounded-full bg-gray-100">
                            <div
                                class="h-full rounded-full bg-green-500"
                                :style="{ width: completionPct(task.completed, task.instances.length) + '%' }"
                            ></div>
                        </div>
                    </div>
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-2 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Status</th>
                                <th class="px-6 py-2 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Assigned</th>
                                <th class="px-6 py-2 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Completed</th>
                                <th class="px-6 py-2 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Notes</th>
                                <th class="px-6 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="instance in task.instances" :key="instance.id">
                                <td class="whitespace-nowrap px-6 py-3 text-sm">
                                    <span class="rounded-full px-2 py-1 text-xs font-medium" :class="statusColor(instance.status)">{{ statusLabel(instance.status) }}</span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-3 text-sm text-gray-500">{{ instance.assigned_date ? new Date(instance.assigned_date).toLocaleString() : '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-3 text-sm text-gray-500">{{ instance.completion_date ? new Date(instance.completion_date).toLocaleString() : '—' }}</td>
                                <td class="px-6 py-3 text-sm text-gray-500">{{ instance.notes ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-3 text-right text-sm">
                                    <button v-if="instance.status === 'assigned'" @click="toggle(instance)" class="text-green-600 hover:text-green-900">
                                        Mark Complete
                                    </button>
                                    <button v-else-if="instance.status === 'completed'" @click="toggle(instance)" class="text-gray-500 hover:text-gray-800">
                                        Undo Complete
                                    </button>
                                    <span v-else class="text-gray-400">—</span>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
