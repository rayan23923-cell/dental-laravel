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
const props = defineProps({
    recipientCount: Number,
});

const page = usePage();

const form = useForm({
    title: '',
    body: '',
});

const submit = () => {
    if (!confirm(t('adminBroadcast.confirmTemplate', { count: props.recipientCount }))) {
        return;
    }
    form.post(route('admin-broadcast.store'), {
        onSuccess: () => form.reset(),
    });
};
</script>

<template>
    <Head :title="t('adminBroadcast.title')" />

    <AuthenticatedLayout>
        <!-- Chat-list style (2026-10-13, by request): rounded card with an icon, rounded inputs. -->
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('adminBroadcast.title') }}</h2>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-xl space-y-4 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                    <div class="mb-5 flex items-start gap-3">
                        <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-fuchsia-500 to-pink-500 text-white"><Icon name="campaign" size="text-[22px]" /></span>
                        <p class="pt-2 text-sm text-gray-600">{{ t('adminBroadcast.description', { count: recipientCount }) }}</p>
                    </div>
                    <form @submit.prevent="submit" class="space-y-4">
                        <div>
                            <InputLabel for="title" :value="t('adminBroadcast.titleLabel')" />
                            <TextInput
                                id="title"
                                v-model="form.title"
                                type="text"
                                class="mt-1 block w-full rounded-xl"
                                maxlength="100"
                                required
                                autofocus
                            />
                            <InputError class="mt-2" :message="form.errors.title" />
                        </div>

                        <div>
                            <InputLabel for="body" :value="t('adminBroadcast.bodyLabel')" />
                            <textarea
                                id="body"
                                v-model="form.body"
                                rows="5"
                                maxlength="2000"
                                required
                                class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            ></textarea>
                            <InputError class="mt-2" :message="form.errors.body" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing"><Icon name="send" size="text-[18px]" class="rtl:-scale-x-100" />{{ t('adminBroadcast.sendButton') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
