<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import { Head, useForm, usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
defineProps({
    stages: Array,
});

const page = usePage();

const form = useForm({
    code: '',
    stage_id: '',
});

const submit = () => {
    form.post(route('waiting-screen-pairing.store'), {
        preserveScroll: true,
        onSuccess: () => form.reset('code'),
    });
};
</script>

<template>
    <Head :title="t('waitingScreenPairing.title')" />

    <AuthenticatedLayout>
        <!-- Chat-list style (2026-10-13, by request): rounded card and inputs. -->
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('waitingScreenPairing.heading') }}</h2>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-lg px-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="mb-4 rounded-xl bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                    <div class="mb-6 flex items-start gap-3">
                        <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-purple-500 text-white"><Icon name="connected_tv" size="text-[22px]" /></span>
                        <p class="pt-2 text-sm text-gray-500">{{ t('waitingScreenPairing.description') }}</p>
                    </div>

                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="code" :value="t('waitingScreenPairing.codeLabel')" />
                            <TextInput
                                id="code"
                                v-model="form.code"
                                type="text"
                                inputmode="numeric"
                                pattern="[0-9]*"
                                maxlength="4"
                                autocomplete="off"
                                class="mt-1 block w-full rounded-xl text-center text-3xl tracking-[0.5em]"
                                autofocus
                                required
                            />
                            <InputError class="mt-2" :message="form.errors.code" />
                        </div>

                        <div>
                            <InputLabel for="stage_id" :value="t('waitingScreenPairing.stageLabel')" />
                            <select
                                id="stage_id"
                                v-model="form.stage_id"
                                class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            >
                                <option value="">{{ t('waitingScreenPairing.allStages') }}</option>
                                <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.stage_id" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing"><Icon name="link" size="text-[18px]" />{{ t('waitingScreenPairing.confirm') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
