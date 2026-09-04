<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import { Head, Link } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    chart: Object,
});
</script>

<template>
    <Head :title="t('dentalCharts.showTitle', { name: chart.patient_id })" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">
                    {{ t('dentalCharts.showTitle', { name: chart.patient_id }) }}
                </h2>
                <Link :href="route('dental-charts.edit', chart.id)" class="text-sm text-indigo-600 hover:underline">{{ t('dentalCharts.editAction') }}</Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-6 sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <dl class="grid grid-cols-2 gap-4 text-sm sm:grid-cols-4">
                        <div><dt class="text-gray-500">{{ t('dentalCharts.phoneLabel') }}</dt><dd class="font-medium text-gray-900">{{ chart.patient_phone ?? '—' }}</dd></div>
                        <div><dt class="text-gray-500">{{ t('dentalCharts.ageLabel') }}</dt><dd class="font-medium text-gray-900">{{ chart.patient_age ?? '—' }}</dd></div>
                        <div><dt class="text-gray-500">{{ t('dentalCharts.sexLabel') }}</dt><dd class="font-medium text-gray-900">{{ chart.patient_sex ?? '—' }}</dd></div>
                        <div><dt class="text-gray-500">{{ t('dentalCharts.doctorCol') }}</dt><dd class="font-medium text-gray-900">{{ chart.doctor?.name ?? '—' }}</dd></div>
                        <div><dt class="text-gray-500">{{ t('dentalCharts.chartTypeLabel') }}</dt><dd class="font-medium text-gray-900">{{ chart.chart_type }}</dd></div>
                        <div><dt class="text-gray-500">{{ t('dentalCharts.visitDateCol') }}</dt><dd class="font-medium text-gray-900">{{ new Date(chart.visit_date).toLocaleDateString() }}</dd></div>
                    </dl>
                </div>

                <div v-if="chart.chief_complaint || chart.history_of_complaint" class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-2 text-sm font-semibold text-gray-900">{{ t('dentalCharts.historyHeading') }}</h3>
                    <p v-if="chart.chief_complaint" class="text-sm text-gray-600"><strong>{{ t('dentalCharts.chiefComplaintLabel') }}</strong> {{ chart.chief_complaint }}</p>
                    <p v-if="chart.history_of_complaint" class="mt-2 text-sm text-gray-600"><strong>{{ t('dentalCharts.historyOfComplaintLabel') }}</strong> {{ chart.history_of_complaint }}</p>
                </div>

                <div v-if="chart.tooth_data?.length" class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-2 text-sm font-semibold text-gray-900">{{ t('dentalCharts.toothFindingsHeading') }}</h3>
                    <div class="flex flex-wrap gap-2">
                        <span
                            v-for="entry in chart.tooth_data"
                            :key="entry.tooth_number"
                            class="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-xs text-amber-900"
                        >
                            #{{ entry.tooth_number }} — {{ entry.condition_type }}
                        </span>
                    </div>
                    <div class="mt-4 grid grid-cols-3 gap-4 text-sm">
                        <div v-if="chart.non_vital_teeth"><span class="text-gray-500">{{ t('dentalCharts.nonVitalLabel') }}</span> {{ chart.non_vital_teeth }}</div>
                        <div v-if="chart.missing_teeth"><span class="text-gray-500">{{ t('dentalCharts.missingLabel') }}</span> {{ chart.missing_teeth }}</div>
                        <div v-if="chart.crown_bridge_teeth"><span class="text-gray-500">{{ t('dentalCharts.crownBridgeLabel') }}</span> {{ chart.crown_bridge_teeth }}</div>
                    </div>
                </div>

                <div v-if="chart.treatment_plan_notes" class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-2 text-sm font-semibold text-gray-900">{{ t('dentalCharts.treatmentPlanHeading') }}</h3>
                    <p class="text-sm text-gray-600">{{ chart.treatment_plan_notes }}</p>
                    <p v-if="chart.senior_doctor_name" class="mt-2 text-xs text-gray-400">{{ t('dentalCharts.reviewedByTemplate', { name: chart.senior_doctor_name }) }}</p>
                </div>

                <div v-if="chart.notes" class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-2 text-sm font-semibold text-gray-900">{{ t('dentalCharts.notesHeading') }}</h3>
                    <p class="text-sm text-gray-600">{{ chart.notes }}</p>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
