<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import PermissionsEditor from '@/Components/Permissions/PermissionsEditor.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t, te } = useI18n();
const props = defineProps({
    roles: Array,
    // The permissions page's editor, filled in before the account exists
    // (2026-10-14, by request); see Components/Permissions/PermissionsEditor.
    modules: Array,
    scopeOptions: Object,
    // role → its ready-made "module.permission" grants (App\Support\RolePresets).
    roleDefaults: [Object, Array],
});

const defaultsFor = (role) => [...(props.roleDefaults?.[role] ?? [])];

const form = useForm({
    full_name: '',
    username: '',
    email: '',
    phone: '',
    password: '',
    role: 'editor',
    grants: defaultsFor('editor'),
    // A new account sees no scoped data until "الكل" or items are picked.
    scope: { departments: [], stages: [], education_types: [], academic_sessions: [], all_education_types: false, all_academic_sessions: false },
});

// Picking a role starts its permissions over from that role's preset.
watch(() => form.role, (role) => (form.grants = defaultsFor(role)));

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

        <div class="py-6 pb-28 sm:py-10 sm:pb-28">
            <form @submit.prevent="submit" class="mx-auto max-w-3xl space-y-5 px-4 sm:px-6 lg:px-8">
                <h3 class="-mb-3 px-2 text-xs font-semibold text-indigo-600">{{ t('usersAdmin.accountSection') }}</h3>
                <div class="overflow-hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                    <div class="mb-5 flex justify-center">
                        <span class="flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-pink-500 text-white shadow"><Icon name="person_add" size="text-[28px]" /></span>
                    </div>
                    <div class="space-y-6">
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
                            <TextInput id="phone" v-model="form.phone" type="tel" class="mt-1 block w-full rounded-xl" />
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
                            <p class="mt-1 text-xs text-gray-500">{{ form.role === 'reception' || form.role === 'lab' ? t('usersAdmin.deskRoleHint') : t('usersAdmin.roleDefaultsHint') }}</p>
                            <InputError class="mt-2" :message="form.errors.role" />
                        </div>

                        <div>
                            <InputLabel for="password" :value="t('common.password')" />
                            <TextInput id="password" v-model="form.password" type="password" class="mt-1 block w-full rounded-xl" autocomplete="new-password" />
                            <p class="mt-1 text-xs text-gray-500">{{ t('common.passwordAutoHint') }}</p>
                            <InputError class="mt-2" :message="form.errors.password" />
                        </div>

                    </div>
                </div>

                <PermissionsEditor :form="form" :modules="modules" :scope-options="scopeOptions" />

                <div class="fixed inset-x-0 bottom-0 z-30 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur">
                    <div class="mx-auto flex max-w-3xl items-center justify-end gap-3">
                        <span v-if="form.hasErrors" class="flex-1 text-xs text-red-600">{{ Object.values(form.errors)[0] }}</span>
                        <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing"><Icon name="save" size="text-[18px]" />{{ t('usersAdmin.saveUser') }}</PrimaryButton>
                    </div>
                </div>
            </form>
        </div>
    </AuthenticatedLayout>
</template>
