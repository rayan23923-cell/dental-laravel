<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import { Head, Link } from '@inertiajs/vue3';

const props = defineProps({
    resource: String,
    title: String,
    fields: Array,
    record: Object,
});

const displayValue = (field) => {
    const value = props.record[field.key];
    if (value === null || value === undefined || value === '') return '—';
    if (field.type === 'boolean') return value == 1 ? 'Yes' : 'No';
    return value;
};
</script>

<template>
    <Head :title="title" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ title }}</h2>
                <Link :href="route(`${resource}.edit`, record.id)" class="text-sm text-indigo-600 hover:underline">Edit</Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl sm:px-6 lg:px-8">
                <div v-if="record.doctor" class="mb-4 overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <dt class="text-sm text-gray-500">Doctor</dt>
                    <dd class="font-medium text-gray-900">{{ record.doctor.name }}</dd>
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <dl class="grid grid-cols-1 gap-6 sm:grid-cols-2">
                        <div v-for="f in fields" :key="f.key">
                            <dt class="text-sm text-gray-500">{{ f.label }}</dt>
                            <dd class="mt-1 whitespace-pre-wrap break-words text-sm font-medium text-gray-900">{{ displayValue(f) }}</dd>
                        </div>
                    </dl>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
