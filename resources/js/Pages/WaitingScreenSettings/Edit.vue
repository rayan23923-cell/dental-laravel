<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { onBeforeUnmount, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    settings: Object,
    screens: { type: Array, default: () => [] },
    returnMinutes: { type: Array, default: () => [0, 1, 2, 5, 10, 30, 60] },
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
});

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
