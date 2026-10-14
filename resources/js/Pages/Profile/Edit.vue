<script setup>
/**
 * Staff profile — matches admin/admin_profile.php: two independent forms,
 * "تحديث الملف الشخصي" (name/email/phone/photo) and "تغيير كلمة المرور"
 * (old/new/confirm). Replaces the Breeze scaffold's partials, which had no
 * phone/photo fields and shipped a delete-account form with no counterpart
 * in the original.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';
import ActiveSessionsPanel from '@/Components/ActiveSessionsPanel.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ProfileHero from '@/Components/ChatList/ProfileHero.vue';
import SettingsSection from '@/Components/ChatList/SettingsSection.vue';

const props = defineProps({
    profile: Object,
    status: String,
});

const page = usePage();
const { t, te } = useI18n();
const preview = ref(props.profile.photo_url);

const profileForm = useForm({
    full_name: props.profile.full_name ?? '',
    email: props.profile.email ?? '',
    phone: props.profile.phone ?? '',
    profile_image: null,
    // '' = "follow system language" (stored as null server-side) — see
    // ProfileController::update()'s own comment on this field.
    locale: props.profile.locale ?? '',
});

// Picking a photo from the header saves it straight away, like Instagram.
const onPhoto = (file) => {
    profileForm.profile_image = file;
    preview.value = URL.createObjectURL(file);
    submitProfile();
};

// A full reload (not Inertia's own partial visit) once the language
// actually changed — `<html lang>` and vue-i18n's active locale are both
// only re-resolved on a fresh document load (server-side ResolveLocale +
// app.js reading the `locale` shared prop at boot), not on an XHR page
// visit that just swaps this component's own props.
const submitProfile = () => {
    const localeChanged = profileForm.locale !== (props.profile.locale ?? '');
    profileForm.post(route('profile.update'), {
        preserveScroll: true,
        onSuccess: () => {
            if (localeChanged) window.location.reload();
        },
    });
};

const passwordForm = useForm({
    old_password: '',
    new_password: '',
    new_password_confirmation: '',
});

const submitPassword = () =>
    passwordForm.put(route('profile.password'), {
        preserveScroll: true,
        onSuccess: () => passwordForm.reset(),
    });

// Telegram-style list (2026-10-14, by request): one section open at a time;
// a section whose fields failed validation opens by itself.
const open = ref(null);
const toggle = (key, value) => (open.value = value ? key : null);
watch(() => profileForm.errors, (e) => {
    if (e.full_name || e.email || e.phone) open.value = 'personal';
    else if (e.locale) open.value = 'language';
});
watch(() => passwordForm.errors, (e) => {
    if (Object.keys(e).length) open.value = 'password';
});

const languageLabel = computed(() => ({
    '': t('profile.languageSystem'),
    ar: t('profile.languageAr'),
    en: t('profile.languageEn'),
}[profileForm.locale ?? ''] ?? ''));
</script>

<template>
    <Head :title="t('profile.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('profile.title') }}</h2>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-5 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="status" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">{{ status }}</div>

                <ProfileHero
                    :photo="preview"
                    :name="profile.full_name"
                    :subtitle="profile.username"
                    :chips="[profile.role && (te(`roles.${profile.role}`) ? t(`roles.${profile.role}`) : profile.role)].filter(Boolean)"
                    :error="profileForm.errors.profile_image"
                    @pick="onPhoto"
                />

                <ChatListCard>
                    <SettingsSection
                        :open="open === 'personal'" @update:open="toggle('personal', $event)"
                        icon="person" tone="bg-indigo-500" :title="t('profile.updateProfile')"
                        :summary="[profileForm.email, profileForm.phone].filter(Boolean).join(' · ')"
                        :has-error="!!(profileForm.errors.full_name || profileForm.errors.email || profileForm.errors.phone)"
                    >
                        <form @submit.prevent="submitProfile" class="space-y-4">
                            <div>
                                <InputLabel for="full_name" :value="t('profile.name')" />
                                <TextInput id="full_name" v-model="profileForm.full_name" type="text" class="mt-1 block w-full rounded-xl" required />
                                <InputError class="mt-2" :message="profileForm.errors.full_name" />
                            </div>
                            <div>
                                <InputLabel for="email" :value="t('profile.email')" />
                                <TextInput id="email" v-model="profileForm.email" type="email" dir="ltr" class="mt-1 block w-full rounded-xl" required />
                                <InputError class="mt-2" :message="profileForm.errors.email" />
                            </div>
                            <div>
                                <InputLabel for="phone" :value="t('profile.phone')" />
                                <TextInput id="phone" v-model="profileForm.phone" type="tel" dir="ltr" class="mt-1 block w-full rounded-xl" />
                                <InputError class="mt-2" :message="profileForm.errors.phone" />
                            </div>
                            <div class="flex justify-end">
                                <PrimaryButton class="rounded-full" :disabled="profileForm.processing">{{ t('profile.save') }}</PrimaryButton>
                            </div>
                        </form>
                    </SettingsSection>

                    <SettingsSection
                        :open="open === 'language'" @update:open="toggle('language', $event)"
                        icon="translate" tone="bg-sky-500" :title="t('profile.language')"
                        :summary="languageLabel" :has-error="!!profileForm.errors.locale"
                    >
                        <form @submit.prevent="submitProfile" class="space-y-3">
                            <label
                                v-for="opt in [['', t('profile.languageSystem')], ['ar', t('profile.languageAr')], ['en', t('profile.languageEn')]]"
                                :key="opt[0]"
                                class="flex cursor-pointer items-center justify-between rounded-xl bg-white px-4 py-3 ring-1 ring-gray-100"
                            >
                                <span class="text-sm text-gray-800">{{ opt[1] }}</span>
                                <input v-model="profileForm.locale" type="radio" :value="opt[0]" class="text-indigo-600 focus:ring-indigo-500" />
                            </label>
                            <InputError :message="profileForm.errors.locale" />
                            <div class="flex justify-end">
                                <PrimaryButton class="rounded-full" :disabled="profileForm.processing">{{ t('profile.save') }}</PrimaryButton>
                            </div>
                        </form>
                    </SettingsSection>

                    <SettingsSection
                        :open="open === 'password'" @update:open="toggle('password', $event)"
                        icon="lock" tone="bg-amber-500" :title="t('profile.changePassword')"
                        :has-error="Object.keys(passwordForm.errors).length > 0"
                    >
                        <form @submit.prevent="submitPassword" class="space-y-4">
                            <div>
                                <InputLabel for="old_password" :value="t('profile.currentPassword')" />
                                <TextInput id="old_password" v-model="passwordForm.old_password" type="password" class="mt-1 block w-full rounded-xl" autocomplete="current-password" />
                                <InputError class="mt-2" :message="passwordForm.errors.old_password" />
                            </div>
                            <div>
                                <InputLabel for="new_password" :value="t('profile.newPassword')" />
                                <TextInput id="new_password" v-model="passwordForm.new_password" type="password" class="mt-1 block w-full rounded-xl" autocomplete="new-password" />
                                <InputError class="mt-2" :message="passwordForm.errors.new_password" />
                            </div>
                            <div>
                                <InputLabel for="new_password_confirmation" :value="t('profile.confirmPassword')" />
                                <TextInput id="new_password_confirmation" v-model="passwordForm.new_password_confirmation" type="password" class="mt-1 block w-full rounded-xl" autocomplete="new-password" />
                            </div>
                            <div class="flex justify-end">
                                <PrimaryButton class="rounded-full" :disabled="passwordForm.processing">{{ t('profile.changePassword') }}</PrimaryButton>
                            </div>
                        </form>
                    </SettingsSection>

                    <SettingsSection
                        :open="open === 'devices'" @update:open="toggle('devices', $event)"
                        icon="devices" tone="bg-emerald-500" :title="t('sessions.title')"
                    >
                        <ActiveSessionsPanel bare />
                    </SettingsSection>
                </ChatListCard>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
