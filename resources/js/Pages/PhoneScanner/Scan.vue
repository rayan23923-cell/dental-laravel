<script setup>
/**
 * The phone as the computer's QR scanner (2026-10-12, by request). The
 * camera keeps scanning (with camera switch and flash from QrScanner) and
 * every code is posted to the pairing; the computer polls for it.
 *
 * When the computer asks for a photo (2026-10-13, a task's paper form),
 * the request shows here with a camera button; the photo is shrunk and
 * sent, and the computer attaches it.
 */
import Icon from '@/Components/Icon.vue';
import QrScanner from '@/Components/QrScanner.vue';
import { Head } from '@inertiajs/vue3';
import axios from 'axios';
import { shrinkImage } from '@/shrinkImage';
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    token: String,
    userName: String,
    expiresAt: String,
});

const { t, locale } = useI18n();
const scanner = ref(null);
const sent = ref([]); // { id, payload, status: 'sending' | 'sent' | 'failed' }
const expired = ref(false);
let seq = 0;

const expiresLabel = computed(() =>
    new Date(props.expiresAt).toLocaleTimeString(locale.value === 'ar' ? 'ar-IQ' : 'en-GB', { hour: '2-digit', minute: '2-digit' }),
);

const photoRequest = ref(null);
const photoInput = ref(null);
const photoState = ref(''); // '' | 'sending' | 'sent' | 'failed'
let statusTimer = null;

const markExpired = () => {
    expired.value = true;
    scanner.value?.stop();
    clearInterval(statusTimer);
};

const checkStatus = async () => {
    try {
        const { data } = await axios.get(route('phone-scanner.status', props.token));
        photoRequest.value = data.data.photo_request;
    } catch (e) {
        if (e?.response?.status === 410) markExpired();
    }
};

onMounted(async () => {
    await nextTick();
    scanner.value?.start();
    checkStatus();
    statusTimer = setInterval(checkStatus, 2000);
});
onBeforeUnmount(() => clearInterval(statusTimer));

// The camera app can't open while the scanner holds the camera; it
// comes back when the page does, whether a photo was taken or not.
const resumeScanner = () =>
    setTimeout(() => {
        if (!expired.value && photoState.value !== 'sending' && !scanner.value?.scanning) scanner.value?.start();
    }, 1000);
const takePhoto = () => {
    scanner.value?.stop();
    window.addEventListener('focus', resumeScanner, { once: true });
    photoInput.value.click();
};

const sendPhoto = async (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) {
        scanner.value?.start();
        return;
    }
    photoState.value = 'sending';
    try {
        const form = new FormData();
        form.append('photo', await shrinkImage(file));
        await axios.post(route('phone-scanner.photo', props.token), form);
        photoState.value = 'sent';
        photoRequest.value = null;
        navigator.vibrate?.(80);
        setTimeout(() => {
            if (photoState.value === 'sent') photoState.value = '';
        }, 2500);
    } catch (e) {
        photoState.value = 'failed';
        if (e?.response?.status === 410) markExpired();
    }
    if (!expired.value && !scanner.value?.scanning) scanner.value?.start();
};

const send = async (payload) => {
    if (expired.value) return;
    const item = { id: ++seq, payload, status: 'sending' };
    sent.value.unshift(item);
    sent.value = sent.value.slice(0, 20);
    try {
        await axios.post(route('phone-scanner.store', props.token), { payload });
        item.status = 'sent';
        navigator.vibrate?.(80);
    } catch (e) {
        item.status = 'failed';
        if (e?.response?.status === 410) markExpired();
    }
    sent.value = [...sent.value];
};
</script>

<template>
    <Head :title="t('phoneScanner.scanTitle')" />

    <div class="min-h-screen bg-slate-900 px-3 py-4 text-white" dir="rtl">
        <div class="mx-auto max-w-md">
            <header class="mb-3 flex items-center gap-2">
                <Icon name="qr_code_scanner" class="text-3xl text-emerald-400" />
                <div>
                    <h1 class="text-lg font-bold">{{ t('phoneScanner.scanTitle') }}</h1>
                    <p v-if="userName" class="text-xs text-white/70">{{ t('phoneScanner.linkedTo', { name: userName }) }}</p>
                </div>
            </header>

            <div v-if="expired" class="rounded-xl bg-rose-600/20 p-4 text-center text-sm text-rose-100">
                <Icon name="link_off" class="text-3xl" />
                <p class="mt-2">{{ t('phoneScanner.expired') }}</p>
            </div>

            <template v-else>
                <div v-if="photoRequest" class="mb-3 rounded-2xl bg-emerald-600 p-4 text-center shadow-lg">
                    <p class="text-sm text-emerald-50">{{ t('phoneScanner.photoRequested') }}</p>
                    <p class="mt-1 text-base font-bold">{{ photoRequest }}</p>
                    <button
                        type="button"
                        class="mt-3 inline-flex w-full items-center justify-center rounded-xl bg-white px-4 py-3 text-lg font-bold text-emerald-700 active:bg-emerald-50"
                        :disabled="photoState === 'sending'"
                        @click="takePhoto"
                    >
                        <Icon name="photo_camera" class="ml-2 text-2xl" />{{ t('phoneScanner.takePhoto') }}
                    </button>
                </div>
                <p v-if="photoState === 'sending'" class="mb-3 rounded-xl bg-amber-500/20 p-3 text-center text-sm text-amber-100">{{ t('phoneScanner.photoSending') }}</p>
                <p v-else-if="photoState === 'sent'" class="mb-3 rounded-xl bg-emerald-500/20 p-3 text-center text-sm text-emerald-100">
                    <Icon name="check_circle" class="ml-1" />{{ t('phoneScanner.photoSent') }}
                </p>
                <p v-else-if="photoState === 'failed'" class="mb-3 rounded-xl bg-rose-600/20 p-3 text-center text-sm text-rose-100">{{ t('phoneScanner.photoFailed') }}</p>
                <input ref="photoInput" type="file" accept="image/*" capture="environment" class="hidden" @change="sendPhoto" />
            </template>

            <div v-if="!expired" class="rounded-2xl bg-white p-3 text-gray-900">
                <QrScanner ref="scanner" continuous @decoded="send" />
            </div>

            <p v-if="!expired" class="mt-2 text-center text-xs text-white/50">{{ t('phoneScanner.expiresAt', { time: expiresLabel }) }}</p>

            <section class="mt-4">
                <h2 class="mb-2 text-sm font-semibold text-white/80">{{ t('phoneScanner.history') }}</h2>
                <p v-if="!sent.length" class="rounded-xl bg-white/5 p-4 text-center text-sm text-white/60">{{ t('phoneScanner.none') }}</p>
                <ul v-else class="space-y-2">
                    <li v-for="item in sent" :key="item.id" class="flex items-center gap-2 rounded-xl bg-white/10 p-3">
                        <Icon
                            :name="item.status === 'sent' ? 'check_circle' : item.status === 'failed' ? 'error' : 'schedule'"
                            :class="item.status === 'sent' ? 'text-emerald-400' : item.status === 'failed' ? 'text-rose-400' : 'text-amber-300'"
                        />
                        <span class="min-w-0 flex-1 truncate font-mono text-xs" dir="ltr">{{ item.payload }}</span>
                        <span class="shrink-0 text-xs text-white/60">
                            {{ item.status === 'sent' ? t('phoneScanner.sent') : item.status === 'failed' ? t('phoneScanner.sendFailed') : t('phoneScanner.sending') }}
                        </span>
                    </li>
                </ul>
            </section>
        </div>
    </div>
</template>
