<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    services: Array,
    currency: String,
});

const form = useForm({
    name: '',
    phone: '',
    service_id: '',
    amount_paid: '',
});

// Registration is name + phone + a priced service (2026-10-12). Picking a
// service fills the amount paid with its price; the desk can still change it.
const serviceFilter = ref('');
const filteredServices = computed(() =>
    serviceFilter.value.trim()
        ? props.services.filter((s) => s.name.includes(serviceFilter.value.trim()))
        : props.services,
);
const selectedService = computed(() => props.services.find((s) => s.id === form.service_id) ?? null);
const formatPrice = (price) => `${Number(price).toLocaleString()} ${props.currency ?? ''}`.trim();

const onServiceChange = () => {
    const price = selectedService.value?.price;
    form.amount_paid = price !== null && price !== undefined ? String(Number(price)) : '';
};

const submit = () => {
    form.post(route('patient-registrations.store'));
};
</script>

<template>
    <Head :title="t('nav.registerPatient')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('nav.registerPatient') }}</h2>
                <Link :href="route('patient-registrations.index')" class="text-sm text-indigo-600 hover:underline">{{ t('patientReg.registryLink') }} &rarr;</Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="name" :value="t('patientReg.patientName')" />
                            <TextInput id="name" v-model="form.name" type="text" class="mt-1 block w-full" required autofocus />
                            <InputError class="mt-2" :message="form.errors.name" />
                        </div>

                        <div>
                            <InputLabel for="phone" :value="t('profile.phone')" />
                            <TextInput id="phone" v-model="form.phone" type="text" class="mt-1 block w-full" dir="ltr" required />
                            <InputError class="mt-2" :message="form.errors.phone" />
                        </div>

                        <div>
                            <InputLabel for="service_id" :value="t('patientReg.serviceLabel')" />
                            <TextInput
                                v-if="services.length > 6"
                                v-model="serviceFilter"
                                type="text"
                                :placeholder="t('patientReg.filterServices')"
                                class="mt-1 block w-full"
                            />
                            <select
                                id="service_id"
                                v-model="form.service_id"
                                @change="onServiceChange"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                required
                            >
                                <option value="" disabled>{{ t('patientReg.chooseService') }}</option>
                                <option v-for="service in filteredServices" :key="service.id" :value="service.id">
                                    {{ service.name }}<template v-if="service.price !== null"> — {{ formatPrice(service.price) }}</template>
                                </option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.service_id" />
                            <p v-if="services.length === 0" class="mt-2 text-sm text-amber-600">{{ t('patientReg.noServicesYet') }}</p>
                        </div>

                        <div>
                            <InputLabel for="amount_paid" :value="t('patientReg.amountPaid')" />
                            <TextInput id="amount_paid" v-model="form.amount_paid" type="number" min="0" step="any" class="mt-1 block w-full" dir="ltr" />
                            <p class="mt-1 text-xs text-gray-500">{{ t('patientReg.amountPaidHint') }}</p>
                            <InputError class="mt-2" :message="form.errors.amount_paid" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">{{ t('patientReg.submitRegistration') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
