<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import { Head, Link } from '@inertiajs/vue3';

defineProps({
    entries: Array,
});

// Specialties whose form has been rebuilt as a faithful port of the
// original app's own case sheet (real sections, labels, option sets and
// per-tooth charts) rather than the generic column-driven form.
const TAILORED = ['periodontal-charts', 'complete-denture-records', 'prosthodontics-records', 'oral-medicine-charts', 'prevention-records', 'orthodontics-records', 'surgeries', 'surgery-follow-ups', 'surgery-images', 'surgery-medications', 'treatment-plans', 'treatment-materials', 'dental-charts'];
</script>

<template>
    <Head title="Clinical Records" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">Clinical Records</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-4 sm:px-6 lg:px-8">
                <p class="text-sm text-gray-600">
                    Specialty case-sheet records (periodontal, prosthodontics, surgery, etc.).
                    Forms marked <span class="rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800">Full case sheet</span>
                    are faithful ports of the original app's own form, including its
                    sections and per-tooth charts. The rest still use the generic
                    field-driven form while they are ported one by one.
                </p>

                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    <Link
                        v-for="entry in entries"
                        :key="entry.route"
                        :href="route(`${entry.route}.index`)"
                        class="block rounded-lg bg-white p-6 shadow-sm transition hover:shadow-md"
                    >
                        <div class="flex items-start justify-between gap-2">
                            <div class="font-medium text-gray-900">{{ entry.title }}</div>
                            <span v-if="TAILORED.includes(entry.route)" class="shrink-0 rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800">
                                Full case sheet
                            </span>
                        </div>
                        <div class="mt-1 text-sm text-indigo-600">Manage &rarr;</div>
                    </Link>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
