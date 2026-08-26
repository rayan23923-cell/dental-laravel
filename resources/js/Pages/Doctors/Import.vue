<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm } from '@inertiajs/vue3';

defineProps({
    educationTypes: Array,
    stages: Array,
});

const form = useForm({
    file: null,
    education_type_id: '',
    stage_id: '',
    default_password: '',
});

const submit = () => {
    form.post(route('doctors.import'));
};
</script>

<template>
    <Head title="Import Doctors" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">Import Doctors</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl space-y-4 sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <p class="mb-4 text-sm text-gray-600">
                        Upload an Excel file with columns: First Name, Last Name, Email, Phone, Username.
                        <a :href="route('doctors.template')" class="text-indigo-600 hover:underline">Download the template</a>.
                        All imported doctors get the same education type, stage, and default password below.
                    </p>

                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="file" value="Excel File" />
                            <input
                                id="file"
                                type="file"
                                accept=".xlsx,.xls,.csv"
                                class="mt-1 block w-full text-sm text-gray-700"
                                @input="form.file = $event.target.files[0]"
                            />
                            <InputError class="mt-2" :message="form.errors.file" />
                        </div>

                        <div>
                            <InputLabel for="education_type_id" value="Education Type" />
                            <select id="education_type_id" v-model="form.education_type_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>Select an education type</option>
                                <option v-for="t in educationTypes" :key="t.id" :value="t.id">{{ t.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.education_type_id" />
                        </div>

                        <div>
                            <InputLabel for="stage_id" value="Stage" />
                            <select id="stage_id" v-model="form.stage_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>Select a stage</option>
                                <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.stage_id" />
                        </div>

                        <div>
                            <InputLabel for="default_password" value="Default Password" />
                            <TextInput id="default_password" v-model="form.default_password" type="text" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="form.errors.default_password" />
                        </div>

                        <div class="flex justify-end gap-3">
                            <SecondaryButton :href="route('doctors.index')" as="a">Cancel</SecondaryButton>
                            <PrimaryButton :disabled="form.processing">Import</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
