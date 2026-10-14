<script setup>
/**
 * Notification bell (2026-10-14, by request): polls the signed-in staff
 * member's or doctor's notifications, and when a new one arrives (a task
 * start request, or its approval or turn-down) plays a short chime and
 * shows it as a toast. Opening the list marks everything read. The app's
 * inbox gets the same notifications, with the same sound.
 */
import axios from 'axios';
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';

const props = defineProps({
    doctor: { type: Boolean, default: false },
});

const { t } = useI18n();
const items = ref([]);
const unread = ref(0);
const open = ref(false);
const toast = ref(null);
let seen = null; // ids already known, so only new ones chime
let timer = null;
let toastTimer = null;

const feedRoute = computed(() => (props.doctor ? 'doctor.notifications.index' : 'notifications.index'));
const readRoute = computed(() => (props.doctor ? 'doctor.notifications.read-all' : 'notifications.read-all'));

// A short two-note chime made with Web Audio, so there's no sound file to ship.
const chime = () => {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        [880, 1318.5].forEach((freq, i) => {
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();
            osc.type = 'sine';
            osc.frequency.value = freq;
            const start = ctx.currentTime + i * 0.18;
            gain.gain.setValueAtTime(0.0001, start);
            gain.gain.exponentialRampToValueAtTime(0.3, start + 0.02);
            gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.35);
            osc.connect(gain).connect(ctx.destination);
            osc.start(start);
            osc.stop(start + 0.4);
        });
        setTimeout(() => ctx.close(), 1000);
    } catch {
        // No audio available — the toast still shows.
    }
};

const load = async () => {
    if (document.visibilityState !== 'visible') return;
    try {
        const { data } = await axios.get(route(feedRoute.value));
        const fresh = seen ? data.data.filter((n) => !n.read_at && !seen.has(n.id)) : [];
        seen = new Set(data.data.map((n) => n.id));
        items.value = data.data;
        unread.value = data.unread;
        if (fresh.length) {
            chime();
            toast.value = fresh[0];
            clearTimeout(toastTimer);
            toastTimer = setTimeout(() => (toast.value = null), 8000);
        }
    } catch {
        // Try again on the next tick.
    }
};

const toggle = async () => {
    open.value = !open.value;
    if (open.value && unread.value) {
        unread.value = 0;
        await axios.post(route(readRoute.value)).catch(() => {});
    }
};

const fmt = (v) => (v ? new Date(v).toLocaleString(t('sessions.dateLocale'), { dateStyle: 'short', timeStyle: 'short' }) : '');

onMounted(() => {
    load();
    timer = setInterval(load, 15000);
    document.addEventListener('visibilitychange', load);
});
onBeforeUnmount(() => {
    clearInterval(timer);
    clearTimeout(toastTimer);
    document.removeEventListener('visibilitychange', load);
});
</script>

<template>
    <div class="relative">
        <button
            type="button"
            class="relative flex h-9 w-9 items-center justify-center rounded-xl border border-hairline/70 bg-surface-2 text-content transition hover:border-accent/50"
            :aria-label="t('notificationsBell.title')"
            @click="toggle"
        >
            <Icon name="notifications" size="text-[20px]" />
            <span
                v-if="unread > 0"
                class="absolute -end-1 -top-1 min-w-[1.1rem] rounded-full bg-red-500 px-1 text-center text-[10px] font-bold leading-[1.1rem] text-white"
            >{{ unread > 99 ? '99+' : unread }}</span>
        </button>

        <div v-if="open" class="fixed inset-0 z-40" @click="open = false"></div>
        <div
            v-if="open"
            class="fixed inset-x-4 top-20 z-50 overflow-hidden rounded-xl border border-hairline/70 bg-surface shadow-panel sm:absolute sm:inset-x-auto sm:end-0 sm:top-auto sm:mt-2 sm:w-80"
        >
            <div class="border-b border-hairline/70 px-4 py-2.5 text-sm font-semibold text-content">{{ t('notificationsBell.title') }}</div>
            <div class="max-h-[70vh] overflow-y-auto sm:max-h-96">
                <div v-if="!items.length" class="px-4 py-8 text-center text-sm text-muted">{{ t('notificationsBell.empty') }}</div>
                <div
                    v-for="n in items"
                    :key="n.id"
                    class="border-b border-hairline/50 px-4 py-2.5 last:border-b-0"
                    :class="n.read_at ? '' : 'bg-accent/5'"
                >
                    <div class="text-sm font-medium text-content">{{ n.title }}</div>
                    <div class="text-xs text-muted">{{ n.message }}</div>
                    <div class="mt-0.5 text-[11px] text-muted/80">{{ fmt(n.created_at) }}</div>
                </div>
            </div>
        </div>

        <!-- New notification toast -->
        <transition
            enter-active-class="transition duration-200"
            enter-from-class="translate-y-2 opacity-0"
            leave-active-class="transition duration-200"
            leave-to-class="translate-y-2 opacity-0"
        >
            <div
                v-if="toast"
                class="fixed bottom-4 left-1/2 z-[60] flex w-[min(24rem,calc(100vw-2rem))] -translate-x-1/2 cursor-pointer items-start gap-3 rounded-2xl bg-gray-900 px-4 py-3 text-white shadow-xl"
                @click="toast = null; toggle()"
            >
                <Icon name="notifications_active" size="text-[22px]" class="text-amber-300" />
                <div class="min-w-0">
                    <div class="text-sm font-semibold">{{ toast.title }}</div>
                    <div class="text-xs text-gray-300">{{ toast.message }}</div>
                </div>
            </div>
        </transition>
    </div>
</template>
