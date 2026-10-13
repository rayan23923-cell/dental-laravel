<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t, te } = useI18n();
const props = defineProps({
    roles: Array,
});

const form = useForm({
    full_name: '',
    username: '',
    email: '',
    phone: '',
    password: '',
    role: 'editor',
});

const submit = () => {
    form.post(route('users.store'));
};
</script>

<template>
    <Head :title="t('usersAdmin.addUserTitle')" />

    <AuthenticatedLayout>
        <!-- Chat-list style (2026-10-13, by request): rounded card with an icon, rounded inputs. -->
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                {{ t('usersAdmin.addUserTitle') }}
            </h2>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl px-4 sm:px-6 lg:px-8">
                <div class="overflow-hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                    <div class="mb-5 flex justify-center">
                        <span class="flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-pink-500 text-white shadow"><Icon name="person_add" size="text-[28px]" /></span>
                    </div>
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="full_name" :value="t('common.fullName')" />
                            <TextInput id="full_name" v-model="form.full_name" type="text" class="mt-1 block w-full rounded-xl" required autofocus />
                            <InputError class="mt-2" :message="form.errors.full_name" />
                        </div>

                        <div>
                            <InputLabel for="username" :value="t('common.username')" />
                            <TextInput id="username" v-model="form.username" type="text" class="mt-1 block w-full rounded-xl" required />
                            <InputError class="mt-2" :message="form.errors.username" />
                        </div>

                        <div>
                            <InputLabel for="email" :value="t('profile.email')" />
                            <TextInput id="email" v-model="form.email" type="email" class="mt-1 block w-full rounded-xl" required />
                            <InputError class="mt-2" :message="form.errors.email" />
                        </div>

                        <div>
                            <InputLabel for="phone" :value="t('profile.phone')" />
                            <TextInput id="phone" v-model="form.phone" type="text" class="mt-1 block w-full rounded-xl" />
                            <InputError class="mt-2" :message="form.errors.phone" />
                        </div>

                        <div>
                            <InputLabel for="role" :value="t('common.role')" />
                            <select
                                id="role"
                                v-model="form.role"
                                class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                required
                            >
                                <option v-for="r in roles" :key="r" :value="r">{{ te(`roles.${r}`) ? t(`roles.${r}`) : r }}</option>
                            </select>
                            <p v-if="form.role === 'reception' || form.role === 'lab'" class="mt-1 text-xs text-gray-500">{{ t('usersAdmin.deskRoleHint') }}</p>
                            <InputError class="mt-2" :message="form.errors.role" />
                        </div>

                        <div>
                            <InputLabel for="password" :value="t('common.password')" />
                            <TextInput id="password" v-model="form.password" type="password" class="mt-1 block w-full rounded-xl" autocomplete="new-password" />
                            <p class="mt-1 text-xs text-gray-500">{{ t('common.passwordAutoHint') }}</p>
                            <InputError class="mt-2" :message="form.errors.password" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing"><Icon name="save" size="text-[18px]" />{{ t('usersAdmin.saveUser') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
