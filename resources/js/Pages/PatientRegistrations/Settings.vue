<script setup>
/**
 * Registration settings (2026-10-12): the services the desk registers
 * patients for, each with its price, plus the lab test price and how long
 * a clear lab result stays valid. Days are no longer part of registration.
 * Each service and the lab fee also have a student discount percentage
 * (2026-10-25), taken off for patients registered as eligible.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import ExcelTransferButtons from '@/Components/ExcelTransferButtons.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    services: Array,
    lab: { type: Object, default: () => ({}) },
});

const page = usePage();
const currency = props.lab.clinic_currency ?? '';
const formatPrice = (price) => (price === null || price === undefined ? '—' : `${Number(price).toLocaleString()} ${currency}`.trim());

// Each service's student discount percentage (2026-10-25), 50 by default.
const serviceForm = useForm({ name: '', price: '', student_discount_percent: 50 });
const submitService = () => {
    serviceForm.post(route('register-services.store'), { preserveScroll: true, onSuccess: () => serviceForm.reset() });
};
const deleteService = (service) => {
    if (confirm(t('patientReg.deleteServiceConfirm', { name: service.name }))) {
        router.delete(route('register-services.destroy', service.id), { preserveScroll: true });
    }
};

// Inline edit of an existing service's name and price.
const editing = ref({});
const startEdit = (service) => {
    editing.value = {
        ...editing.value,
        [service.id]: { name: service.name, price: service.price ?? '', student_discount_percent: service.student_discount_percent ?? 50 },
    };
};
const saveEdit = (service) => {
    router.put(route('register-services.update', service.id), editing.value[service.id], {
        preserveScroll: true,
        onSuccess: () => {
            const next = { ...editing.value };
            delete next[service.id];
            editing.value = next;
        },
    });
};

const labForm = useForm({
    lab_fee: props.lab.lab_fee ?? '',
    lab_validity_days: props.lab.lab_validity_days ?? '',
    lab_student_discount_percent: props.lab.lab_student_discount_percent ?? 50,
});
const submitLab = () => {
    labForm.put(route('register-settings.lab'), { preserveScroll: true });
};
</script>

<template>
    <Head :title="t('nav.registrationSettings')" />

    <AuthenticatedLayout>
        <template #header>
            <!-- Chat-list style (2026-10-13, by request): round header button, rounded cards/inputs, icon actions. -->
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('patientReg.settingsTitle') }}</h2>
                <ChatAddButton :label="t('patientReg.registryLink')" icon="list_alt" secondary :href="route('patient-registrations.index')" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-4xl space-y-6 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700 whitespace-pre-line">
                    {{ page.props.flash.error }}
                </div>

                <!-- Services and prices -->
                <div class="overflow-hidden rounded-2xl bg-white p-6 shadow-sm ring-1 ring-gray-100">
                    <div class="mb-4 flex items-center justify-between gap-3">
                        <h3 class="font-semibold text-gray-800">{{ t('patientReg.servicesPricesHeading') }}</h3>
                        <ExcelTransferButtons :export-url="route('register-services.export')" :import-url="route('register-services.import')" />
                    </div>
                    <form @submit.prevent="submitService" class="mb-6 grid grid-cols-1 items-end gap-3 sm:grid-cols-[1fr_10rem_8rem_auto]">
                        <div>
                            <InputLabel for="service_name" :value="t('patientReg.serviceNameLabel')" />
                            <TextInput id="service_name" v-model="serviceForm.name" type="text" class="mt-1 block w-full rounded-xl" required />
                            <InputError class="mt-2" :message="serviceForm.errors.name" />
                        </div>
                        <div>
                            <InputLabel for="service_price" :value="t('patientReg.priceLabel')" />
                            <TextInput id="service_price" v-model="serviceForm.price" type="number" min="0" step="any" dir="ltr" class="mt-1 block w-full rounded-xl" />
                            <InputError class="mt-2" :message="serviceForm.errors.price" />
                        </div>
                        <div>
                            <InputLabel for="service_discount" :value="t('patientReg.studentDiscountLabel')" />
                            <TextInput id="service_discount" v-model="serviceForm.student_discount_percent" type="number" min="0" max="100" step="any" dir="ltr" class="mt-1 block w-full rounded-xl" />
                            <InputError class="mt-2" :message="serviceForm.errors.student_discount_percent" />
                        </div>
                        <PrimaryButton class="rounded-full" :disabled="serviceForm.processing">{{ t('patientReg.addService') }}</PrimaryButton>
                    </form>

                    <div class="overflow-x-auto rounded-xl ring-1 ring-gray-100">
                    <table class="min-w-full divide-y divide-gray-100">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.serviceLabel') }}</th>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.priceLabel') }}</th>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patientReg.studentDiscountLabel') }}</th>
                                <th class="px-4 py-2 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('patients.actionsCol') }}</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-100 bg-white">
                            <tr v-for="service in services" :key="service.id">
                                <template v-if="editing[service.id]">
                                    <td class="px-4 py-2"><TextInput v-model="editing[service.id].name" type="text" class="block w-full rounded-xl" /></td>
                                    <td class="px-4 py-2"><TextInput v-model="editing[service.id].price" type="number" min="0" step="any" dir="ltr" class="block w-full rounded-xl" /></td>
                                    <td class="px-4 py-2"><TextInput v-model="editing[service.id].student_discount_percent" type="number" min="0" max="100" step="any" dir="ltr" class="block w-24 rounded-xl" /></td>
                                    <td class="whitespace-nowrap px-4 py-2 text-sm">
                                        <PrimaryButton class="rounded-full" type="button" @click="saveEdit(service)">{{ t('patientReg.savePrice') }}</PrimaryButton>
                                    </td>
                                </template>
                                <template v-else>
                                    <td class="whitespace-nowrap px-4 py-3 text-sm font-medium text-gray-900">{{ service.name }}</td>
                                    <td class="whitespace-nowrap px-4 py-3 text-sm text-gray-700" dir="ltr" style="text-align: right">{{ formatPrice(service.price) }}</td>
                                    <td class="whitespace-nowrap px-4 py-3 text-sm text-gray-700" dir="ltr" style="text-align: right">{{ Number(service.student_discount_percent ?? 50) }}%</td>
                                    <td class="flex whitespace-nowrap px-4 py-1.5 text-sm">
                                        <ChatAction icon="edit" :label="t('common.edit')" @click="startEdit(service)" />
                                        <ChatAction icon="delete" :label="t('common.delete')" danger @click="deleteService(service)" />
                                    </td>
                                </template>
                            </tr>
                            <tr v-if="services.length === 0">
                                <td colspan="4" class="px-4 py-8 text-center text-sm text-gray-500">{{ t('patientReg.noServicesYet') }}</td>
                            </tr>
                        </tbody>
                    </table>
                    </div>
                </div>

                <!-- Lab -->
                <div class="overflow-hidden rounded-2xl bg-white p-6 shadow-sm ring-1 ring-gray-100">
                    <h3 class="mb-1 font-semibold text-gray-800">{{ t('patientReg.labSettingsHeading') }}</h3>
                    <p class="mb-4 text-sm text-gray-500">{{ t('patientReg.labSettingsDesc') }}</p>
                    <form @submit.prevent="submitLab" class="grid grid-cols-1 items-end gap-3 sm:grid-cols-[1fr_1fr_1fr_auto]">
                        <div>
                            <InputLabel for="lab_fee" :value="t('clinicSettingsAdmin.labFeeLabel')" />
                            <TextInput id="lab_fee" v-model="labForm.lab_fee" type="number" min="0" step="any" dir="ltr" class="mt-1 block w-full rounded-xl" />
                            <InputError class="mt-2" :message="labForm.errors.lab_fee" />
                        </div>
                        <div>
                            <InputLabel for="lab_validity_days" :value="t('clinicSettingsAdmin.labValidityLabel')" />
                            <TextInput id="lab_validity_days" v-model="labForm.lab_validity_days" type="number" min="0" dir="ltr" class="mt-1 block w-full rounded-xl" />
                            <InputError class="mt-2" :message="labForm.errors.lab_validity_days" />
                        </div>
                        <div>
                            <InputLabel for="lab_student_discount_percent" :value="t('patientReg.studentDiscountLabel')" />
                            <TextInput id="lab_student_discount_percent" v-model="labForm.lab_student_discount_percent" type="number" min="0" max="100" step="any" dir="ltr" class="mt-1 block w-full rounded-xl" />
                            <InputError class="mt-2" :message="labForm.errors.lab_student_discount_percent" />
                        </div>
                        <PrimaryButton class="rounded-full" :disabled="labForm.processing">{{ t('profile.save') }}</PrimaryButton>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
