<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    charts: Object,
    filters: Object,
});

const page = usePage();
const search = ref(props.filters.search ?? '');

watch(search, (value) => {
    router.get(route('dental-charts.index'), { search: value }, { preserveState: true, replace: true });
});

const destroy = (chart) => {
    if (confirm(t('dentalCharts.deleteConfirm', { name: chart.patient_id }))) {
        router.delete(route('dental-charts.destroy', chart.id));
    }
};
</script>

<template>
    <Head :title="t('dentalCharts.pageTitle')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('dentalCharts.pageTitle') }}</h2>
                <Link :href="route('dental-charts.create')">
                    <PrimaryButton>{{ t('dentalCharts.newChart') }}</PrimaryButton>
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
                        <TextInput v-model="search" type="text" :placeholder="t('dentalCharts.searchPlaceholder')" class="w-full max-w-sm" />
                    </div>

                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('dentalCharts.patientCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('dentalCharts.doctorCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('dentalCharts.typeCol') }}</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('dentalCharts.visitDateCol') }}</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('dentalCharts.actionsCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="chart in charts.data" :key="chart.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">
                                    <Link :href="route('dental-charts.show', chart.id)" class="hover:underline">{{ chart.patient_id }}</Link>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ chart.doctor?.name ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ chart.chart_type }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ new Date(chart.visit_date).toLocaleDateString() }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <Link :href="route('dental-charts.edit', chart.id)" class="text-indigo-600 hover:text-indigo-900">{{ t('dentalCharts.editAction') }}</Link>
                                    <button @click="destroy(chart)" class="ml-4 text-red-600 hover:text-red-900">{{ t('dentalCharts.deleteAction') }}</button>
                                </td>
                            </tr>
                            <tr v-if="charts.data.length === 0">
                                <td colspan="5" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('dentalCharts.emptyList') }}</td>
                            </tr>
                        </tbody>
                    </table>

                    <div class="flex justify-between border-t border-gray-200 p-4">
                        <Link
                            v-for="link in charts.links"
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
