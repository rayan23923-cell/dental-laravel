<script setup>
import AuthField from '@/Components/AuthField.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, useForm } from '@inertiajs/vue3';


const form = useForm({
    password: '',
});

const submit = () => {
    form.post(route('password.confirm'), {
        onFinish: () => form.reset(),
    });
};
</script>

<template>
    <GuestLayout>
        <Head title="تأكيد كلمة المرور" />

        <h2 class="text-lg font-semibold text-content">تأكيد كلمة المرور</h2>
        <p class="mt-1 text-sm leading-relaxed text-muted">هذه منطقة محمية — أكّد كلمة المرور للمتابعة.</p>

        <form @submit.prevent="submit" class="mt-6 space-y-5">
            <AuthField
                id="password"
                v-model="form.password"
                label="كلمة المرور"
                type="password"
                icon="lock"
                placeholder="••••••••"
                autocomplete="current-password"
                :error="form.errors.password"
                required
                autofocus
            />

            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-3 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            >
                <Icon :name="form.processing ? 'progress_activity' : 'lock_open'" :class="form.processing ? 'animate-spin' : ''" />
                {{ form.processing ? 'جارٍ التأكيد…' : 'تأكيد' }}
            </button>
        </form>
    </GuestLayout>
</template>
