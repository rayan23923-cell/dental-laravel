<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    days: Array,
    services: Array,
    tasks: Array,
});

const page = usePage();

// Filters which day checkboxes are *shown* when picking days for a new
// service — selections already made (`serviceForm.day_ids`) aren't
// touched by this, only visibility.
const dayFilter = ref('');
const filteredDays = computed(() =>
    dayFilter.value.trim() ? props.days.filter((d) => d.name.includes(dayFilter.value.trim())) : props.days,
);

const dayForm = useForm({ name: '', sort_order: 0 });
const submitDay = () => {
    dayForm.post(route('register-days.store'), { preserveScroll: true, onSuccess: () => dayForm.reset() });
};
const deleteDay = (day) => {
    if (confirm(t('patientReg.deleteDayConfirm', { name: day.name }))) {
        dayForm.delete(route('register-days.destroy', day.id), { preserveScroll: true });
    }
};

const serviceForm = useForm({ name: '', day_ids: [] });
const submitService = () => {
    serviceForm.post(route('register-services.store'), { preserveScroll: true, onSuccess: () => serviceForm.reset() });
};
const deleteService = (service) => {
    if (confirm(t('patientReg.deleteServiceConfirm', { name: service.name }))) {
        serviceForm.delete(route('register-services.destroy', service.id), { preserveScroll: true });
    }
};

const dayNames = (service) => {
    const ids = new Set((service.days || []).map((d) => d.id));
    return props.days.filter((d) => ids.has(d.id)).map((d) => d.name).join(t('patientReg.listSeparator')) || '—';
};

// --- Tasks ("التشخيص") — day-governed diagnosis. Tasks themselves are
// created/edited in Tasks admin, not here; this only syncs which days
// each already-existing task is offered on (see
// TaskRegisterDaysController's docblock). Unlike services (create-time
// sync only), each row here has its own editable day set, saved
// individually via "حفظ" — tasks already exist, there's no create form.
const taskFilter = ref('');
const filteredTasks = computed(() =>
    taskFilter.value.trim() ? props.tasks.filter((t) => t.title.includes(taskFilter.value.trim())) : props.tasks,
);

const taskDayIds = ref(Object.fromEntries(props.tasks.map((t) => [t.id, (t.days || []).map((d) => d.id)])));
const taskSaving = ref({});

const saveTaskDays = (task) => {
    taskSaving.value[task.id] = true;
    router.put(
        route('tasks.register-days.update', task.id),
        { day_ids: taskDayIds.value[task.id] },
        { preserveScroll: true, onFinish: () => { taskSaving.value[task.id] = false; } },
    );
};
</script>

<template>
    <Head :title="t('nav.registrationSettings')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('patientReg.settingsTitle') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-6 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- Days -->
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-4 font-semibold text-gray-800">{{ t('patientReg.daysHeading') }}</h3>
                    <form @submit.prevent="submitDay" class="mb-4 flex items-end gap-3">
                        <div class="flex-1">
                            <InputLabel for="day_name" :value="t('patientReg.dayNameLabel')" />
                            <TextInput id="day_name" v-model="dayForm.name" type="text" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="dayForm.errors.name" />
                        </div>
                        <PrimaryButton :disabled="dayForm.processing">{{ t('patientReg.addDay') }}</PrimaryButton>
                    </form>
                    <ul class="divide-y divide-gray-200">
                        <li v-for="day in days" :key="day.id" class="flex items-center justify-between py-2">
                            <span>{{ day.name }}</span>
                            <SecondaryButton @click="deleteDay(day)">{{ t('common.delete') }}</SecondaryButton>
                        </li>
                        <li v-if="days.length === 0" class="py-4 text-center text-sm text-gray-500">{{ t('patientReg.noDaysYet') }}</li>
                    </ul>
                </div>

                <!-- Services -->
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-4 font-semibold text-gray-800">{{ t('patientReg.servicesHeading') }}</h3>
                    <form @submit.prevent="submitService" class="mb-6 space-y-4">
                        <div>
                            <InputLabel for="service_name" :value="t('patientReg.serviceNameLabel')" />
                            <TextInput id="service_name" v-model="serviceForm.name" type="text" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="serviceForm.errors.name" />
                        </div>
                        <div>
                            <InputLabel :value="t('patientReg.availableDaysLabel')" />
                            <TextInput
                                v-if="days.length > 8"
                                v-model="dayFilter"
                                type="text"
                                :placeholder="t('patientReg.filterDays')"
                                class="mt-2 block w-full sm:w-64"
                            />
                            <div class="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
                                <label v-for="day in filteredDays" :key="day.id" class="flex items-center gap-2 text-sm text-gray-700">
                                    <input type="checkbox" :value="day.id" v-model="serviceForm.day_ids" class="rounded border-gray-300" />
                                    {{ day.name }}
                                </label>
                            </div>
                            <InputError class="mt-2" :message="serviceForm.errors.day_ids" />
                        </div>
                        <PrimaryButton :disabled="serviceForm.processing">{{ t('patientReg.addService') }}</PrimaryButton>
                    </form>

                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.serviceLabel') }}</th>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.daysCol') }}</th>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patients.actionsCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="service in services" :key="service.id">
                                <td class="whitespace-nowrap px-4 py-3 text-sm font-medium text-gray-900">{{ service.name }}</td>
                                <td class="px-4 py-3 text-sm text-gray-500">{{ dayNames(service) }}</td>
                                <td class="whitespace-nowrap px-4 py-3 text-sm">
                                    <SecondaryButton @click="deleteService(service)">{{ t('common.delete') }}</SecondaryButton>
                                </td>
                            </tr>
                            <tr v-if="services.length === 0">
                                <td colspan="3" class="px-4 py-8 text-center text-sm text-gray-500">{{ t('patientReg.noServicesYet') }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>

                <!-- Tasks ("التشخيص") -->
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <h3 class="mb-1 font-semibold text-gray-800">{{ t('patientReg.diagnosis') }}</h3>
                    <p class="mb-4 text-sm text-gray-500">
                        {{ t('patientReg.diagnosisDesc') }}
                    </p>
                    <TextInput
                        v-if="tasks.length > 6"
                        v-model="taskFilter"
                        type="text"
                        :placeholder="t('patientReg.filterDiagnosis')"
                        class="mb-4 block w-full sm:w-64"
                    />
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.diagnosis') }}</th>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.daysCol') }}</th>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patients.actionsCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="task in filteredTasks" :key="task.id">
                                <td class="whitespace-nowrap px-4 py-3 text-sm font-medium text-gray-900">{{ task.title }}</td>
                                <td class="px-4 py-3">
                                    <div class="flex flex-wrap gap-2">
                                        <label v-for="day in days" :key="day.id" class="flex items-center gap-1 text-sm text-gray-700">
                                            <input type="checkbox" :value="day.id" v-model="taskDayIds[task.id]" class="rounded border-gray-300" />
                                            {{ day.name }}
                                        </label>
                                    </div>
                                </td>
                                <td class="whitespace-nowrap px-4 py-3 text-sm">
                                    <SecondaryButton :disabled="taskSaving[task.id]" @click="saveTaskDays(task)">{{ t('profile.save') }}</SecondaryButton>
                                </td>
                            </tr>
                            <tr v-if="filteredTasks.length === 0">
                                <td colspan="3" class="px-4 py-8 text-center text-sm text-gray-500">{{ t('patientReg.noMatchingResults') }}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
