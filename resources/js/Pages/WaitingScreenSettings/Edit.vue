<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm, usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    settings: Object,
    groups: Array,
});

const page = usePage();

const form = useForm({
    group_id: props.settings.group_id ?? '',
    patients_per_page: props.settings.patients_per_page ?? 8,
    rotation_seconds: props.settings.rotation_seconds ?? 12,
});

const submit = () => {
    form.put(route('waiting-screen-settings.update'), { preserveScroll: true });
};
</script>

<template>
    <Head :title="t('waitingScreenSettings.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('waitingScreenSettings.heading') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="mb-4 rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <p class="mb-6 text-sm text-gray-500">{{ t('waitingScreenSettings.description') }}</p>
                    <p class="mb-6 rounded-md bg-indigo-50 p-3 text-sm text-indigo-700">
                        {{ t('waitingScreenSettings.stageMovedNote') }}
                    </p>

                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="group_id" :value="t('waitingScreenSettings.groupLabel')" />
                            <select
                                id="group_id"
                                v-model="form.group_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            >
                                <option value="">{{ t('waitingScreenSettings.allGroups') }}</option>
                                <option v-for="g in groups" :key="g.id" :value="g.id">
                                    {{ g.name }}<template v-if="g.stage"> — {{ g.stage.name }}</template>
                                </option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.group_id" />
                        </div>

                        <div>
                            <InputLabel for="patients_per_page" :value="t('waitingScreenSettings.patientsPerPageLabel')" />
                            <TextInput
                                id="patients_per_page"
                                v-model.number="form.patients_per_page"
                                type="number"
                                min="1"
                                max="50"
                                class="mt-1 block w-full max-w-[10rem]"
                                required
                            />
                            <InputError class="mt-2" :message="form.errors.patients_per_page" />
                        </div>

                        <div>
                            <InputLabel for="rotation_seconds" :value="t('waitingScreenSettings.rotationSecondsLabel')" />
                            <TextInput
                                id="rotation_seconds"
                                v-model.number="form.rotation_seconds"
                                type="number"
                                min="3"
                                max="300"
                                class="mt-1 block w-full max-w-[10rem]"
                                required
                            />
                            <InputError class="mt-2" :message="form.errors.rotation_seconds" />
                        </div>

                        <div class="flex items-center justify-between border-t border-gray-200 pt-6">
                            <a
                                :href="route('waiting-screen')"
                                target="_blank"
                                rel="noopener"
                                class="text-sm font-medium text-indigo-600 hover:text-indigo-900"
                            >
                                {{ t('waitingScreenSettings.openScreen') }} ↗
                            </a>
                            <PrimaryButton :disabled="form.processing">{{ t('waitingScreenSettings.save') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
