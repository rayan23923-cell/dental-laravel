<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { ref, watch } from 'vue';

const props = defineProps({
    appointments: Object,
    filters: Object,
});

const page = usePage();
const search = ref(props.filters.search ?? '');

watch(search, (value) => {
    router.get(route('appointments.index'), { search: value }, { preserveState: true, replace: true });
});

const destroy = (appointment) => {
    if (confirm(`Delete the appointment for "${appointment.full_name}"?`)) {
        router.delete(route('appointments.destroy', appointment.id));
    }
};

const togglePinned = (appointment) => {
    router.put(route('appointments.toggle-pinned', appointment.id), {}, { preserveScroll: true });
};

const paidTotal = (appointment) => appointment.payments.reduce((sum, p) => sum + Number(p.amount), 0);
</script>

<template>
    <Head title="Appointments" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">Appointments</h2>
                <Link :href="route('appointments.create')">
                    <PrimaryButton>New Appointment</PrimaryButton>
                </Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-6xl space-y-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <div class="border-b border-gray-200 p-4">
                        <TextInput v-model="search" type="text" placeholder="Search by name..." class="w-full max-w-sm" />
                    </div>

                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Patient</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Doctor</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Task</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Date</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Paid</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Status</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="appointment in appointments.data" :key="appointment.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ appointment.full_name }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ appointment.doctor?.full_name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ appointment.task?.title ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ appointment.appointment_date }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ paidTotal(appointment).toFixed(2) }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <span v-if="appointment.confirmed_by_accountant" class="rounded-full bg-green-100 px-2 py-1 text-xs text-green-800">Confirmed</span>
                                    <span v-else class="rounded-full bg-gray-100 px-2 py-1 text-xs text-gray-600">Pending</span>
                                    <span v-if="appointment.pinned" class="ml-1 rounded-full bg-amber-100 px-2 py-1 text-xs text-amber-800">Pinned</span>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <button @click="togglePinned(appointment)" class="text-amber-600 hover:text-amber-900">
                                        {{ appointment.pinned ? 'Unpin' : 'Pin' }}
                                    </button>
                                    <Link :href="route('appointments.edit', appointment.id)" class="ml-4 text-indigo-600 hover:text-indigo-900">Edit</Link>
                                    <button @click="destroy(appointment)" class="ml-4 text-red-600 hover:text-red-900">Delete</button>
                                </td>
                            </tr>
                            <tr v-if="appointments.data.length === 0">
                                <td colspan="7" class="px-6 py-8 text-center text-sm text-gray-500">No appointments yet.</td>
                            </tr>
                        </tbody>
                    </table>

                    <div class="flex justify-between border-t border-gray-200 p-4">
                        <Link
                            v-for="link in appointments.links"
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
