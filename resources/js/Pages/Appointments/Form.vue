<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    appointment: Object,
    patientRegistrations: Array,
    doctorUsers: Array,
    tasks: Array,
});

const isEdit = computed(() => props.appointment !== null);
const a = props.appointment ?? {};

const form = useForm({
    full_name: a.full_name ?? '',
    patient_registration_id: a.patient_registration_id ?? '',
    doctor_id: a.doctor_id ?? '',
    task_id: a.task_id ?? '',
    appointment_date: a.appointment_date ?? '',
    confirmed_by_accountant: a.confirmed_by_accountant ?? false,
    pinned: a.pinned ?? false,
});

// The server always overwrites full_name from the chosen registration's
// name on save anyway (App\Services\AppointmentPatientSync::refresh()) —
// this watcher just keeps the visible field from looking wrong/stale
// between picking a patient and actually submitting the form.
watch(
    () => form.patient_registration_id,
    (id) => {
        const patient = props.patientRegistrations.find((p) => p.id === id);
        if (patient) {
            form.full_name = patient.name;
        }
    },
);

// Mirrors PatientRegistrations/Create.vue's own taskFilter/filteredTasks
// — this task <select> had no filter at all, unusable once there are
// more than a handful of tasks.
const taskFilter = ref('');
const filteredTasks = computed(() =>
    taskFilter.value.trim() ? props.tasks.filter((t) => t.title.includes(taskFilter.value.trim())) : props.tasks,
);

const submit = () => {
    if (isEdit.value) {
        form.put(route('appointments.update', props.appointment.id));
    } else {
        form.post(route('appointments.store'));
    }
};
</script>

<template>
    <Head :title="isEdit ? t('appointments.editTitle') : t('appointments.newAppointment')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                {{ isEdit ? t('appointments.editTitle') : t('appointments.newAppointment') }}
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="full_name" :value="t('appointments.fullName')" />
                            <TextInput id="full_name" v-model="form.full_name" type="text" class="mt-1 block w-full" required autofocus />
                            <InputError class="mt-2" :message="form.errors.full_name" />
                        </div>

                        <div>
                            <InputLabel for="patient_registration_id" :value="t('appointments.registeredPatient')" />
                            <select
                                id="patient_registration_id"
                                v-model="form.patient_registration_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                :required="!isEdit"
                            >
                                <option value="" disabled>{{ t('appointments.chooseRegisteredPatient') }}</option>
                                <option v-for="p in patientRegistrations" :key="p.id" :value="p.id">{{ p.name }} — {{ p.phone }}</option>
                            </select>
                            <p v-if="isEdit && !a.patient_registration_id" class="mt-1 text-xs text-gray-500">
                                {{ t('appointments.legacyPatientNote') }}
                            </p>
                            <InputError class="mt-2" :message="form.errors.patient_registration_id" />
                        </div>

                        <div>
                            <InputLabel for="doctor_id" :value="t('appointments.doctorStaffLabel')" />
                            <select id="doctor_id" v-model="form.doctor_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>{{ t('appointments.selectUser') }}</option>
                                <option v-for="u in doctorUsers" :key="u.id" :value="u.id">{{ u.full_name }} ({{ u.role }})</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.doctor_id" />
                        </div>

                        <div>
                            <InputLabel for="task_id" :value="t('appointments.taskCol')" />
                            <TextInput
                                v-if="tasks.length > 6"
                                v-model="taskFilter"
                                type="text"
                                :placeholder="t('patientReg.filterTasks')"
                                class="mt-1 block w-full"
                            />
                            <select id="task_id" v-model="form.task_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>{{ t('appointments.selectTask') }}</option>
                                <option v-for="taskOption in filteredTasks" :key="taskOption.id" :value="taskOption.id">{{ taskOption.title }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.task_id" />
                        </div>

                        <div>
                            <InputLabel for="appointment_date" :value="t('appointments.dateCol')" />
                            <TextInput id="appointment_date" v-model="form.appointment_date" type="date" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="form.errors.appointment_date" />
                        </div>

                        <div class="flex items-center gap-6">
                            <label class="flex items-center gap-2 text-sm text-gray-700">
                                <input type="checkbox" v-model="form.confirmed_by_accountant" class="rounded border-gray-300 text-indigo-600 shadow-sm focus:ring-indigo-500" />
                                {{ t('appointments.confirmedByAccountant') }}
                            </label>
                            <label class="flex items-center gap-2 text-sm text-gray-700">
                                <input type="checkbox" v-model="form.pinned" class="rounded border-gray-300 text-indigo-600 shadow-sm focus:ring-indigo-500" />
                                {{ t('appointments.pinned') }}
                            </label>
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">{{ isEdit ? t('appointments.updateAppointment') : t('appointments.saveAppointment') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
