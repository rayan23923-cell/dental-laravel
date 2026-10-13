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
});

// Registration is name + phone + a priced service (2026-10-12). Services
// are picked from cards; payment is mandatory and is the service's price,
// recorded by the server, so there is no amount field. A service with no
// price yet cannot be picked.
const serviceFilter = ref('');
const filteredServices = computed(() =>
    serviceFilter.value.trim()
        ? props.services.filter((s) => s.name.includes(serviceFilter.value.trim()))
        : props.services,
);
const selectedService = computed(() => props.services.find((s) => s.id === form.service_id) ?? null);
const formatPrice = (price) => `${Number(price).toLocaleString()} ${props.currency ?? ''}`.trim();
const isPriced = (service) => service.price !== null && service.price !== undefined;

const pickService = (service) => {
    if (isPriced(service)) form.service_id = service.id;
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
                            <InputLabel :value="t('patientReg.serviceLabel')" />
                            <TextInput
                                v-if="services.length > 6"
                                v-model="serviceFilter"
                                type="text"
                                :placeholder="t('patientReg.filterServices')"
                                class="mt-1 block w-full"
                            />
                            <div role="radiogroup" class="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-3">
                                <button
                                    v-for="service in filteredServices"
                                    :key="service.id"
                                    type="button"
                                    role="radio"
                                    :aria-checked="form.service_id === service.id"
                                    :disabled="!isPriced(service)"
                                    @click="pickService(service)"
                                    class="flex min-h-[5.5rem] flex-col items-center justify-center gap-1 rounded-lg border-2 p-3 text-center transition"
                                    :class="
                                        form.service_id === service.id
                                            ? 'border-indigo-600 bg-indigo-50 ring-2 ring-indigo-200'
                                            : isPriced(service)
                                              ? 'border-gray-200 bg-white hover:border-indigo-300'
                                              : 'cursor-not-allowed border-dashed border-gray-200 bg-gray-50 opacity-60'
                                    "
                                >
                                    <span class="font-semibold text-gray-900">{{ service.name }}</span>
                                    <span v-if="isPriced(service)" class="text-sm text-indigo-700" dir="ltr">{{ formatPrice(service.price) }}</span>
                                    <span v-else class="text-xs text-amber-700">{{ t('patientReg.noPriceYet') }}</span>
                                </button>
                            </div>
                            <InputError class="mt-2" :message="form.errors.service_id" />
                            <p v-if="services.length === 0" class="mt-2 text-sm text-amber-600">{{ t('patientReg.noServicesYet') }}</p>
                        </div>

                        <div v-if="selectedService" class="flex items-center justify-between rounded-lg bg-gray-50 px-4 py-3">
                            <span class="text-sm text-gray-600">{{ t('patientReg.amountDue') }}</span>
                            <span class="text-lg font-bold text-gray-900" dir="ltr">{{ formatPrice(selectedService.price) }}</span>
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing || !selectedService">{{ t('patientReg.submitRegistration') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
