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
import { ref } from 'vue';
import Icon from '@/Components/Icon.vue';
import ActiveSessionsPanel from '@/Components/ActiveSessionsPanel.vue';

const props = defineProps({
    profile: Object,
    status: String,
});

const page = usePage();
const preview = ref(props.profile.photo_url);

const profileForm = useForm({
    full_name: props.profile.full_name ?? '',
    email: props.profile.email ?? '',
    phone: props.profile.phone ?? '',
    profile_image: null,
});

const onPhoto = (event) => {
    const file = event.target.files[0];
    profileForm.profile_image = file;
    if (file) preview.value = URL.createObjectURL(file);
};

const submitProfile = () => profileForm.post(route('profile.update'), { preserveScroll: true });

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
</script>

<template>
    <Head title="الملف الشخصي" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">الملف الشخصي</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-3xl space-y-6 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="status" class="rounded-md bg-green-50 p-4 text-sm text-green-700">{{ status }}</div>

                <!-- Identity summary -->
                <div class="flex items-center gap-4 rounded-lg bg-white p-6 shadow-sm">
                    <img v-if="preview" :src="preview" class="h-20 w-20 rounded-full object-cover" />
                    <div v-else class="flex h-20 w-20 items-center justify-center rounded-full bg-gray-100 text-2xl"><Icon name="person" class="ml-1" /></div>
                    <div>
                        <div class="text-lg font-semibold text-gray-900">{{ profile.full_name }}</div>
                        <div class="text-sm text-gray-500">{{ profile.username }}</div>
                        <span class="mt-1 inline-block rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ profile.role }}</span>
                    </div>
                </div>

                <!-- تحديث الملف الشخصي -->
                <form @submit.prevent="submitProfile" class="space-y-4 rounded-lg bg-white p-6 shadow-sm">
                    <h3 class="text-sm font-semibold text-gray-700">تحديث الملف الشخصي</h3>

                    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                        <div>
                            <InputLabel for="full_name" value="الاسم" />
                            <TextInput id="full_name" v-model="profileForm.full_name" type="text" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="profileForm.errors.full_name" />
                        </div>
                        <div>
                            <InputLabel for="email" value="البريد الإلكتروني" />
                            <TextInput id="email" v-model="profileForm.email" type="email" class="mt-1 block w-full" required />
                            <InputError class="mt-2" :message="profileForm.errors.email" />
                        </div>
                        <div>
                            <InputLabel for="phone" value="رقم الهاتف" />
                            <TextInput id="phone" v-model="profileForm.phone" type="text" class="mt-1 block w-full" />
                            <InputError class="mt-2" :message="profileForm.errors.phone" />
                        </div>
                        <div>
                            <InputLabel for="profile_image" value="الصورة الشخصية" />
                            <input id="profile_image" type="file" accept="image/*" class="mt-1 block w-full text-sm text-gray-700" @input="onPhoto" />
                            <InputError class="mt-2" :message="profileForm.errors.profile_image" />
                        </div>
                    </div>

                    <div class="flex justify-end">
                        <PrimaryButton :disabled="profileForm.processing">حفظ</PrimaryButton>
                    </div>
                </form>

                <!-- تغيير كلمة المرور -->
                <form @submit.prevent="submitPassword" class="space-y-4 rounded-lg bg-white p-6 shadow-sm">
                    <h3 class="text-sm font-semibold text-gray-700">تغيير كلمة المرور</h3>

                    <div>
                        <InputLabel for="old_password" value="كلمة المرور الحالية" />
                        <TextInput id="old_password" v-model="passwordForm.old_password" type="password" class="mt-1 block w-full" autocomplete="current-password" />
                        <InputError class="mt-2" :message="passwordForm.errors.old_password" />
                    </div>

                    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                        <div>
                            <InputLabel for="new_password" value="كلمة المرور الجديدة" />
                            <TextInput id="new_password" v-model="passwordForm.new_password" type="password" class="mt-1 block w-full" autocomplete="new-password" />
                            <InputError class="mt-2" :message="passwordForm.errors.new_password" />
                        </div>
                        <div>
                            <InputLabel for="new_password_confirmation" value="تأكيد كلمة المرور" />
                            <TextInput id="new_password_confirmation" v-model="passwordForm.new_password_confirmation" type="password" class="mt-1 block w-full" autocomplete="new-password" />
                        </div>
                    </div>

                    <div class="flex justify-end">
                        <PrimaryButton :disabled="passwordForm.processing">تغيير كلمة المرور</PrimaryButton>
                    </div>
                </form>

                <ActiveSessionsPanel />
            </div>
        </div>
    </AuthenticatedLayout>
</template>
