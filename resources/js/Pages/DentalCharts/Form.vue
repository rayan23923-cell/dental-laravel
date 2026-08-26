<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import ToothSelector from '@/Components/ToothSelector.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { computed } from 'vue';

const props = defineProps({
    doctors: Array,
    taskInstance: Object,
    chart: Object,
});

const isEdit = computed(() => props.chart !== null);
const c = props.chart ?? {};

const form = useForm({
    patient_id: c.patient_id ?? '',
    patient_phone: c.patient_phone ?? '',
    patient_age: c.patient_age ?? '',
    patient_sex: c.patient_sex ?? '',
    patient_address: c.patient_address ?? '',
    patient_occupation: c.patient_occupation ?? '',
    doctor_id: c.doctor_id ?? props.taskInstance?.doctor_id ?? '',
    task_instances_id: c.task_instances_id ?? props.taskInstance?.id ?? null,
    chart_type: c.chart_type ?? 'permanent',
    visit_date: c.visit_date ? c.visit_date.substring(0, 10) : new Date().toISOString().substring(0, 10),
    chief_complaint: c.chief_complaint ?? '',
    history_of_complaint: c.history_of_complaint ?? '',
    oral_hygiene: c.oral_hygiene ?? '',
    periodontal_condition: c.periodontal_condition ?? '',
    non_vital_teeth: c.non_vital_teeth ?? '',
    missing_teeth: c.missing_teeth ?? '',
    crown_bridge_teeth: c.crown_bridge_teeth ?? '',
    tooth_data: c.tooth_data ?? [],
    treatment_plan_date: c.treatment_plan_date ?? '',
    treatment_plan_notes: c.treatment_plan_notes ?? '',
    senior_doctor_name: c.senior_doctor_name ?? '',
    notes: c.notes ?? '',
});

const submit = () => {
    if (isEdit.value) {
        form.put(route('dental-charts.update', props.chart.id));
    } else {
        form.post(route('dental-charts.store'));
    }
};
</script>

<template>
    <Head :title="isEdit ? 'Edit Dental Chart' : 'New Dental Chart'" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                {{ isEdit ? 'Edit Dental Chart' : 'New Dental Chart' }}
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-6 sm:px-6 lg:px-8">
                <form @submit.prevent="submit" class="space-y-6">
                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-900">Patient</h3>
                        <div class="grid grid-cols-2 gap-4">
                            <div>
                                <InputLabel for="patient_id" value="Patient Name" />
                                <TextInput id="patient_id" v-model="form.patient_id" type="text" class="mt-1 block w-full" required />
                                <InputError class="mt-2" :message="form.errors.patient_id" />
                            </div>
                            <div>
                                <InputLabel for="patient_phone" value="Phone" />
                                <TextInput id="patient_phone" v-model="form.patient_phone" type="text" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="patient_age" value="Age" />
                                <TextInput id="patient_age" v-model="form.patient_age" type="number" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="patient_sex" value="Sex" />
                                <select id="patient_sex" v-model="form.patient_sex" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                    <option value="">—</option>
                                    <option value="male">Male</option>
                                    <option value="female">Female</option>
                                </select>
                            </div>
                            <div>
                                <InputLabel for="patient_address" value="Address" />
                                <TextInput id="patient_address" v-model="form.patient_address" type="text" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="patient_occupation" value="Occupation" />
                                <TextInput id="patient_occupation" v-model="form.patient_occupation" type="text" class="mt-1 block w-full" />
                            </div>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-900">Visit</h3>
                        <div class="grid grid-cols-3 gap-4">
                            <div>
                                <InputLabel for="doctor_id" value="Doctor" />
                                <select id="doctor_id" v-model="form.doctor_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                    <option value="" disabled>Select a doctor</option>
                                    <option v-for="d in doctors" :key="d.id" :value="d.id">{{ d.name }}</option>
                                </select>
                                <InputError class="mt-2" :message="form.errors.doctor_id" />
                            </div>
                            <div>
                                <InputLabel for="chart_type" value="Chart Type" />
                                <select id="chart_type" v-model="form.chart_type" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                    <option value="permanent">Permanent</option>
                                    <option value="primary">Primary</option>
                                </select>
                            </div>
                            <div>
                                <InputLabel for="visit_date" value="Visit Date" />
                                <TextInput id="visit_date" v-model="form.visit_date" type="date" class="mt-1 block w-full" />
                            </div>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-900">History &amp; Examination</h3>
                        <div class="space-y-4">
                            <div>
                                <InputLabel for="chief_complaint" value="Chief Complaint" />
                                <textarea id="chief_complaint" v-model="form.chief_complaint" rows="2" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                            </div>
                            <div>
                                <InputLabel for="history_of_complaint" value="History of Complaint" />
                                <textarea id="history_of_complaint" v-model="form.history_of_complaint" rows="2" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                            </div>
                            <div>
                                <InputLabel for="oral_hygiene" value="Oral Hygiene" />
                                <TextInput id="oral_hygiene" v-model="form.oral_hygiene" type="text" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="periodontal_condition" value="Periodontal Condition" />
                                <TextInput id="periodontal_condition" v-model="form.periodontal_condition" type="text" class="mt-1 block w-full" />
                            </div>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-900">Tooth Chart</h3>
                        <ToothSelector v-model="form.tooth_data" :chart-type="form.chart_type" />

                        <div class="mt-6 grid grid-cols-3 gap-4">
                            <div>
                                <InputLabel for="non_vital_teeth" value="Non-Vital Teeth" />
                                <TextInput id="non_vital_teeth" v-model="form.non_vital_teeth" type="text" placeholder="e.g. 16, 26" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="missing_teeth" value="Missing Teeth" />
                                <TextInput id="missing_teeth" v-model="form.missing_teeth" type="text" placeholder="e.g. 18, 48" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="crown_bridge_teeth" value="Crown &amp; Bridge Teeth" />
                                <TextInput id="crown_bridge_teeth" v-model="form.crown_bridge_teeth" type="text" class="mt-1 block w-full" />
                            </div>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-900">Treatment Plan</h3>
                        <div class="grid grid-cols-2 gap-4">
                            <div>
                                <InputLabel for="treatment_plan_date" value="Plan Date" />
                                <TextInput id="treatment_plan_date" v-model="form.treatment_plan_date" type="date" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="senior_doctor_name" value="Senior Doctor" />
                                <TextInput id="senior_doctor_name" v-model="form.senior_doctor_name" type="text" class="mt-1 block w-full" />
                            </div>
                        </div>
                        <div class="mt-4">
                            <InputLabel for="treatment_plan_notes" value="Plan Notes" />
                            <textarea id="treatment_plan_notes" v-model="form.treatment_plan_notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                        </div>
                        <div class="mt-4">
                            <InputLabel for="notes" value="General Notes" />
                            <textarea id="notes" v-model="form.notes" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                        </div>
                    </div>

                    <div class="flex justify-end">
                        <PrimaryButton :disabled="form.processing">{{ isEdit ? 'Update Chart' : 'Save Chart' }}</PrimaryButton>
                    </div>
                </form>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
