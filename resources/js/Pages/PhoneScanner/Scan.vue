<script setup>
/**
 * The phone as the computer's QR scanner (2026-10-12, by request). The
 * camera keeps scanning (with camera switch and flash from QrScanner) and
 * every code is posted to the pairing; the computer polls for it.
 */
import Icon from '@/Components/Icon.vue';
import QrScanner from '@/Components/QrScanner.vue';
import { Head } from '@inertiajs/vue3';
import axios from 'axios';
import { computed, nextTick, onMounted, ref } from 'vue';
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

onMounted(async () => {
    await nextTick();
    scanner.value?.start();
});

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
        if (e?.response?.status === 410) {
            expired.value = true;
            scanner.value?.stop();
        }
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

            <div v-else class="rounded-2xl bg-white p-3 text-gray-900">
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
