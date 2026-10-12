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
const patientsPerPage = ref(8);
const rotationSeconds = ref(12);
const currentPage = ref(0);
const now = ref(new Date());

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
const pages = computed(() => {
    const size = patientsPerPage.value || 8;
    const chunks = [];
    for (let i = 0; i < appointments.value.length; i += size) {
        chunks.push(appointments.value.slice(i, i + size));
    }
    return chunks.length ? chunks : [[]];
});

const currentPageItems = computed(() => pages.value[currentPage.value] ?? []);

const timeString = computed(() =>
    now.value.toLocaleTimeString('ar-IQ', { hour: '2-digit', minute: '2-digit' }),
);
const dateString = computed(() =>
    now.value.toLocaleDateString('ar-IQ', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }),
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

const load = async () => {
    const { data } = await window.axios.get('/api/v1/waiting-screen', {
        params: pairingToken.value ? { token: pairingToken.value } : {},
    });

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
    logoUrl.value = data.logo_url;
    stageName.value = data.stage_name;
    groupName.value = data.group_name;
    appointments.value = data.appointments;
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
onMounted(() => {
    load();
    dataTimer = setInterval(load, 4000);
    clockTimer = setInterval(() => {
        now.value = new Date();
    }, 1000);
});

onBeforeUnmount(() => {
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
                            v-if="logoUrl"
                            :src="logoUrl"
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
                <div v-if="appointments.length === 0" class="py-32 text-center text-2xl text-ig-gray">
                    {{ t('waitingScreen.empty') }}
                </div>

                <transition-group
                    v-else
                    name="waiting-screen-page"
                    tag="div"
                    class="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3"
                >
                    <div
                        v-for="item in currentPageItems"
                        :key="currentPage + '-' + item.patient_name + '-' + (item.doctor_name ?? '')"
                        class="rounded-2xl border border-ig-border-light bg-white p-6 shadow-sm dark:border-ig-border-dark dark:bg-ig-black"
                    >
                        <div class="text-xl font-semibold sm:text-2xl">{{ item.patient_name }}</div>
                        <div class="mt-3 flex items-center gap-2">
                            <span class="h-2 w-2 shrink-0 rounded-full" :class="item.doctor_name ? 'bg-ig-blue' : 'bg-ig-gray'" />
                            <span class="text-base text-ig-gray sm:text-lg" :class="item.doctor_name && 'text-ig-blue dark:text-ig-blue'">
                                {{ item.doctor_name ?? t('waitingScreen.unassigned') }}
                            </span>
                        </div>
                    </div>
                </transition-group>
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
            {{ t('waitingScreen.loading') }}
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
