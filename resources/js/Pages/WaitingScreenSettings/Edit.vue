<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import axios from 'axios';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    settings: Object,
    screens: { type: Array, default: () => [] },
    returnMinutes: { type: Array, default: () => [0, 1, 2, 5, 10, 30, 60] },
    // Calling names by voice (2026-11-17), see App\Support\VoiceCalls.
    voice: { type: Object, default: () => ({}) },
    voiceEngines: { type: Array, default: () => [] },
    voiceDefaults: { type: Object, default: () => ({}) },
    voiceNames: { type: Array, default: () => [] },
    voiceInstalled: { type: Array, default: () => [] },
    voiceDownloadable: { type: Boolean, default: false },
});

// Remote control of paired screens (2026-11-03, by request).
const screenName = (screen, i) => screen.name || t('waitingScreenSettings.screenUnnamed', { n: i + 1 });
const minutesLabel = (m) => (m === 0 ? t('waitingScreenSettings.never') : t('waitingScreenSettings.minutes', { n: m }));
const onOff = (v) => (v === true ? t('waitingScreenSettings.on') : v === false ? t('waitingScreenSettings.off') : t('waitingScreenSettings.unknown'));
const commandLabels = {
    reload: 'reload',
    check_update: 'checkUpdate',
    open_on_boot: 'openOnBoot',
    open_on_wake: 'openOnWake',
    return_minutes: 'returnMinutes',
};
const pendingList = (screen) => screen.pending.map((c) => t('waitingScreenSettings.' + (commandLabels[c] ?? c))).join('، ');
const lastSeen = (screen) => (screen.last_seen_at
    ? t('waitingScreenSettings.lastSeen', { time: new Date(screen.last_seen_at).toLocaleString() })
    : t('waitingScreenSettings.neverSeen'));

const send = (screen, type, value = null) => {
    router.post(route('waiting-screen-screens.command', screen.id), { type, value }, { preserveScroll: true });
};
const rename = (screen, i) => {
    const name = window.prompt(t('waitingScreenSettings.renamePrompt'), screenName(screen, i));
    if (name === null) return;
    router.patch(route('waiting-screen-screens.update', screen.id), { name }, { preserveScroll: true });
};
const unpair = (screen) => {
    if (!window.confirm(t('waitingScreenSettings.unpairConfirm'))) return;
    router.delete(route('waiting-screen-screens.destroy', screen.id), { preserveScroll: true });
};

// Keeps "online" and delivered commands fresh while the page is open.
let refresh = null;
onMounted(() => {
    refresh = setInterval(() => router.reload({ only: ['screens'], preserveScroll: true }), 10000);
});
onBeforeUnmount(() => refresh && clearInterval(refresh));

const page = usePage();

const form = useForm({
    // Lab-only screen (2026-11-02, by request): no stage or group filter.
    group_id: null,
    patients_per_page: props.settings.patients_per_page ?? 8,
    rotation_seconds: props.settings.rotation_seconds ?? 12,
    // Lab filter (2026-11-03, by request): today's only or all pending.
    lab_scope: props.settings.lab_scope || 'today',
    ...props.voice,
});

