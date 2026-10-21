<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * One user's details and password (2026-10-21, by request: "إدارة
 * المستخدمين"); permissions stay on their own page, linked below.
 */
const { t, te } = useI18n();
const props = defineProps({
    targetUser: Object,
    roles: Array,
    isSelf: Boolean,
});

const page = usePage();
const u = props.targetUser;

const form = useForm({
    full_name: u.full_name ?? '',
    username: u.username ?? '',
    email: u.email ?? '',
    phone: u.phone ?? '',
    role: u.role,
    status: u.status ?? 'active',
    notes: u.notes ?? '',
});

const passwordForm = useForm({
    password: '',
    password_confirmation: '',
    send_email: false,
    generate: false,
});

const save = () => form.put(route('users.update', u.id), { preserveScroll: true });

const changePassword = (generate) => {
    passwordForm.generate = generate;
    passwordForm.put(route('users.password', u.id), {
        preserveScroll: true,
        onSuccess: () => passwordForm.reset(),
    });
};

const generated = computed(() => page.props.flash?.generated_password);
const copied = ref(false);
const copy = async () => {
    try {
        await navigator.clipboard.writeText(generated.value);
        copied.value = true;
    } catch {
        // Clipboard blocked (plain http on the LAN): the password is on screen to copy by hand.
    }
};

const roleLabel = (role) => (te(`roles.${role}`) ? t(`roles.${role}`) : role);
const lastLogin = computed(() => (u.last_login ? new Date(u.last_login).toLocaleString() : t('usersAdmin.never')));
</script>

