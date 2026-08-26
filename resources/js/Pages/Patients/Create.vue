<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm } from '@inertiajs/vue3';

defineProps({
    stages: Array,
    doctors: Array,
});

const form = useForm({
    name: '',
    phone: '',
    stage_id: '',
    doctor_id: '',
});

const submit = () => {
    form.post(route('patients.store'));
};
</script>

<template>
    <Head title="Register Patient" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                Register Patient
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="name" value="Name" />
                            <TextInput id="name" v-model="form.name" type="text" class="mt-1 block w-full" required autofocus />
                            <InputError class="mt-2" :message="form.errors.name" />
                        </div>

                        <div>
                            <InputLabel for="phone" value="Phone" />
                            <TextInput id="phone" v-model="form.phone" type="text" class="mt-1 block w-full" />
                            <InputError class="mt-2" :message="form.errors.phone" />
                        </div>

                        <div>
                            <InputLabel for="stage_id" value="Stage" />
                            <select
                                id="stage_id"
                                v-model="form.stage_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            >
                                <option value="">Unassigned</option>
                                <option v-for="stage in stages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.stage_id" />
                        </div>

                        <div>
                            <InputLabel for="doctor_id" value="Doctor" />
                            <select
                                id="doctor_id"
                                v-model="form.doctor_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            >
                                <option value="">Unassigned</option>
                                <option v-for="doctor in doctors" :key="doctor.id" :value="doctor.id">{{ doctor.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.doctor_id" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">Save Patient</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
