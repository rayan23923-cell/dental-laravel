<script setup>
import { Head } from '@inertiajs/vue3';
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

// Persisted so a TV reload doesn't lose its pairing and fall back to
// showing the QR again — see Api\WaitingScreenController's own docblock:
// a *confirmed* pairing is kept indefinitely, only a still-pending one can
// go stale. `localStorage` is per-browser/per-device, exactly the "this
// physical screen" scope a pairing is meant to have.
const STORAGE_KEY = 'waiting_screen_pairing_token';

const paired = ref(null); // null = not yet known, true/false once the first response lands
const pairingToken = ref(localStorage.getItem(STORAGE_KEY) ?? '');
const pairingCode = ref(null);

const clinicName = ref('');
const logoUrl = ref(null);
const stageName = ref(null);
const groupName = ref(null);
const appointments = ref([]);
// Lab patients (2026-11-02): samples sheet printed ('waiting') or result
// recorded and not yet collected ('ready').
const labPatients = ref([]);
const patientsPerPage = ref(8);
const rotationSeconds = ref(12);
const currentPage = ref(0);
// The clock follows the server's time (2026-11-02, by request): a TV's own
// clock is often wrong or never set. `serverOffset` is server minus TV, in
// ms, from every reply; the TV clock is only used until the first one.
let serverOffset = 0;
// …and its time zone, so a TV set to another zone still shows clinic time.
const serverTimezone = ref(null);
const tzOption = () => {
    if (!serverTimezone.value) return {};
    try {
        Intl.DateTimeFormat('en', { timeZone: serverTimezone.value });
        return { timeZone: serverTimezone.value };
    } catch {
        return {};
    }
};
const serverNow = () => new Date(Date.now() + serverOffset);
const now = ref(serverNow());

// Unattended TV (2026-11-02, by request): the screen keeps showing the last
// list while the network is down, retries on its own (sooner when the
// browser says it is back online) and shows a small "reconnecting" badge.
const connectionLost = ref(false);
let failingSince = null;

// The logo as a path on this same server (2026-11-02, by request): an
// absolute link may point at https://clinic.lan while the TV opened the
// page over http (or by IP), and then the logo never loads.
const sameOriginPath = (url) => {
    if (!url) return null;
    try {
        const parsed = new URL(url, window.location.href);
        return parsed.pathname.startsWith('/storage/') ? parsed.pathname + parsed.search : parsed.href;
    } catch {
        return url;
    }
};
const logoFailed = ref(false);

let dataTimer = null;
let clockTimer = null;
let rotateTimer = null;
let scheduledRotationSeconds = null;

const qrUrl = computed(() =>
    pairingToken.value ? `/api/v1/waiting-screen/pairings/${pairingToken.value}/qr?size=360` : null,
);

// Chunked into fixed-size pages (admin-controlled, see
// WaitingScreenSettings/Edit.vue) rather than one long scrolling list —
// a waiting-room TV is read from across a room, so each page needs to
// stay large-print and glanceable.
// The screen shows the lab only (2026-11-02, by request), so the pages
// rotate through the lab list; its cards are smaller, hence 12 a page.
const LAB_PER_PAGE = 12;
const pages = computed(() => {
    const size = LAB_PER_PAGE;
    const chunks = [];
    for (let i = 0; i < labPatients.value.length; i += size) {
        chunks.push(labPatients.value.slice(i, i + size));
    }
    return chunks.length ? chunks : [[]];
});

// One lab list (2026-11-02, by request): a card stays in place and turns
// from amber "بانتظار الفحص" to green "النتيجة جاهزة".
const labCounts = computed(() => ({
    ready: labPatients.value.filter((p) => p.status === 'ready').length,
    waiting: labPatients.value.filter((p) => p.status !== 'ready').length,
}));

const currentPageItems = computed(() => pages.value[currentPage.value] ?? []);