// «تجربة الصوت» (2026-11-17, by request): plays the sentence for a sample
// name with the wording, speed and volume on the form, before saving.
const testName = ref(t('waitingScreenSettings.voiceTestNameDefault'));
const testKind = ref('ready');
const testing = ref(false);
const testError = ref('');
let testAudio = null;
const joinSentence = (kind, name) => {
    const before = (form[`voice_${kind}_before`] ?? '').trim();
    const after = (form[`voice_${kind}_after`] ?? '').trim();
    let text = `${before} ${name.trim()}`.trim();
    if (after) text += (/^[،,.؛:!؟?]/.test(after) ? '' : '، ') + after;
    return text;
};
// A voice the Windows server does not carry (2026-11-17): fetched piece by piece.
const installed = ref([...props.voiceInstalled]);
const voiceMissing = computed(() => form.voice_engine === 'piper' && !installed.value.includes(form.voice_name));
const downloading = ref(false);
const downloadText = ref('');
const downloadError = ref('');
const mb = (b) => (b / 1048576).toFixed(1);
const downloadVoice = async () => {
    downloading.value = true;
    downloadError.value = '';
    const voice = form.voice_name;
    try {
        for (;;) {
            const { data } = await axios.post(route('waiting-screen-settings.voice-download', voice), {}, { timeout: 180000 });
            const s = data.data;
            downloadText.value = t('waitingScreenSettings.voiceDownloading', { done: mb(s.received), total: mb(s.total) });
            if (s.done) break;
        }
        installed.value = [...installed.value, voice];
        downloadText.value = t('waitingScreenSettings.voiceDownloaded');
    } catch (e) {
        downloadError.value = e?.response?.data?.message ?? t('waitingScreenSettings.voiceDownloadFailed');
    } finally {
        downloading.value = false;
    }
};
const previewSentence = computed(() => joinSentence(testKind.value, testName.value || ''));
const testVoice = async () => {
    testing.value = true;
    testError.value = '';
    try {
        const { data } = await axios.post(route('waiting-screen-settings.voice-preview'), {
            name: testName.value,
            kind: testKind.value,
            voice_engine: form.voice_engine,
            voice_name: form.voice_name,
            voice_rate: form.voice_rate,
            voice_ready_before: form.voice_ready_before,
            voice_ready_after: form.voice_ready_after,
            voice_waiting_before: form.voice_waiting_before,
            voice_waiting_after: form.voice_waiting_after,
        }, { responseType: 'blob' });
        testAudio?.pause();
        testAudio = new Audio(URL.createObjectURL(data));
        testAudio.volume = Math.max(0, Math.min(1, form.voice_volume / 100));
        for (let i = 0; i < form.voice_repeat; i++) {
            await testAudio.play();
            await new Promise((r) => { testAudio.onended = r; });
            if (i < form.voice_repeat - 1) await new Promise((r) => setTimeout(r, 900));
        }
    } catch (e) {
        let message = '';
        try { message = JSON.parse(await e?.response?.data?.text?.())?.message ?? ''; } catch { message = ''; }
        testError.value = message || t('waitingScreenSettings.voiceTestFailed');
    } finally {
        testing.value = false;
    }
};

const submit = () => {
    form.put(route('waiting-screen-settings.update'), { preserveScroll: true });
};
</script>

