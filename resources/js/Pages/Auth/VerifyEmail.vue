<script setup>
import TgSpinner from '@/Components/TgSpinner.vue';
import GuestLayout from '@/Layouts/GuestLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
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
        <Head :title="t('authPages.verifyEmailTitle')" />

        <h2 class="text-lg font-semibold text-content">{{ t('authPages.verifyEmailHeading') }}</h2>
        <p class="mt-1 text-sm leading-relaxed text-muted">
            {{ t('authPages.verifyEmailDescription') }}
        </p>

        <div v-if="verificationLinkSent" class="mt-5 rounded-xl border border-accent/40 bg-accent/10 px-4 py-3 text-sm text-accent">
            {{ t('authPages.verifyEmailLinkSentMsg') }}
        </div>

        <form @submit.prevent="submit" class="mt-6 space-y-5">
            <button
                type="submit"
                :disabled="form.processing"
                class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-3 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
            >
                <TgSpinner v-if="form.processing" :size="20" />
                <Icon v-else name="forward_to_inbox" />
                {{ form.processing ? t('authPages.resendingLink') : t('authPages.resendLinkButton') }}
            </button>

            <Link
                :href="route('logout')"
                method="post"
                as="button"
                class="block w-full text-center text-sm text-muted transition hover:text-content"
            >
                {{ t('authPages.logout') }}
            </Link>
        </form>
    </GuestLayout>
</template>