const timeString = computed(() =>
    now.value.toLocaleTimeString('ar-IQ', { hour: '2-digit', minute: '2-digit', ...tzOption() }),
);
const dateString = computed(() =>
    now.value.toLocaleDateString('ar-IQ', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', ...tzOption() }),
);

// Called after every 4s data refresh, so it must be a no-op when nothing
// changed — re-arming on every call would clear+recreate the interval
// before its own (typically 12s) period ever elapses, permanently
// preventing rotation from firing at all. Only reschedule when the
// admin-configured interval itself changes.
const scheduleRotation = () => {
    const seconds = rotationSeconds.value || 12;
    if (rotateTimer && scheduledRotationSeconds === seconds) return;
    scheduledRotationSeconds = seconds;
    if (rotateTimer) clearInterval(rotateTimer);
    rotateTimer = setInterval(() => {
        if (pages.value.length > 1) {
            currentPage.value = (currentPage.value + 1) % pages.value.length;
        }
    }, seconds * 1000);
};

let loading = false;
const load = async () => {
    if (loading) return;
    loading = true;
    let data;
    try {
        ({ data } = await window.axios.get('/api/v1/waiting-screen', {
            params: pairingToken.value ? { token: pairingToken.value } : {},
            timeout: 10000,
        }));
    } catch {
        connectionLost.value = true;
        failingSince ??= Date.now();
        return;
    } finally {
        loading = false;
    }

    if (connectionLost.value) {
        connectionLost.value = false;
        logoFailed.value = false;
        // Down for over a minute: the server may have been updated
        // meanwhile, so reload once to pick up the new page as well.
        if (failingSince && Date.now() - failingSince > 60_000) {
            window.location.reload();
            return;
        }
    }
    failingSince = null;

    if (data.server_time) {
        serverOffset = Number(data.server_time) - Date.now();
        serverTimezone.value = data.timezone ?? null;
        now.value = serverNow();
    }

    // The server always echoes back the token it actually used — it
    // issues a fresh one whenever ours was missing/unknown/stale, so this
    // keeps the browser in sync without the client needing its own
    // expiry logic.
    if (data.token && data.token !== pairingToken.value) {
        pairingToken.value = data.token;
        localStorage.setItem(STORAGE_KEY, data.token);
    }

    paired.value = data.paired;
    if (!data.paired) {
        pairingCode.value = data.code ?? null;
        return;
    }

    clinicName.value = data.clinic_name;
    logoUrl.value = sameOriginPath(data.logo_url);
    stageName.value = data.stage_name;
    groupName.value = data.group_name;
    appointments.value = data.appointments;
    labPatients.value = data.lab ?? [];
    patientsPerPage.value = data.patients_per_page;
    rotationSeconds.value = data.rotation_seconds;

    if (currentPage.value >= pages.value.length) {
        currentPage.value = 0;
    }
    scheduleRotation();
};

const rePair = () => {
    localStorage.removeItem(STORAGE_KEY);
    pairingToken.value = '';
    paired.value = null;
    load();
};

// Two independent timers: the clock ticks every second regardless, while
// the data refetch also doubles as the pairing-status poll — fast (4s)
// while unpaired so scanning the QR feels instant, backed off to 30s once
// paired since it's then just catching new/edited appointments.
// Keeps the TV from dimming or sleeping while the page is open, where the
// browser supports it (re-taken whenever the page becomes visible again).
let wakeLock = null;
const keepAwake = async () => {
    try {
        if ('wakeLock' in navigator && document.visibilityState === 'visible') {
            wakeLock = await navigator.wakeLock.request('screen');
        }
    } catch {
        wakeLock = null;
    }
};
const onVisible = () => {
    if (document.visibilityState === 'visible') {
        keepAwake();
        load();
    }
};
// Full screen with the first press of the remote (browsers only allow it
// after a key press or tap).
const goFullscreen = () => {
    const el = document.documentElement;
    if (!document.fullscreenElement && el.requestFullscreen) {
        el.requestFullscreen().catch(() => {});
    }
};

onMounted(() => {
    load();
    dataTimer = setInterval(load, 4000);
    clockTimer = setInterval(() => {
        now.value = serverNow();
    }, 1000);
    keepAwake();
    window.addEventListener('online', load);
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('keydown', goFullscreen);
    window.addEventListener('click', goFullscreen);
});

onBeforeUnmount(() => {
    window.removeEventListener('online', load);
    document.removeEventListener('visibilitychange', onVisible);
    window.removeEventListener('keydown', goFullscreen);
    window.removeEventListener('click', goFullscreen);
    wakeLock?.release?.().catch(() => {});
    if (dataTimer) clearInterval(dataTimer);
    if (clockTimer) clearInterval(clockTimer);
    if (rotateTimer) clearInterval(rotateTimer);
});
</script>

<template>
    <Head :title="t('waitingScreen.title')" />

    <div
        dir="rtl"
        class="flex min-h-screen flex-col bg-ig-off-white text-ig-near-black dark:bg-ig-dark-surface dark:text-ig-off-white"
    >
        <template v-if="paired === false">
            <div class="flex flex-1 flex-col items-center justify-center gap-6 px-8 py-12 text-center">
                <div class="rounded-3xl bg-ig-gradient p-1 shadow-xl">
                    <div class="rounded-[1.35rem] bg-white p-6">
                        <img v-if="qrUrl" :src="qrUrl" alt="" class="h-72 w-72" />
                    </div>
                </div>
                <h1 class="text-3xl font-bold sm:text-4xl">{{ t('waitingScreen.scanToPairHeading') }}</h1>
                <p class="max-w-lg text-lg text-ig-gray">{{ t('waitingScreen.scanToPairSubtext') }}</p>
                <div v-if="pairingCode" class="flex flex-col items-center gap-1">
                    <span class="text-sm text-ig-gray">{{ t('waitingScreen.codeCaption') }}</span>
                    <span class="rounded-xl border border-ig-border-light bg-white px-6 py-2 text-4xl font-bold tracking-[0.4em] dark:border-ig-border-dark dark:bg-ig-black">
                        {{ pairingCode }}
                    </span>
                </div>
                <div class="mt-4 text-2xl font-semibold tabular-nums text-ig-gray">{{ timeString }}</div>
            </div>
        </template>

        <template v-else-if="paired === true">
            <header class="bg-ig-gradient px-10 py-6 text-white shadow-lg">
                <div class="mx-auto flex max-w-7xl items-center justify-between">
                    <div class="flex items-center gap-4">
                        <img
                            v-if="logoUrl && !logoFailed"
                            :src="logoUrl"
                            @error="logoFailed = true"
                            alt=""
                            class="h-16 w-16 shrink-0 rounded-full border-4 border-white/70 bg-white object-cover"
                        />
                        <div>
                            <div class="text-2xl font-bold leading-tight sm:text-3xl">{{ clinicName }}</div>
                            <div v-if="stageName || groupName" class="mt-1 text-sm text-white/90 sm:text-base">
                                {{ [stageName, groupName].filter(Boolean).join(' · ') }}
                            </div>
                        </div>
                    </div>

                    <div class="text-left">
                        <div class="text-4xl font-bold tabular-nums sm:text-5xl">{{ timeString }}</div>
                        <div class="mt-1 text-sm text-white/90 sm:text-base">{{ dateString }}</div>
                    </div>
                </div>
            </header>

            <main class="mx-auto w-full max-w-7xl flex-1 px-8 py-10">
                <!-- Lab (2026-11-02): amber while waiting for the test, green once the result is ready. -->
                <section
                    v-if="labPatients.length"
                    class="rounded-2xl border border-ig-border-light bg-white/60 p-6 shadow-sm dark:border-ig-border-dark dark:bg-ig-black/40"
                >
                    <div class="mb-4 flex flex-wrap items-center gap-3">
                        <h2 class="text-2xl font-bold sm:text-3xl">{{ t('waitingScreen.labHeading') }}</h2>
                        <span v-if="labCounts.ready" class="rounded-full bg-emerald-500 px-3 py-0.5 text-base font-bold text-white">
                            {{ t('waitingScreen.labReadyBadge') }} · {{ labCounts.ready }}
                        </span>
                        <span v-if="labCounts.waiting" class="rounded-full bg-amber-500 px-3 py-0.5 text-base font-bold text-white">
                            {{ t('waitingScreen.labWaitingHeading') }} · {{ labCounts.waiting }}
                        </span>
                    </div>
                    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
                        <div
                            v-for="(item, i) in currentPageItems"
                            :key="'lab-' + currentPage + '-' + i + '-' + item.patient_name"
                            class="flex items-center justify-between gap-3 rounded-xl border-2 px-5 py-4 shadow-sm transition-colors duration-700"
                            :class="item.status === 'ready'
                                ? 'border-emerald-400 bg-emerald-500 text-white'
                                : 'border-amber-300 bg-amber-50 text-ig-near-black dark:border-amber-500/60 dark:bg-amber-500/10 dark:text-ig-off-white'"
                        >
                            <span class="min-w-0 truncate text-xl font-semibold sm:text-2xl">{{ item.patient_name }}</span>
                            <span
                                class="flex shrink-0 items-center gap-2 rounded-full px-3 py-1 text-base font-bold"
                                :class="item.status === 'ready' ? 'bg-white/25 text-white' : 'bg-amber-500 text-white'"
                            >
                                <span v-if="item.status === 'ready'" class="relative flex h-2.5 w-2.5">
                                    <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-white opacity-75" />
                                    <span class="relative inline-flex h-2.5 w-2.5 rounded-full bg-white" />
                                </span>
                                {{ item.status === 'ready' ? t('waitingScreen.labReadyBadge') : t('waitingScreen.labWaitingHeading') }}
                            </span>
                        </div>
                    </div>
                </section>

                <div v-else class="py-32 text-center text-2xl text-ig-gray">
                    {{ t('waitingScreen.labEmpty') }}
                </div>
            </main>

            <footer class="flex flex-col items-center gap-2 pb-8">
                <div v-if="pages.length > 1" class="flex items-center gap-2">
                    <span
                        v-for="(p, i) in pages"
                        :key="i"
                        class="h-2.5 w-2.5 rounded-full transition-colors"
                        :class="i === currentPage ? 'bg-ig-blue' : 'bg-ig-border-light dark:bg-ig-border-dark'"
                    />
                </div>
                <div v-if="pages.length > 1" class="text-sm text-ig-gray">
                    {{ t('waitingScreen.pageIndicator', { current: currentPage + 1, total: pages.length }) }}
                </div>
                <button type="button" @click="rePair" class="mt-2 text-xs text-ig-gray/70 underline hover:text-ig-gray">
                    {{ t('waitingScreen.rePair') }}
                </button>
            </footer>
        </template>

        <div v-else class="flex flex-1 items-center justify-center text-2xl text-ig-gray">
            {{ connectionLost ? t('waitingScreen.reconnecting') : t('waitingScreen.loading') }}
        </div>

        <!-- Network down: the last list stays up while it retries by itself. -->
        <div
            v-if="connectionLost"
            class="fixed bottom-4 left-4 flex items-center gap-2 rounded-full bg-red-600 px-4 py-2 text-base font-semibold text-white shadow-lg"
        >
            <span class="h-2.5 w-2.5 animate-pulse rounded-full bg-white" />
            {{ t('waitingScreen.reconnecting') }}
        </div>
    </div>
</template>

<style scoped>
.waiting-screen-page-enter-active,
.waiting-screen-page-leave-active {
    transition: opacity 0.4s ease;
}
.waiting-screen-page-enter-from,
.waiting-screen-page-leave-to {
    opacity: 0;
}
</style>
