<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import DynamicField from '@/Components/DynamicField.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    resource: String, // route name prefix, e.g. "periodontal-charts"
    title: String,
    fields: Array, // [{ key, label, type, required }]
    record: Object, // null on create
    doctors: Array,
});

const isEdit = computed(() => props.record !== null);

const initial = {};
props.fields.forEach((f) => {
    let value = props.record ? (props.record[f.key] ?? '') : '';

    // Boolean-typed fields come back from Eloquent's 'boolean' cast as real
    // true/false (not "1"/"0" strings). The <select> in DynamicField.vue
    // compares against string option values ("1"/"0"), so an un-normalized
    // JS boolean would silently fail to pre-select the current value when
    // editing an existing record (always falls back to the blank option).
    if (f.type === 'boolean' && typeof value === 'boolean') {
        value = value ? '1' : '0';
    }

    initial[f.key] = value;
});

const form = useForm(initial);

const submit = () => {
    if (isEdit.value) {
        form.put(route(`${props.resource}.update`, props.record.id));
    } else {
        form.post(route(`${props.resource}.store`));
    }
};
</script>

<template>
    <Head :title="title" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                {{ isEdit ? t('specialtyForms.editPrefixTemplate', { title }) : t('specialtyForms.newPrefixTemplate', { title }) }}
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div v-if="doctors" class="grid grid-cols-1 gap-6 sm:grid-cols-2">
                            <div v-if="form.doctor_id !== undefined">
                                <label class="block text-sm font-medium text-gray-700">{{ t('specialtyForms.doctorLabel') }} *</label>
                                <select v-model="form.doctor_id" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                    <option value="" disabled>{{ t('specialtyForms.selectDoctorPlaceholder') }}</option>
                                    <option v-for="d in doctors" :key="d.id" :value="d.id">{{ d.name }}</option>
                                </select>
                                <p v-if="form.errors.doctor_id" class="mt-2 text-sm text-red-600">{{ form.errors.doctor_id }}</p>
                            </div>
                        </div>

                        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
                            <DynamicField
                                v-for="f in fields.filter((f) => f.key !== 'doctor_id')"
                                :key="f.key"
                                :field="f"
                                v-model="form[f.key]"
                                :error="form.errors[f.key]"
                            />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">{{ isEdit ? t('specialtyForms.updateButton') : t('specialtyForms.saveButton') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
