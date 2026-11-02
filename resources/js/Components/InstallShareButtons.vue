<script setup>
/**
 * "تثبيت التطبيق" and "مشاركة" (2026-11-02, by request): install the web
 * app on the phone/computer with the clinic logo, or share its link.
 * Where the browser can't install by itself (iPhone Safari, Firefox, or
 * plain http on the clinic network) the button explains the steps.
 */
import Icon from '@/Components/Icon.vue';
import Modal from '@/Components/Modal.vue';
import { installState, isIos, isStandalone } from '@/installPrompt';
import { usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    // 'menu': lines in the account dropdown; 'wide': tiles in the narrow-screen menu.
    variant: { type: String, default: 'menu' },
});

const { t } = useI18n();
const page = usePage();
const help = ref(false);
const copied = ref(false);

const standalone = isStandalone();
const ios = isIos();
const secure = typeof window !== 'undefined' && window.isSecureContext;
const appName = computed(() => document.querySelector('meta[name="app-name"]')?.content || page.props.clinic?.name || '');

const install = async () => {
    if (installState.deferred) {
        const prompt = installState.deferred;
        installState.deferred = null;
        prompt.prompt();
        try {
            await prompt.userChoice;
        } catch {
            /* closed */
        }
        return;
    }
    help.value = true;
};

const share = async () => {
    const url = `${window.location.origin}/`;
    if (navigator.share) {
        try {
            await navigator.share({ title: appName.value, text: appName.value, url });
            return;
        } catch (e) {
            if (e?.name === 'AbortError') return;
        }
    }
    try {
        await navigator.clipboard.writeText(url);
    } catch {
        const box = document.createElement('textarea');
        box.value = url;
        document.body.appendChild(box);
        box.select();
        document.execCommand('copy');
        box.remove();
    }
    copied.value = true;
    setTimeout(() => (copied.value = false), 2500);
};

const lineClass = 'flex w-full items-center gap-2 px-4 py-2 text-start text-sm leading-5 text-gray-700 transition hover:bg-gray-100 focus:bg-gray-100 focus:outline-none';
const tileClass = 'flex w-full items-center gap-2 rounded-xl px-3 py-2 text-sm font-medium text-muted transition hover:bg-surface-2 hover:text-content';
</script>

<template>
    <button v-if="!standalone && !installState.installed" type="button" :class="props.variant === 'wide' ? tileClass : lineClass" @click="install">
        <Icon name="install_mobile" size="text-[18px]" />{{ t('installApp.install') }}
    </button>
    <button type="button" :class="props.variant === 'wide' ? tileClass : lineClass" @click="share">
        <Icon :name="copied ? 'check' : 'share'" size="text-[18px]" />{{ copied ? t('installApp.copied') : t('installApp.share') }}
    </button>

    <Modal :show="help" max-width="md" @close="help = false">
        <div class="flex flex-col gap-3 p-6">
            <h3 class="flex items-center gap-2 text-lg font-semibold text-gray-900">
                <Icon name="install_mobile" />{{ t('installApp.title') }}
            </h3>
            <p class="text-sm text-gray-600">{{ t('installApp.intro') }}</p>
            <div v-if="ios" class="rounded-xl bg-sky-50 p-3 text-sm text-sky-900">
                <p class="mb-1 font-semibold">{{ t('installApp.iosTitle') }}</p>
                <ol class="list-decimal space-y-1 ps-5">
                    <li>{{ t('installApp.ios1') }}</li>
                    <li>{{ t('installApp.ios2') }}</li>
                    <li>{{ t('installApp.ios3') }}</li>
                </ol>
            </div>
            <template v-else>
                <div class="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-900">
                    <p class="mb-1 font-semibold">{{ t('installApp.androidTitle') }}</p>
                    <ol class="list-decimal space-y-1 ps-5">
                        <li>{{ t('installApp.android1') }}</li>
                        <li>{{ t('installApp.android2') }}</li>
                    </ol>
                </div>
                <div class="rounded-xl bg-indigo-50 p-3 text-sm text-indigo-900">
                    <p class="mb-1 font-semibold">{{ t('installApp.desktopTitle') }}</p>
                    <p>{{ t('installApp.desktop1') }}</p>
                </div>
            </template>
            <p v-if="!secure" class="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">{{ t('installApp.httpNote') }}</p>
            <button type="button" class="rounded-xl border border-gray-300 px-4 py-2 font-semibold text-gray-700 hover:bg-gray-50" @click="help = false">
                {{ t('common.close') }}
            </button>
        </div>
    </Modal>
</template>
