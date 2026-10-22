<script setup>
/**
 * "إعدادات النماذج" (2026-10-22, by request), opened from task progress:
 * the supervisor's own rotating code at the top, then the supervisor code
 * settings. Forms, grades shown to students and the task switches are in
 * the general settings. See FormSettingsController.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import SettingsToggle from '@/Components/ChatList/SettingsToggle.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link } from '@inertiajs/vue3';
import axios from 'axios';
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    settings: Object,
    canEdit: Boolean,
    myCode: { type: Object, default: null },
    canOpenGeneral: Boolean,
});
const { t } = useI18n();

const form = reactive({ ...props.settings, supervisor_code_actions: [...props.settings.supervisor_code_actions] });
const saving = ref(false);
const message = ref('');
const error = ref('');
const save = async () => {
    saving.value = true;
    message.value = error.value = '';
    try {
        const { data } = await axios.put(route('form-settings.update'), form);
        Object.assign(form, data.settings);
        message.value = t('formSettings.saved');
        refreshCode();
    } catch (e) {
        const errors = e.response?.data?.errors;
        error.value = errors ? Object.values(errors).flat()[0] : t('formSettings.failed');
    } finally {
        saving.value = false;
    }
};
const toggleAction = (key) => {
    const list = form.supervisor_code_actions;
    form.supervisor_code_actions = list.includes(key) ? list.filter((k) => k !== key) : [...list, key];
};

// The code refreshes itself when its period ends.
const code = ref(props.myCode);
const now = ref(Date.now());
let timer = null;
const refreshCode = async () => {
    if (!code.value) return;
    try {
        code.value = (await axios.get(route('task-progress.my-code'))).data;
    } catch {
        // keep the last one on screen
    }
};
onMounted(() => {
    timer = setInterval(() => {
        now.value = Date.now();
        if (code.value && new Date(code.value.expires_at).getTime() <= now.value) refreshCode();
    }, 1000);
});
onBeforeUnmount(() => clearInterval(timer));
const remaining = computed(() => {
    if (!code.value) return '';
    const s = Math.max(0, Math.floor((new Date(code.value.expires_at).getTime() - now.value) / 1000));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    return (h ? `${h}:` : '') + `${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
});
const digits = computed(() => (code.value?.code ?? '').split(''));
const copied = ref(false);
const copy = async () => {
    try {
        await navigator.clipboard.writeText(code.value.code);
        copied.value = true;
        setTimeout(() => (copied.value = false), 1500);
    } catch {
        // clipboard blocked
    }
};
const actions = ['start', 'step', 'finish'];
const actionIcon = { start: 'play_circle', step: 'checklist', finish: 'task_alt' };
</script>

<template>
    <Head :title="t('formSettings.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center gap-2">
                <Link :href="route('task-progress.index')" class="rounded-full p-1 text-gray-500 hover:bg-gray-100"><Icon name="arrow_forward" /></Link>
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('formSettings.title') }}</h2>
            </div>
        </template>

        <div class="py-8">
            <div class="mx-auto max-w-3xl space-y-5 px-4 sm:px-6">
                <p class="text-sm text-gray-500">{{ t('formSettings.subtitle') }}</p>

                <!-- The supervisor's own code -->
                <div v-if="code" class="overflow-hidden rounded-3xl bg-gradient-to-br from-indigo-600 to-violet-600 p-6 text-white shadow-lg">
                    <div class="flex items-center justify-between">
                        <span class="flex items-center gap-2 text-sm font-medium text-indigo-100"><Icon name="key" />{{ t('formSettings.myCode') }}</span>
                        <span class="rounded-full bg-white/15 px-3 py-1 text-xs">{{ form.supervisor_code_period === 'hourly' ? t('formSettings.hourly') : t('formSettings.daily') }}</span>
                    </div>
                    <div class="mt-5 flex justify-center gap-2 sm:gap-3" dir="ltr">
                        <span
                            v-for="(d, i) in digits"
                            :key="i"
                            class="flex h-14 w-11 items-center justify-center rounded-2xl bg-white/15 text-3xl font-bold tabular-nums ring-1 ring-white/25 sm:h-16 sm:w-12 sm:text-4xl"
                        >{{ d }}</span>
                    </div>
                    <div class="mt-5 flex items-center justify-between text-sm text-indigo-100">
                        <span class="flex items-center gap-1"><Icon name="schedule" size="text-[18px]" />{{ t('formSettings.changesAt', { time: remaining }) }}</span>
                        <button type="button" class="rounded-full bg-white/15 px-3 py-1 hover:bg-white/25" @click="copy">
                            <Icon :name="copied ? 'check' : 'content_copy'" size="text-[16px]" class="ml-1" />{{ copied ? t('formSettings.copied') : t('formSettings.copy') }}
                        </button>
                    </div>
                    <p v-if="!form.supervisor_code_enabled" class="mt-4 rounded-xl bg-amber-400/20 p-2 text-center text-xs text-amber-50">{{ t('formSettings.codeOff') }}</p>
                </div>

                <!-- Forms, grades and task switches live with the general settings (2026-10-22, by request). -->
                <Link
                    v-if="canOpenGeneral"
                    :href="route('clinic-settings.edit')"
                    class="flex items-center gap-3 rounded-2xl bg-white p-4 text-sm text-gray-700 shadow-sm ring-1 ring-gray-100 hover:bg-gray-50"
                >
                    <Icon name="settings" class="text-indigo-600" />
                    <span class="flex-1">{{ t('formSettings.generalLink') }}</span>
                    <Icon name="chevron_left" class="text-gray-400" />
                </Link>

                <p v-if="!canEdit" class="rounded-xl bg-gray-50 p-3 text-sm text-gray-600 ring-1 ring-gray-200">{{ t('formSettings.readOnly') }}</p>

                <fieldset :disabled="!canEdit" class="space-y-5">
                    <section class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                        <h3 class="mb-1 flex items-center gap-2 font-semibold text-gray-900"><Icon name="pin" class="text-violet-600" />{{ t('formSettings.codeSection') }}</h3>
                        <SettingsToggle v-model="form.supervisor_code_enabled" :label="t('formSettings.codeEnabled')" :hint="t('formSettings.codeEnabledHint')" />
                        <template v-if="form.supervisor_code_enabled">
                            <div class="mt-3 text-sm text-gray-700">{{ t('formSettings.period') }}</div>
                            <div class="mt-2 grid grid-cols-2 gap-2">
                                <button
                                    v-for="p in ['daily', 'hourly']"
                                    :key="p"
                                    type="button"
                                    class="flex items-center justify-center gap-2 rounded-xl border-2 p-3 text-sm font-medium transition"
                                    :class="form.supervisor_code_period === p ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-gray-200 text-gray-600 hover:bg-gray-50'"
                                    @click="form.supervisor_code_period = p"
                                >
                                    <Icon :name="p === 'daily' ? 'today' : 'hourglass_top'" />{{ t('formSettings.' + p) }}
                                </button>
                            </div>
                            <div class="mt-4 text-sm text-gray-700">{{ t('formSettings.actions') }}</div>
                            <div class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-3">
                                <button
                                    v-for="a in actions"
                                    :key="a"
                                    type="button"
                                    class="flex items-center gap-2 rounded-xl border-2 p-3 text-sm font-medium transition"
                                    :class="form.supervisor_code_actions.includes(a) ? 'border-emerald-500 bg-emerald-50 text-emerald-700' : 'border-gray-200 text-gray-500 hover:bg-gray-50'"
                                    @click="toggleAction(a)"
                                >
                                    <Icon :name="form.supervisor_code_actions.includes(a) ? 'check_circle' : actionIcon[a]" />{{ t('formSettings.action_' + a) }}
                                </button>
                            </div>
                        </template>
                    </section>
                </fieldset>

                <div v-if="canEdit" class="flex items-center justify-end gap-3">
                    <span v-if="message" class="text-sm text-emerald-600">{{ message }}</span>
                    <span v-if="error" class="text-sm text-red-600">{{ error }}</span>
                    <button
                        type="button"
                        class="rounded-full bg-indigo-600 px-6 py-2.5 text-sm font-medium text-white shadow hover:bg-indigo-700 disabled:opacity-50"
                        :disabled="saving"
                        @click="save"
                    >
                        {{ t('formSettings.save') }}
                    </button>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
