<script setup>
// Connection status in the browser (2026-11-01, by request): a bar shows
// when the device has no network, or the server stops answering, and a
// short "connection restored" note when it comes back. The server check
// uses the light /up health route.
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const state = ref('ok'); // ok | offline | serverDown | restored
let timer = null;
let restoredTimer = null;
let checking = false;

const markDown = (next) => {
    clearTimeout(restoredTimer);
    state.value = next;
};
const markUp = () => {
    if (state.value === 'offline' || state.value === 'serverDown') {
        state.value = 'restored';
        clearTimeout(restoredTimer);
        restoredTimer = setTimeout(() => (state.value = 'ok'), 3000);
    }
};

const check = async () => {
    if (checking) return;
    if (!navigator.onLine) return markDown('offline');
    checking = true;
    const ctrl = new AbortController();
    const abort = setTimeout(() => ctrl.abort(), 8000);
    try {
        const res = await fetch('/up', { method: 'HEAD', cache: 'no-store', signal: ctrl.signal });
        res.status < 500 ? markUp() : markDown('serverDown');
    } catch {
        markDown(navigator.onLine ? 'serverDown' : 'offline');
    } finally {
        clearTimeout(abort);
        checking = false;
    }
};

// Checked often while down (to clear the bar soon), rarely while fine.
const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(async () => {
        if (!document.hidden) await check();
        schedule();
    }, state.value === 'ok' || state.value === 'restored' ? 30000 : 5000);
};

const onOffline = () => {
    markDown('offline');
    schedule();
};
const onOnline = () => check().then(schedule);
const onVisible = () => {
    if (!document.hidden) check();
};

onMounted(() => {
    window.addEventListener('offline', onOffline);
    window.addEventListener('online', onOnline);
    document.addEventListener('visibilitychange', onVisible);
    if (!navigator.onLine) state.value = 'offline';
    schedule();
});
onBeforeUnmount(() => {
    window.removeEventListener('offline', onOffline);
    window.removeEventListener('online', onOnline);
    document.removeEventListener('visibilitychange', onVisible);
    clearTimeout(timer);
    clearTimeout(restoredTimer);
});
</script>

<template>
    <Transition
        enter-from-class="-translate-y-full opacity-0"
        leave-to-class="-translate-y-full opacity-0"
        enter-active-class="transition duration-200"
        leave-active-class="transition duration-200"
    >
        <div
            v-if="state !== 'ok'"
            role="status"
            aria-live="polite"
            class="fixed inset-x-0 top-0 z-[9999] flex items-center justify-center gap-3 px-4 py-2 text-center text-sm font-semibold text-white shadow"
            :class="state === 'restored' ? 'bg-green-600' : state === 'offline' ? 'bg-red-600' : 'bg-amber-600'"
        >
            <span>{{ t(`connection.${state}`) }}</span>
            <button
                v-if="state !== 'restored'"
                type="button"
                class="rounded-lg bg-white/20 px-3 py-1 text-xs hover:bg-white/30"
                @click="check().then(schedule)"
            >
                {{ t('connection.retry') }}
            </button>
        </div>
    </Transition>
</template>
