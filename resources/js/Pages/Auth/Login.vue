<script setup>
import GoogleSignInButton from '@/Components/GoogleSignInButton.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
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

        <h2 class="text-lg font-semibold text-content">تسجيل الدخول</h2>
        <p class="mt-1 text-sm text-muted">أدخل اسم المستخدم أو البريد الإلكتروني وكلمة المرور للمتابعة.</p>

        <div v-if="status" class="mt-5 rounded-xl border border-accent/40 bg-accent/10 px-4 py-3 text-sm text-accent">
            {{ status }}
        </div>

        <form @submit.prevent="submit" class="mt-6 space-y-5">
            <div>
                <label for="login" class="mb-1.5 block text-xs font-medium uppercase tracking-wide text-muted">
                    اسم المستخدم أو البريد الإلكتروني
                </label>
                <div class="relative">
                    <Icon name="person" class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-muted" />
                    <input
                        id="login"
                        v-model="form.login"
                        type="text"
                        required
                        autofocus
                        autocomplete="username"
                        dir="ltr"
                        class="w-full rounded-xl border border-hairline bg-surface-2 px-4 py-3 pr-11 text-content placeholder:text-muted/70 focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/40"
                        placeholder="username أو name@clinic.local"
                    />
                </div>
                <InputError class="mt-2" :message="form.errors.login" />
            </div>

            <div>
                <label for="password" class="mb-1.5 block text-xs font-medium uppercase tracking-wide text-muted">
                    كلمة المرور
                </label>
                <div class="relative">
                    <Icon name="lock" class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-muted" />
                    <input
                        id="password"
                        v-model="form.password"
                        :type="showPassword ? 'text' : 'password'"
                        required
                        autocomplete="current-password"
                        dir="ltr"
                        class="w-full rounded-xl border border-hairline bg-surface-2 px-4 py-3 pl-11 pr-11 text-content placeholder:text-muted/70 focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/40"
                        placeholder="••••••••"
                    />
                    <button
                        type="button"
                        @click="showPassword = !showPassword"
                        class="absolute left-2 top-1/2 -translate-y-1/2 rounded-lg p-1.5 text-muted transition hover:bg-surface hover:text-content"
                        :aria-label="showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'"
                    >
                        <Icon :name="showPassword ? 'visibility_off' : 'visibility'" />
                    </button>
                </div>
                <InputError class="mt-2" :message="form.errors.password" />
            </div>

            <div class="flex items-center justify-between">
                <label class="flex cursor-pointer items-center gap-2 text-sm text-muted">
                    <input
                        v-model="form.remember"
                        type="checkbox"
                        class="h-4 w-4 rounded border-hairline bg-surface-2 text-accent focus:ring-accent/40"
                    />
                    تذكّرني
                </label>

                <Link
                    v-if="canResetPassword"
                    :href="route('password.request')"
                    class="text-sm text-accent transition hover:opacity-80"
                >
                    نسيت كلمة المرور؟
                </Link>
            </div>

            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-3 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            >
                <Icon :name="form.processing ? 'progress_activity' : 'login'" :class="form.processing ? 'animate-spin' : ''" />
                {{ form.processing ? 'جارٍ الدخول…' : 'دخول' }}
            </button>

            <template v-if="page.props.googleSignInEnabled">
                <div class="flex items-center gap-3 text-xs text-muted">
                    <span class="h-px flex-1 bg-hairline"></span>
                    أو
                    <span class="h-px flex-1 bg-hairline"></span>
                </div>
                <GoogleSignInButton />
            </template>
        </form>
    </GuestLayout>
</template>
