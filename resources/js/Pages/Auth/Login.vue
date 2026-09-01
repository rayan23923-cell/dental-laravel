<script setup>
import GoogleSignInButton from '@/Components/GoogleSignInButton.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import IgSpinner from '@/Components/IgSpinner.vue';
import InputError from '@/Components/InputError.vue';
import { Head, Link, usePage, useForm } from '@inertiajs/vue3';
import { ref } from 'vue';

defineProps({
    canResetPassword: { type: Boolean },
    status: { type: String },
});

const page = usePage();

const form = useForm({
    // Accepts either the account's username or its email — see
    // App\Http\Requests\Auth\LoginRequest::authenticate() for how the two
    // are told apart server-side.
    login: '',
    password: '',
    remember: false,
});

// The panel has no hidden state; a password field that can't be revealed is
// the one place a touchscreen user is left guessing.
const showPassword = ref(false);

const submit = () => {
    form.post(route('login'), {
        onFinish: () => form.reset('password'),
    });
};
</script>

<template>
    <GuestLayout>
        <Head title="تسجيل الدخول" />

        <div v-if="status" class="mb-5 rounded-md border border-ig-blue/30 bg-ig-blue/10 px-3 py-2.5 text-center text-sm text-ig-blue">
            {{ status }}
        </div>

        <form @submit.prevent="submit" class="space-y-2">
            <div>
                <input
                    id="login"
                    v-model="form.login"
                    type="text"
                    required
                    autofocus
                    autocomplete="username"
                    dir="ltr"
                    class="w-full rounded-md border border-ig-border-light bg-ig-off-white px-3 py-2.5 text-sm text-ig-near-black placeholder:text-ig-gray focus:border-ig-gray focus:outline-none dark:border-ig-border-dark dark:bg-ig-dark-surface dark:text-ig-off-white"
                    placeholder="اسم المستخدم أو البريد الإلكتروني"
                />
                <InputError class="mt-1.5" :message="form.errors.login" />
            </div>

            <div class="relative">
                <input
                    id="password"
                    v-model="form.password"
                    :type="showPassword ? 'text' : 'password'"
                    required
                    autocomplete="current-password"
                    dir="ltr"
                    class="w-full rounded-md border border-ig-border-light bg-ig-off-white px-3 py-2.5 pl-16 text-sm text-ig-near-black placeholder:text-ig-gray focus:border-ig-gray focus:outline-none dark:border-ig-border-dark dark:bg-ig-dark-surface dark:text-ig-off-white"
                    placeholder="كلمة المرور"
                />
                <button
                    type="button"
                    @click="showPassword = !showPassword"
                    class="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-semibold text-ig-near-black dark:text-ig-off-white"
                >
                    {{ showPassword ? 'إخفاء' : 'إظهار' }}
                </button>
                <InputError class="mt-1.5" :message="form.errors.password" />
            </div>

            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-lg bg-ig-blue py-2.5 text-sm font-semibold text-white transition hover:brightness-105 disabled:cursor-not-allowed disabled:bg-ig-blue/30"
            >
                <IgSpinner v-if="form.processing" :size="16" />
                {{ form.processing ? 'جارٍ الدخول…' : 'دخول' }}
            </button>

            <template v-if="page.props.googleSignInEnabled">
                <div class="flex items-center gap-3 py-2 text-xs font-semibold text-ig-gray">
                    <span class="h-px flex-1 bg-ig-border-light dark:bg-ig-border-dark"></span>
                    أو
                    <span class="h-px flex-1 bg-ig-border-light dark:bg-ig-border-dark"></span>
                </div>
                <GoogleSignInButton />
            </template>

            <label class="flex cursor-pointer items-center gap-2 pt-3 text-sm text-ig-near-black dark:text-ig-off-white">
                <input
                    v-model="form.remember"
                    type="checkbox"
                    class="h-4 w-4 rounded border-ig-border-light text-ig-blue focus:ring-ig-blue/40 dark:border-ig-border-dark"
                />
                تذكّرني
            </label>

            <div class="pt-2 text-center">
                <Link
                    v-if="canResetPassword"
                    :href="route('password.request')"
                    class="text-xs text-ig-near-black hover:underline dark:text-ig-off-white"
                >
                    نسيت كلمة المرور؟
                </Link>
            </div>
        </form>
    </GuestLayout>
</template>
