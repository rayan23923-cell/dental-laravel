<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    educationTypes: Array,
    stages: Array,
    // The list the user came from, filters and page kept (2026-10-18).
    backUrl: String,
});

const form = useForm({
    back: props.backUrl,
    name: '',
    username: '',
    email: '',
    phone: '',
    education_type_id: '',
    stage_id: '',
    password: '',
    profile_image: null,
    nfc_tag_id: '',
});

// Mirrors the original app's AJAX-driven stage filtering (admin/ajax/get_stages_by_edu.php):
// the stage dropdown only shows stages belonging to the selected education type, so a
// doctor can't be assigned a stage/education-type combination that doesn't exist together.
const filteredStages = computed(() =>
    form.education_type_id
        ? props.stages.filter((s) => s.education_type_id === form.education_type_id)
        : props.stages
);

watch(
    () => form.education_type_id,
    () => {
        if (!filteredStages.value.some((s) => s.id === form.stage_id)) {
            form.stage_id = '';
        }
    }
);

const submit = () => {
    form.post(route('doctors.store'));
};
</script>

<template>
    <Head :title="t('doctorsAdmin.addDoctor')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-2">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">
                    {{ t('doctorsAdmin.addDoctor') }}
                </h2>
                <!-- Back to the doctors list (2026-10-18, by request). -->
                <Link :href="backUrl || route('doctors.index')" class="flex items-center gap-1 text-sm text-indigo-600 hover:underline">
                    {{ t('common.back') }}
                </Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="name" :value="t('profile.name')" />
                            <TextInput id="name" v-model="form.name" type="text" class="mt-1 block w-full" required autofocus />
                            <InputError class="mt-2" :message="form.errors.name" />
                        </div>

                        <div>
                            <InputLabel for="username" :value="t('common.username')" />
                            <TextInput id="username" v-model="form.username" type="text" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="form.errors.username" />
                        </div>

                        <div>
                            <InputLabel for="email" :value="t('profile.email')" />
                            <TextInput id="email" v-model="form.email" type="email" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="form.errors.email" />
                        </div>

                        <div>
                            <InputLabel for="phone" :value="t('profile.phone')" />
                            <TextInput id="phone" v-model="form.phone" type="tel" class="mt-1 block w-full" />
                            <InputError class="mt-2" :message="form.errors.phone" />
                        </div>

                        <div>
                            <InputLabel for="education_type_id" :value="t('doctorsAdmin.educationTypeCol')" />
                            <select
                                id="education_type_id"
                                v-model="form.education_type_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                required
                            >
                                <option value="" disabled>{{ t('doctorsAdmin.selectEducationType') }}</option>
                                <option v-for="type in educationTypes" :key="type.id" :value="type.id">{{ type.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.education_type_id" />
                        </div>

                        <div>
                            <InputLabel for="stage_id" :value="t('doctorsAdmin.stageCol')" />
                            <select
                                id="stage_id"
                                v-model="form.stage_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                :disabled="!form.education_type_id"
                                required
                            >
                                <option value="" disabled>{{ form.education_type_id ? t('doctorsAdmin.selectStage') : t('doctorsAdmin.selectEducationTypeFirst') }}</option>
                                <option v-for="stage in filteredStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.stage_id" />
                        </div>

                        <div>
                            <InputLabel for="password" :value="t('common.password')" />
                            <TextInput id="password" v-model="form.password" type="password" class="mt-1 block w-full" autocomplete="new-password" />
                            <p class="mt-1 text-xs text-gray-500">{{ t('common.passwordAutoHint') }}</p>
                            <InputError class="mt-2" :message="form.errors.password" />
                        </div>

                        <div>
                            <InputLabel for="nfc_tag_id" :value="t('doctorsAdmin.nfcTagLabel')" />
                            <TextInput id="nfc_tag_id" v-model="form.nfc_tag_id" type="text" class="mt-1 block w-full" dir="ltr" />
                            <p class="mt-1 text-xs text-gray-500">
                                {{ t('doctorsAdmin.nfcTagHint') }}
                            </p>
                            <InputError class="mt-2" :message="form.errors.nfc_tag_id" />
                        </div>

                        <div>
                            <InputLabel for="profile_image" :value="t('doctorsAdmin.profilePhotoLabel')" />
                            <input
                                id="profile_image"
                                type="file"
                                accept="image/*"
                                class="mt-1 block w-full text-sm text-gray-700"
                                @input="form.profile_image = $event.target.files[0]"
                            />
                            <InputError class="mt-2" :message="form.errors.profile_image" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">{{ t('doctorsAdmin.saveDoctor') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
