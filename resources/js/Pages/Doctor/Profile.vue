<script setup>
/**
 * Doctor profile — matches doctor/profile.php: the same two forms as the
 * admin profile (تحديث الملف الشخصي / تغيير كلمة المرور), plus the doctor's
 * read-only stage and study type.
 */
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';
import ActiveSessionsPanel from '@/Components/ActiveSessionsPanel.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ProfileHero from '@/Components/ChatList/ProfileHero.vue';
import SettingsSection from '@/Components/ChatList/SettingsSection.vue';

const { t } = useI18n();
const props = defineProps({
    profile: Object,
});

const preview = ref(props.profile.photo_url);

const profileForm = useForm({
    name: props.profile.name ?? '',
    email: props.profile.email ?? '',
    phone: props.profile.phone ?? '',
    profile_image: null,
});

// Picking a photo from the header saves it straight away, like Instagram.
const onPhoto = (file) => {
    profileForm.profile_image = file;
    preview.value = URL.createObjectURL(file);
    submitProfile();
};

const submitProfile = () => profileForm.post(route('doctor.profile.update'), { preserveScroll: true });

const passwordForm = useForm({
    old_password: '',
    new_password: '',
    new_password_confirmation: '',
});

const submitPassword = () =>
    passwordForm.put(route('doctor.profile.password'), {
        preserveScroll: true,
        onSuccess: () => passwordForm.reset(),
    });

// Telegram-style list (2026-10-14, by request), same as the staff profile.
const open = ref(null);
const toggle = (key, value) => (open.value = value ? key : null);
watch(() => profileForm.errors, (e) => {
    if (e.name || e.email || e.phone) open.value = 'personal';
});
watch(() => passwordForm.errors, (e) => {
    if (Object.keys(e).length) open.value = 'password';
});
</script>

<template>
    <Head :title="t('profile.title')" />

    <DoctorLayout>
        <div class="mx-auto max-w-2xl space-y-5">
            <h2 class="text-lg font-semibold text-gray-800">{{ t('profile.title') }}</h2>

            <ProfileHero
                :photo="preview"
                :name="profile.name"
                :subtitle="profile.username"
                :chips="[profile.education_type, profile.stage].filter(Boolean)"
                :error="profileForm.errors.profile_image"
                @pick="onPhoto"
            />

        <ChatListCard>
            <SettingsSection
                :open="open === 'personal'" @update:open="toggle('personal', $event)"
                icon="person" tone="bg-indigo-500" :title="t('profile.updateProfile')"
                :summary="[profileForm.email, profileForm.phone].filter(Boolean).join(' · ')"
                :has-error="!!(profileForm.errors.name || profileForm.errors.email || profileForm.errors.phone)"
            >
                <form @submit.prevent="submitProfile" class="space-y-4">
                    <div>
                        <InputLabel for="name" :value="t('profile.name')" />
                        <TextInput id="name" v-model="profileForm.name" type="text" class="mt-1 block w-full rounded-xl" required />
                        <InputError class="mt-2" :message="profileForm.errors.name" />
                    </div>
                    <div>
                        <InputLabel for="email" :value="t('profile.email')" />
                        <TextInput id="email" v-model="profileForm.email" type="email" dir="ltr" class="mt-1 block w-full rounded-xl" required />
                        <InputError class="mt-2" :message="profileForm.errors.email" />
                    </div>
                    <div>
                        <InputLabel for="phone" :value="t('profile.phone')" />
                        <TextInput id="phone" v-model="profileForm.phone" type="text" dir="ltr" class="mt-1 block w-full rounded-xl" />
                        <InputError class="mt-2" :message="profileForm.errors.phone" />
                    </div>
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
    </DoctorLayout>
</template>