<template>
    <Head :title="t('waitingScreenSettings.title')" />

    <AuthenticatedLayout>
        <!-- Chat-list style (2026-10-13, by request): rounded card, rounded inputs,
             and "open the screen" as a round header button. -->
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('waitingScreenSettings.heading') }}</h2>
                <a
                    :href="route('waiting-screen')"
                    target="_blank"
                    rel="noopener"
                    :title="t('waitingScreenSettings.openScreen')"
                    class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200"
                >
                    <Icon name="open_in_new" :label="t('waitingScreenSettings.openScreen')" />
                </a>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl px-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="mb-4 rounded-xl bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                    <div class="mb-6 flex items-start gap-3">
                        <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-sky-500 to-cyan-500 text-white"><Icon name="tv" size="text-[22px]" /></span>
                        <p class="pt-2 text-sm text-gray-500">{{ t('waitingScreenSettings.description') }}</p>
                    </div>

                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel :value="t('waitingScreenSettings.labScopeLabel')" />
                            <div class="mt-2 grid gap-2 sm:grid-cols-2">
                                <label
                                    v-for="opt in ['today', 'all']"
                                    :key="opt"
                                    class="flex cursor-pointer items-start gap-3 rounded-xl p-3 ring-1 transition"
                                    :class="form.lab_scope === opt ? 'bg-sky-50 ring-sky-400' : 'ring-gray-200 hover:bg-gray-50'"
                                >
                                    <input v-model="form.lab_scope" type="radio" name="lab_scope" :value="opt" class="mt-1 text-sky-600 focus:ring-sky-500" />
                                    <span>
                                        <span class="block text-sm font-medium text-gray-800">{{ t(`waitingScreenSettings.labScope_${opt}`) }}</span>
                                        <span class="block text-xs text-gray-500">{{ t(`waitingScreenSettings.labScope_${opt}_hint`) }}</span>
                                    </span>
                                </label>
                            </div>
                            <InputError class="mt-2" :message="form.errors.lab_scope" />
                        </div>

                        <div>
                            <InputLabel for="patients_per_page" :value="t('waitingScreenSettings.patientsPerPageLabel')" />
                            <TextInput
                                id="patients_per_page"
                                v-model.number="form.patients_per_page"
                                type="number"
                                min="1"
                                max="50"
                                class="mt-1 block w-full rounded-xl max-w-[10rem]"
                                required
                            />
                            <InputError class="mt-2" :message="form.errors.patients_per_page" />
                        </div>

                        <div>
                            <InputLabel for="rotation_seconds" :value="t('waitingScreenSettings.rotationSecondsLabel')" />
                            <TextInput
                                id="rotation_seconds"
                                v-model.number="form.rotation_seconds"
                                type="number"
                                min="3"
                                max="300"
                                class="mt-1 block w-full rounded-xl max-w-[10rem]"
                                required
                            />
                            <InputError class="mt-2" :message="form.errors.rotation_seconds" />
                        </div>

                        <!-- Calling names by voice (2026-11-17, by request) -->
                        <div class="space-y-4 rounded-2xl bg-violet-50/60 p-4 ring-1 ring-violet-100">
                            <div>
                                <h3 class="flex items-center gap-2 font-semibold text-gray-800"><Icon name="record_voice_over" />{{ t('waitingScreenSettings.voiceHeading') }}</h3>
                                <p class="mt-1 text-xs text-gray-500">{{ t('waitingScreenSettings.voiceHint') }}</p>
                            </div>
                            <label class="flex items-center gap-2 text-sm font-medium text-gray-800">
                                <input v-model="form.voice_enabled" type="checkbox" class="rounded text-violet-600 focus:ring-violet-500" />
                                {{ t('waitingScreenSettings.voiceEnabled') }}
                            </label>
                            <template v-if="form.voice_enabled">
                                <div>
                                    <InputLabel :value="t('waitingScreenSettings.voiceEngine')" />
                                    <select v-model="form.voice_engine" class="mt-1 block w-full rounded-xl border-gray-300 text-sm">
                                        <option v-for="engine in ['piper', 'windows']" :key="engine" :value="engine">
                                            {{ t(`waitingScreenSettings.voiceEngine_${engine}`) }}{{ voiceEngines.includes(engine) ? '' : ' — ' + t('waitingScreenSettings.voiceEngineMissing') }}
                                        </option>
                                    </select>
                                    <InputError class="mt-2" :message="form.errors.voice_engine" />
                                </div>
                                <div v-if="form.voice_engine === 'piper'">
                                    <InputLabel :value="t('waitingScreenSettings.voiceName')" />
                                    <select v-model="form.voice_name" class="mt-1 block w-full rounded-xl border-gray-300 text-sm">
                                        <option v-for="name in voiceNames" :key="name" :value="name">
                                            {{ t(`waitingScreenSettings.voiceName_${name}`) }}{{ installed.includes(name) ? '' : ' — ' + t('waitingScreenSettings.voiceNameMissing') }}
                                        </option>
                                    </select>
                                    <InputError class="mt-2" :message="form.errors.voice_name" />
                                    <div v-if="voiceMissing && voiceDownloadable" class="mt-2 space-y-2 rounded-xl bg-amber-50 p-3 text-xs text-amber-900">
                                        <p>{{ t('waitingScreenSettings.voiceNeedsDownload') }}</p>
                                        <button type="button" :disabled="downloading" @click="downloadVoice" class="inline-flex items-center gap-1 rounded-full bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-amber-700 disabled:opacity-50">
                                            <Icon name="download" size="text-[16px]" />{{ t('waitingScreenSettings.voiceDownload') }}
                                        </button>
                                        <p v-if="downloadText">{{ downloadText }}</p>
                                        <p v-if="downloadError" class="text-red-700">{{ downloadError }}</p>
                                    </div>
                                    <p v-else-if="downloadText" class="mt-2 text-xs text-emerald-700">{{ downloadText }}</p>
                                </div>
                                <div v-for="kind in ['ready', 'waiting']" :key="kind" class="rounded-xl bg-white p-3 ring-1 ring-gray-100">
                                    <label class="flex items-center gap-2 text-sm font-medium text-gray-800">
                                        <input v-model="form[`voice_${kind}`]" type="checkbox" class="rounded text-violet-600 focus:ring-violet-500" />
                                        {{ t(kind === 'ready' ? 'waitingScreenSettings.voiceReady' : 'waitingScreenSettings.voiceWaiting') }}
                                    </label>
                                    <div v-if="form[`voice_${kind}`]" class="mt-3 grid gap-3 sm:grid-cols-2">
                                        <div>
                                            <InputLabel :value="t('waitingScreenSettings.voiceBefore')" />
                                            <TextInput v-model="form[`voice_${kind}_before`]" maxlength="150" class="mt-1 block w-full rounded-xl" :placeholder="voiceDefaults[`voice_${kind}_before`]" />
                                            <InputError class="mt-1" :message="form.errors[`voice_${kind}_before`]" />
                                        </div>
                                        <div>
                                            <InputLabel :value="t('waitingScreenSettings.voiceAfter')" />
                                            <TextInput v-model="form[`voice_${kind}_after`]" maxlength="150" class="mt-1 block w-full rounded-xl" :placeholder="voiceDefaults[`voice_${kind}_after`]" />
                                            <InputError class="mt-1" :message="form.errors[`voice_${kind}_after`]" />
                                        </div>
                                    </div>
                                </div>
                                <div class="grid gap-4 sm:grid-cols-3">
                                    <div>
                                        <InputLabel :value="t('waitingScreenSettings.voiceRepeat')" />
                                        <select v-model.number="form.voice_repeat" class="mt-1 block w-full rounded-xl border-gray-300 text-sm">
                                            <option v-for="n in 5" :key="n" :value="n">{{ n }}</option>
                                        </select>
                                    </div>
                                    <div>
                                        <InputLabel :value="`${t('waitingScreenSettings.voiceVolume')} (${form.voice_volume}%)`" />
                                        <input v-model.number="form.voice_volume" type="range" min="0" max="100" step="5" class="mt-3 w-full accent-violet-600" />
                                    </div>
                                    <div>
                                        <InputLabel :value="`${t('waitingScreenSettings.voiceRate')} (${form.voice_rate}%)`" />
                                        <input v-model.number="form.voice_rate" type="range" min="50" max="150" step="5" class="mt-3 w-full accent-violet-600" />
                                        <p class="mt-1 text-[11px] text-gray-500">{{ t('waitingScreenSettings.voiceRateHint') }}</p>
                                    </div>
                                </div>
                                <div class="rounded-xl bg-white p-3 ring-1 ring-gray-100">
                                    <div class="flex flex-wrap items-end gap-2">
                                        <div class="min-w-[10rem] flex-1">
                                            <InputLabel :value="t('waitingScreenSettings.voiceTestName')" />
                                            <TextInput v-model="testName" maxlength="100" class="mt-1 block w-full rounded-xl" />
                                        </div>
                                        <select v-model="testKind" class="rounded-xl border-gray-300 text-sm">
                                            <option value="ready">{{ t('waitingScreenSettings.voiceReady') }}</option>
                                            <option value="waiting">{{ t('waitingScreenSettings.voiceWaiting') }}</option>
                                        </select>
                                        <button type="button" :disabled="testing || !testName.trim()" @click="testVoice" class="inline-flex items-center gap-1 rounded-full bg-violet-600 px-4 py-2 text-sm font-semibold text-white hover:bg-violet-700 disabled:opacity-50">
                                            <Icon name="play_arrow" size="text-[18px]" />{{ testing ? t('waitingScreenSettings.voiceTesting') : t('waitingScreenSettings.voiceTest') }}
                                        </button>
                                    </div>
                                    <p class="mt-2 text-xs text-gray-500">{{ t('waitingScreenSettings.voicePreviewSentence', { text: previewSentence }) }}</p>
                                    <p v-if="testError" class="mt-2 rounded-lg bg-red-50 p-2 text-xs text-red-700">{{ testError }}</p>
                                </div>
                            </template>
                        </div>

                        <div class="flex items-center justify-end border-t border-gray-100 pt-6">
                            <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing"><Icon name="save" size="text-[18px]" />{{ t('waitingScreenSettings.save') }}</PrimaryButton>
                        </div>
                    </form>
                </div>

                <div class="mt-6 overflow-hidden rounded-2xl bg-white p-5 shadow-sm ring-1 ring-gray-100 sm:p-6">
                    <h3 class="text-lg font-semibold text-gray-800">{{ t('waitingScreenSettings.screensHeading') }}</h3>
                    <p class="mt-1 text-sm text-gray-500">{{ t('waitingScreenSettings.screensHint') }}</p>

                    <p v-if="!screens.length" class="mt-4 rounded-xl bg-gray-50 p-4 text-sm text-gray-500">{{ t('waitingScreenSettings.noScreens') }}</p>

                    <div v-for="(screen, i) in screens" :key="screen.id" class="mt-4 rounded-2xl border border-gray-100 p-4">
                        <div class="flex flex-wrap items-center justify-between gap-2">
                            <div class="flex items-center gap-2">
                                <span class="h-2.5 w-2.5 rounded-full" :class="screen.online ? 'bg-emerald-500' : 'bg-gray-300'"></span>
                                <span class="font-semibold text-gray-800">{{ screenName(screen, i) }}</span>
                                <span class="text-xs text-gray-500">{{ screen.online ? t('waitingScreenSettings.online') : t('waitingScreenSettings.offline') }}</span>
                            </div>
                            <div class="flex gap-1">
                                <button type="button" class="inline-flex h-9 w-9 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200" :title="t('waitingScreenSettings.rename')" @click="rename(screen, i)"><Icon name="edit" :label="t('waitingScreenSettings.rename')" size="text-[18px]" /></button>
                                <button type="button" class="inline-flex h-9 w-9 items-center justify-center rounded-full bg-red-50 text-red-600 hover:bg-red-100" :title="t('waitingScreenSettings.unpair')" @click="unpair(screen)"><Icon name="link_off" :label="t('waitingScreenSettings.unpair')" size="text-[18px]" /></button>
                            </div>
                        </div>
                        <p class="mt-1 text-xs text-gray-500">
                            {{ lastSeen(screen) }} ·
                            {{ screen.tv_app ? t('waitingScreenSettings.tvApp', { version: screen.version ?? '' }) : t('waitingScreenSettings.browser') }}
                        </p>
                        <p v-if="screen.tv_app && screen.overlay === false" class="mt-1 text-xs text-amber-600">{{ t('waitingScreenSettings.overlayOff') }}</p>
                        <p v-if="screen.pending.length" class="mt-1 text-xs text-sky-600">{{ t('waitingScreenSettings.pending', { list: pendingList(screen) }) }}</p>

                        <div class="mt-3 flex flex-wrap gap-2">
                            <button type="button" class="inline-flex items-center gap-1 rounded-full bg-sky-50 px-3 py-1.5 text-sm font-medium text-sky-700 hover:bg-sky-100" @click="send(screen, 'reload')"><Icon name="refresh" size="text-[18px]" />{{ t('waitingScreenSettings.reload') }}</button>
                            <button v-if="screen.tv_app" type="button" class="inline-flex items-center gap-1 rounded-full bg-sky-50 px-3 py-1.5 text-sm font-medium text-sky-700 hover:bg-sky-100" @click="send(screen, 'check_update')"><Icon name="system_update" size="text-[18px]" />{{ t('waitingScreenSettings.checkUpdate') }}</button>
                        </div>

                        <div v-if="screen.tv_app" class="mt-3 space-y-2 text-sm">
                            <label class="flex items-center justify-between gap-3">
                                <span>{{ t('waitingScreenSettings.openOnBoot') }} <span class="text-xs text-gray-400">({{ onOff(screen.open_on_boot) }})</span></span>
                                <input type="checkbox" class="rounded" :checked="screen.open_on_boot === true" @change="send(screen, 'open_on_boot', $event.target.checked)" />
                            </label>
                            <label class="flex items-center justify-between gap-3">
                                <span>{{ t('waitingScreenSettings.openOnWake') }} <span class="text-xs text-gray-400">({{ onOff(screen.open_on_wake) }})</span></span>
                                <input type="checkbox" class="rounded" :checked="screen.open_on_wake === true" @change="send(screen, 'open_on_wake', $event.target.checked)" />
                            </label>
                            <label class="flex items-center justify-between gap-3">
                                <span>{{ t('waitingScreenSettings.returnMinutes') }}</span>
                                <select class="rounded-xl border-gray-300 py-1 text-sm" :value="screen.return_minutes ?? ''" @change="send(screen, 'return_minutes', Number($event.target.value))">
                                    <option v-if="screen.return_minutes === null" value="" disabled>{{ t('waitingScreenSettings.unknown') }}</option>
                                    <option v-for="m in returnMinutes" :key="m" :value="m">{{ minutesLabel(m) }}</option>
                                </select>
                            </label>
                        </div>
                        <p v-else class="mt-2 text-xs text-gray-400">{{ t('waitingScreenSettings.needsTvApp') }}</p>
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