<template>
    <Head :title="t('usersAdmin.editTitle')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('usersAdmin.editTitle') }}</h2>
                <Link :href="route('users.index')" class="flex items-center gap-1 text-sm text-indigo-600 hover:underline">
                    {{ t('common.back') }}
                </Link>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-3xl space-y-5 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div v-if="generated" class="rounded-2xl bg-amber-50 p-4 ring-1 ring-amber-200">
                    <div class="text-sm font-semibold text-amber-900">{{ t('usersAdmin.generatedTitle') }}</div>
                    <div class="mt-2 flex items-center gap-3">
                        <code class="select-all rounded-lg bg-white px-3 py-1.5 text-lg font-bold tracking-wider text-gray-900" dir="ltr">{{ generated }}</code>
                        <button type="button" class="inline-flex items-center gap-1 rounded-full bg-amber-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-amber-700" @click="copy">
                            <Icon name="content_copy" size="text-[16px]" />
                            {{ copied ? t('usersAdmin.copied') : t('usersAdmin.copy') }}
                        </button>
                    </div>
                    <p class="mt-2 text-xs text-amber-800">{{ t('usersAdmin.generatedHint') }}</p>
                </div>

                <!-- Who -->
                <div class="flex items-center gap-4 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100">
                    <span class="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-pink-500 text-xl font-semibold text-white" :class="u.status === 'inactive' ? 'opacity-40 grayscale' : ''">
                        {{ (u.full_name || u.username || '?').trim().charAt(0).toUpperCase() }}
                    </span>
                    <div class="min-w-0 flex-1">
                        <div class="truncate text-lg font-semibold text-gray-900">{{ u.full_name || u.username }}</div>
                        <div class="text-sm text-gray-500">{{ roleLabel(u.role) }} · <span dir="ltr">@{{ u.username }}</span></div>
                        <div class="mt-1 text-xs text-gray-400">{{ t('usersAdmin.lastLogin') }}: {{ lastLogin }}</div>
                    </div>
                </div>

                <!-- Details -->
                <form @submit.prevent="save" class="space-y-5">
                    <h3 class="-mb-3 px-2 text-xs font-semibold text-indigo-600">{{ t('usersAdmin.accountSection') }}</h3>
                    <div class="space-y-6 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                        <p v-if="isSelf" class="rounded-xl bg-indigo-50 p-3 text-xs text-indigo-700">{{ t('usersAdmin.selfHint') }}</p>

                        <div>
                            <InputLabel for="full_name" :value="t('common.fullName')" />
                            <TextInput id="full_name" v-model="form.full_name" type="text" class="mt-1 block w-full rounded-xl" required />
                            <InputError class="mt-2" :message="form.errors.full_name" />
                        </div>

                        <div>
                            <InputLabel for="username" :value="t('common.username')" />
                            <TextInput id="username" v-model="form.username" type="text" class="mt-1 block w-full rounded-xl" dir="ltr" required />
                            <InputError class="mt-2" :message="form.errors.username" />
                        </div>

                        <div>
                            <InputLabel for="email" :value="t('profile.email')" />
                            <TextInput id="email" v-model="form.email" type="email" class="mt-1 block w-full rounded-xl" dir="ltr" required />
                            <InputError class="mt-2" :message="form.errors.email" />
                        </div>

                        <div>
                            <InputLabel for="phone" :value="t('profile.phone')" />
                            <TextInput id="phone" v-model="form.phone" type="tel" class="mt-1 block w-full rounded-xl" dir="ltr" />
                            <InputError class="mt-2" :message="form.errors.phone" />
                        </div>

                        <div>
                            <InputLabel for="role" :value="t('common.role')" />
                            <select
                                id="role"
                                v-model="form.role"
                                :disabled="isSelf || u.role === 'super_admin'"
                                class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100"
                            >
                                <option v-for="r in roles" :key="r" :value="r">{{ roleLabel(r) }}</option>
                            </select>
                            <p v-if="u.role === 'super_admin'" class="mt-1 text-xs text-gray-500">{{ t('usersAdmin.superAdminLocked') }}</p>
                            <InputError class="mt-2" :message="form.errors.role" />
                        </div>

                        <div>
                            <InputLabel :value="t('usersAdmin.statusLabel')" />
                            <div class="mt-1 grid grid-cols-2 gap-2">
                                <button
                                    v-for="s in ['active', 'inactive']"
                                    :key="s"
                                    type="button"
                                    :disabled="isSelf"
                                    class="flex items-center justify-center gap-1 rounded-xl px-3 py-2.5 text-sm font-medium ring-1 transition disabled:opacity-50"
                                    :class="form.status === s
                                        ? (s === 'active' ? 'bg-emerald-600 text-white ring-emerald-600' : 'bg-red-600 text-white ring-red-600')
                                        : 'bg-white text-gray-700 ring-gray-200 hover:bg-gray-50'"
                                    @click="form.status = s"
                                >
                                    <Icon :name="s === 'active' ? 'check_circle' : 'block'" size="text-[18px]" />
                                    {{ t(`usersAdmin.${s}`) }}
                                </button>
                            </div>
                            <p class="mt-1 text-xs text-gray-500">{{ t('usersAdmin.inactiveHint') }}</p>
                            <InputError class="mt-2" :message="form.errors.status" />
                        </div>

                        <div>
                            <InputLabel for="notes" :value="t('usersAdmin.notesLabel')" />
                            <textarea id="notes" v-model="form.notes" rows="3" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" />
                            <InputError class="mt-2" :message="form.errors.notes" />
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing">
                                <Icon name="save" size="text-[18px]" />{{ t('usersAdmin.saveInfo') }}
                            </PrimaryButton>
                        </div>
                    </div>
                </form>

                <!-- Password -->
                <form @submit.prevent="changePassword(false)" class="space-y-5">
                    <h3 class="-mb-3 px-2 text-xs font-semibold text-indigo-600">{{ t('usersAdmin.passwordSection') }}</h3>
                    <div class="space-y-6 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                        <div>
                            <InputLabel for="password" :value="t('usersAdmin.newPassword')" />
                            <TextInput id="password" v-model="passwordForm.password" type="password" class="mt-1 block w-full rounded-xl" autocomplete="new-password" />
                            <InputError class="mt-2" :message="passwordForm.errors.password" />
                        </div>
                        <div>
                            <InputLabel for="password_confirmation" :value="t('usersAdmin.confirmPassword')" />
                            <TextInput id="password_confirmation" v-model="passwordForm.password_confirmation" type="password" class="mt-1 block w-full rounded-xl" autocomplete="new-password" />
                        </div>
                        <label class="flex items-center gap-2 text-sm text-gray-700">
                            <input v-model="passwordForm.send_email" type="checkbox" class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                            {{ t('usersAdmin.sendByEmail') }}
                        </label>
                        <p v-if="!isSelf" class="text-xs text-gray-500">{{ t('usersAdmin.passwordSignOutHint') }}</p>
                        <div class="flex flex-wrap justify-end gap-2">
                            <button
                                type="button"
                                class="inline-flex items-center gap-1 rounded-full bg-gray-100 px-4 py-2 text-xs font-semibold uppercase tracking-widest text-gray-700 hover:bg-gray-200 disabled:opacity-50"
                                :disabled="passwordForm.processing"
                                @click="changePassword(true)"
                            >
                                <Icon name="key" size="text-[18px]" />{{ t('usersAdmin.generatePassword') }}
                            </button>
                            <PrimaryButton class="gap-1 rounded-full" :disabled="passwordForm.processing || !passwordForm.password">
                                <Icon name="lock_reset" size="text-[18px]" />{{ t('usersAdmin.changePassword') }}
                            </PrimaryButton>
                        </div>
                    </div>
                </form>

                <!-- Permissions live on their own page. -->
                <Link
                    v-if="u.role !== 'super_admin'"
                    :href="route('permissions.edit', u.id)"
                    class="flex items-center gap-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100 transition hover:bg-gray-50"
                >
                    <span class="flex h-10 w-10 items-center justify-center rounded-full bg-indigo-50 text-indigo-600"><Icon name="admin_panel_settings" /></span>
                    <span class="flex-1 text-sm font-medium text-gray-900">{{ t('usersAdmin.permissionsLink') }}</span>
                    <Icon name="chevron_left" class="text-gray-300 ltr:rotate-180" />
                </Link>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
