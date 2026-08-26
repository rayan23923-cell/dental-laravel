<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { computed } from 'vue';

const props = defineProps({
    resource: String,
    title: String,
    records: Object,
    titleField: String,
});

const page = usePage();

// Both guards reach these listings, and AuthenticatedLayout dereferences
// auth.user.role unguarded — see Specialty/SectionedForm.vue.
const isDoctor = computed(() => !!page.props.auth?.doctor);
const Layout = computed(() => (isDoctor.value ? DoctorLayout : AuthenticatedLayout));

const destroy = (record) => {
    if (confirm(`Delete this ${props.title.toLowerCase()} record?`)) {
        router.delete(route(`${props.resource}.destroy`, record.id));
    }
};

const recordLabel = (record) => record[props.titleField] || `#${record.id}`;
</script>

<template>
    <Head :title="title" />

    <component :is="Layout">
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ title }}</h2>
                <!-- Only the owning doctor may create or delete a case sheet;
                     staff are view-only, as in the original. -->
                <Link v-if="isDoctor" :href="route(`${resource}.create`)">
                    <PrimaryButton>Add Record</PrimaryButton>
                </Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Record</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Doctor</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="record in records.data" :key="record.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">
                                    <Link :href="route(`${resource}.show`, record.id)" class="hover:underline">{{ recordLabel(record) }}</Link>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ record.doctor?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <Link :href="route(`${resource}.edit`, record.id)" class="text-indigo-600 hover:text-indigo-900">
                                        {{ isDoctor ? 'Edit' : 'View' }}
                                    </Link>
                                    <button v-if="isDoctor" @click="destroy(record)" class="ml-4 text-red-600 hover:text-red-900">Delete</button>
                                </td>
                            </tr>
                            <tr v-if="records.data.length === 0">
                                <td colspan="3" class="px-6 py-8 text-center text-sm text-gray-500">No records yet.</td>
                            </tr>
                        </tbody>
                    </table>

                    <div class="flex justify-between border-t border-gray-200 p-4">
                        <Link
                            v-for="link in records.links"
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
    </component>
</template>
