<script setup>
/**
 * "ربط الموبايل كماسح" (2026-10-12, by request): a header button that
 * pairs a phone as this computer's QR scanner. The modal shows a QR that
 * opens the phone's scanner page, and a six-digit code for typing at
 * /scan instead. Codes the phone reads arrive through remoteScanner.js.
 */
import Icon from '@/Components/Icon.vue';
import Modal from '@/Components/Modal.vue';
import { closeRemoteScanner, openRemoteScanner, remoteScanner, restoreRemoteScanner } from '@/remoteScanner';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const open = ref(false);
const busy = ref(false);
const error = ref('');
const copied = ref(false);

onMounted(restoreRemoteScanner);

const pairing = computed(() => remoteScanner.pairing);
const connected = computed(() => !!pairing.value?.phone_joined);

const show = async () => {
    open.value = true;
    if (pairing.value) return;
    busy.value = true;
    error.value = '';
    try {
        await openRemoteScanner();
    } catch (e) {
        error.value = e?.response?.data?.message ?? t('phoneScanner.openFailed');
    } finally {
        busy.value = false;
    }
};

const end = async () => {
    await closeRemoteScanner();
    open.value = false;
};

const renew = async () => {
    busy.value = true;
    try {
        await closeRemoteScanner();
        await openRemoteScanner();
    } finally {
        busy.value = false;
    }
};

const copyUnhandled = async () => {
    try {
        await navigator.clipboard.writeText(remoteScanner.unhandled);
        copied.value = true;
        setTimeout(() => (copied.value = false), 1500);
    } catch {
        // Clipboard blocked: the code is still shown for copying by hand.
    }
};
</script>

<template>
    <button
        type="button"
        @click="show"
        class="relative inline-flex items-center gap-1.5 rounded-xl border px-3 py-2 text-sm font-medium transition"
        :class="pairing ? (connected ? 'border-emerald-500/60 bg-emerald-500/15 text-emerald-500' : 'border-amber-500/60 bg-amber-500/15 text-amber-500') : 'border-hairline/70 bg-surface-2 text-content hover:border-accent/50'"
        :title="t('phoneScanner.button')"
    >
        <Icon name="phonelink_ring" size="text-[18px]" />
        <span class="hidden xl:inline">{{ pairing ? (connected ? t('phoneScanner.connectedShort') : t('phoneScanner.waitingShort')) : t('phoneScanner.button') }}</span>
        <span v-if="remoteScanner.unhandled" class="absolute -top-1 -left-1 h-3 w-3 rounded-full bg-rose-500"></span>
    </button>

    <Modal :show="open" @close="open = false" max-width="md">
        <div class="flex flex-col items-center gap-4 p-6 text-center">
            <h2 class="text-lg font-semibold text-gray-900">{{ t('phoneScanner.title') }}</h2>
            <p class="text-sm text-gray-500">{{ t('phoneScanner.howTo') }}</p>

            <div v-if="busy" class="py-16 text-sm text-gray-500">{{ t('common.loading') }}</div>
            <div v-else-if="error" class="w-full rounded-md bg-red-50 p-3 text-sm text-red-700">{{ error }}</div>

            <template v-else-if="pairing">
                <img :src="pairing.qr" :alt="t('phoneScanner.qrAlt')" class="h-56 w-56 rounded-lg border" />

                <div>
                    <p class="text-xs text-gray-500">{{ t('phoneScanner.orCode') }}</p>
                    <p class="mt-1 font-mono text-3xl font-bold tracking-[0.4em] text-gray-900" dir="ltr">{{ pairing.code }}</p>
                    <p class="mt-1 text-xs text-gray-400" dir="ltr">{{ pairing.enter_url }}</p>
                </div>

                <div
                    class="w-full rounded-md p-3 text-sm font-semibold"
                    :class="connected ? 'bg-emerald-50 text-emerald-800' : 'bg-amber-50 text-amber-800'"
                >
                    <Icon :name="connected ? 'check_circle' : 'hourglass_empty'" class="ml-1" />
                    {{ connected ? t('phoneScanner.connected') : t('phoneScanner.waiting') }}
                </div>

                <div v-if="remoteScanner.lastScan" class="w-full rounded-md bg-gray-50 p-3 text-right text-sm text-gray-700">
                    <p class="text-xs text-gray-500">{{ t('phoneScanner.lastScan') }}</p>
                    <p class="mt-1 break-all font-mono text-xs" dir="ltr">{{ remoteScanner.lastScan.payload }}</p>
                    <p v-if="remoteScanner.unhandled" class="mt-2 text-xs text-amber-700">
                        {{ t('phoneScanner.unhandled') }}
                        <button type="button" class="mr-1 text-indigo-600 hover:underline" @click="copyUnhandled">{{ copied ? t('phoneScanner.copied') : t('phoneScanner.copy') }}</button>
                    </p>
                </div>

                <div class="flex w-full flex-wrap justify-center gap-2">
                    <button type="button" @click="open = false" class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">{{ t('common.close') }}</button>
                    <button type="button" @click="renew" class="rounded-md border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50">{{ t('phoneScanner.newCode') }}</button>
                    <button type="button" @click="end" class="rounded-md border border-red-300 px-4 py-2 text-sm text-red-700 hover:bg-red-50">{{ t('phoneScanner.end') }}</button>
                </div>
            </template>
        </div>
    </Modal>
</template>
