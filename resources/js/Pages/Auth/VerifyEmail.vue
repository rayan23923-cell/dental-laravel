<script setup>
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';
import { computed } from 'vue';

const props = defineProps({
    status: { type: String },
});

const form = useForm({});

const submit = () => {
    form.post(route('verification.send'));
};

const verificationLinkSent = computed(() => props.status === 'verification-link-sent');
</script>

<template>
    <GuestLayout>
        <Head title="تأكيد البريد الإلكتروني" />

        <h2 class="text-lg font-semibold text-content">تأكيد البريد الإلكتروني</h2>
        <p class="mt-1 text-sm leading-relaxed text-muted">
            أرسلنا رابط تأكيد إلى بريدك الإلكتروني. افتح الرابط لتفعيل حسابك، وإن لم يصلك فبإمكانك طلب رابط جديد.
        </p>

        <div v-if="verificationLinkSent" class="mt-5 rounded-xl border border-accent/40 bg-accent/10 px-4 py-3 text-sm text-accent">
            تم إرسال رابط تأكيد جديد إلى بريدك الإلكتروني.
        </div>

        <form @submit.prevent="submit" class="mt-6 space-y-5">
            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-3 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            >
                <Icon :name="form.processing ? 'progress_activity' : 'forward_to_inbox'" :class="form.processing ? 'animate-spin' : ''" />
                {{ form.processing ? 'جارٍ الإرسال…' : 'إعادة إرسال الرابط' }}
            </button>

            <Link
                :href="route('logout')"
                method="post"
                as="button"
                class="block w-full text-center text-sm text-muted transition hover:text-content"
            >
                تسجيل الخروج
            </Link>
        </form>
    </GuestLayout>
</template>
