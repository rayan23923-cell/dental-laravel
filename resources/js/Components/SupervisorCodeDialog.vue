<script setup>
/**
 * The supervisor's code typed on the student's own account (2026-10-22, by
 * request): starts the task, signs the case's next step with its grade, or
 * completes it. The supervisor picks the grade with a tap (GradePicker)
 * and types their code; the server checks it. See SupervisorCodeController.
 */
import GradePicker from '@/Components/GradePicker.vue';
import Icon from '@/Components/Icon.vue';
import Modal from '@/Components/Modal.vue';
import axios from 'axios';
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    // { task, slot } or null
    target: { type: Object, default: null },
    settings: { type: Object, required: true },
});
const emit = defineEmits(['close', 'done']);
const { t } = useI18n();

const allowed = computed(() => props.settings.supervisor_code_actions ?? []);
const started = computed(() => !!props.target?.slot?.instance_id);
const action = ref('start');
const code = ref('');
const grade = ref(null);
const notes = ref('');
const formType = ref('electronic');
const photo = ref(null);
const busy = ref(false);
const error = ref('');
const steps = ref(null);
const codeInput = ref(null);

const nextStep = computed(() => steps.value?.find((s) => !s.signed) ?? null);
const formTypes = computed(() => [
    ...(props.settings.electronic_forms_enabled ? [{ v: 'electronic', icon: 'description', label: t('taskRequests.electronicForm') }] : []),
    ...(props.settings.paper_forms_enabled ? [{ v: 'paper', icon: 'photo_camera', label: t('taskRequests.paperForm') }] : []),
]);
const actionsHere = computed(() =>
    started.value
        ? [
              ...(allowed.value.includes('step') ? [{ v: 'step', icon: 'checklist', label: t('supervisorCode.actionStep') }] : []),
              ...(allowed.value.includes('finish') ? [{ v: 'finish', icon: 'task_alt', label: t('supervisorCode.actionFinish') }] : []),
          ]
        : allowed.value.includes('start')
          ? [{ v: 'start', icon: 'play_circle', label: t('supervisorCode.actionStart') }]
          : [],
);
const gradesOn = computed(() => props.settings.grade_entry_enabled !== false);
const gradeMax = computed(() => (!gradesOn.value ? null : action.value === 'step' ? nextStep.value?.max ?? null : action.value === 'finish' ? Number(props.target?.task?.grade) || null : null));
const title = computed(() => t(`supervisorCode.${action.value}Title`));

watch(
    () => props.target,
    async (target) => {
        if (!target) return;
        code.value = notes.value = error.value = '';
        grade.value = null;
        photo.value = null;
        steps.value = null;
        formType.value = formTypes.value[0]?.v ?? 'electronic';
        action.value = actionsHere.value[0]?.v ?? 'start';
        if (target.slot.instance_id) {
            try {
                steps.value = (await axios.get(route('case-sheets.instance-work', target.slot.instance_id))).data.steps ?? [];
            } catch {
                steps.value = [];
            }
            if (action.value === 'step' && !nextStep.value && actionsHere.value.some((a) => a.v === 'finish')) action.value = 'finish';
        }
        await nextTick();
        codeInput.value?.focus();
    },
);

const canSubmit = computed(() => code.value.length === 6 && !busy.value && (action.value !== 'step' || (nextStep.value && (nextStep.value.max === null || !gradesOn.value || grade.value !== null))));

const submit = async () => {
    busy.value = true;
    error.value = '';
    try {
        let res;
        if (action.value === 'start') {
            const body = new FormData();
            body.append('task_id', props.target.task.id);
            body.append('code', code.value);
            body.append('form_type', formType.value);
            if (notes.value) body.append('notes', notes.value);
            if (formType.value === 'paper' && photo.value) body.append('photo', photo.value);
            res = await axios.post(route('doctor.supervisor-code.start'), body);
        } else if (action.value === 'step') {
            res = await axios.post(route('doctor.supervisor-code.step', props.target.slot.instance_id), { code: code.value, step: nextStep.value.key, grade: grade.value });
        } else {
            res = await axios.post(route('doctor.supervisor-code.complete', props.target.slot.instance_id), { code: code.value, grade: grade.value, notes: notes.value || null });
        }
        emit('done', t('supervisorCode.done', { name: res.data.supervisor }));
    } catch (e) {
        const errors = e.response?.data?.errors;
        error.value = errors ? Object.values(errors).flat()[0] : e.response?.data?.message ?? t('supervisorCode.failed');
        code.value = '';
    } finally {
        busy.value = false;
    }
};
const onCode = (e) => {
    code.value = e.target.value.replace(/\D/g, '').slice(0, 6);
    e.target.value = code.value;
};
</script>

<template>
    <Modal :show="target !== null" max-width="md" @close="emit('close')">
        <form v-if="target" class="space-y-4 p-5" @submit.prevent="submit">
            <div class="flex items-start gap-3">
                <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-violet-100 text-violet-700"><Icon name="pin" /></span>
                <div>
                    <h3 class="text-lg font-semibold text-gray-900">{{ title }}</h3>
                    <p class="text-sm text-gray-500">{{ target.task.title }} · #{{ target.slot.slot }}</p>
                </div>
            </div>

            <div v-if="actionsHere.length > 1" class="grid grid-cols-2 gap-2">
                <button
                    v-for="a in actionsHere"
                    :key="a.v"
                    type="button"
                    class="flex items-center justify-center gap-2 rounded-xl border-2 p-2.5 text-sm font-medium transition"
                    :class="action === a.v ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-gray-200 text-gray-600 hover:bg-gray-50'"
                    @click="action = a.v; grade = null"
                >
                    <Icon :name="a.icon" />{{ a.label }}
                </button>
            </div>

            <!-- Start: the form the case uses -->
            <template v-if="action === 'start'">
                <div v-if="formTypes.length > 1" class="grid grid-cols-2 gap-2">
                    <button
                        v-for="opt in formTypes"
                        :key="opt.v"
                        type="button"
                        class="flex flex-col items-center gap-1 rounded-xl border-2 p-3 text-sm transition"
                        :class="formType === opt.v ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-gray-200 text-gray-600'"
                        @click="formType = opt.v"
                    >
                        <Icon :name="opt.icon" size="text-2xl" />{{ opt.label }}
                    </button>
                </div>
                <div v-if="formType === 'paper'">
                    <label class="text-sm text-gray-700">{{ t('supervisorCode.photoOptional') }}</label>
                    <input type="file" accept="image/*" capture="environment" class="mt-1 block w-full text-sm text-gray-700" @change="photo = $event.target.files[0] ?? null" />
                </div>
            </template>

            <!-- Step: the next one, with its grade -->
            <template v-else-if="action === 'step'">
                <p v-if="steps === null" class="text-sm text-gray-500">{{ t('supervisorCode.loadingSteps') }}</p>
                <p v-else-if="!nextStep" class="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-700">{{ t('supervisorCode.allStepsSigned') }}</p>
                <template v-else>
                    <div class="flex items-center justify-between rounded-xl bg-indigo-50 px-3 py-2 text-sm text-indigo-800">
                        <span class="font-medium">{{ t('supervisorCode.nextStep', { label: nextStep.label }) }}</span>
                        <span class="text-xs">{{ steps.filter((s) => s.signed).length }}/{{ steps.length }}</span>
                    </div>
                    <GradePicker v-if="nextStep.max !== null && gradesOn" v-model="grade" :max="nextStep.max" />
                </template>
            </template>

            <!-- Finish: the final grade when the task has one -->
            <template v-else-if="action === 'finish'">
                <div v-if="gradeMax">
                    <div class="mb-2 text-sm font-medium text-gray-700">{{ t('supervisorCode.finalGrade') }}</div>
                    <GradePicker v-model="grade" :max="gradeMax" />
                </div>
            </template>

            <textarea
                v-if="action !== 'step'"
                v-model="notes"
                rows="2"
                class="block w-full rounded-xl border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                :placeholder="t('supervisorCode.notes')"
            ></textarea>

            <!-- The code itself -->
            <div class="rounded-2xl bg-gray-50 p-4 ring-1 ring-gray-200">
                <label class="block text-center text-sm font-medium text-gray-700">{{ t('supervisorCode.codeLabel') }}</label>
                <div class="relative mx-auto mt-3 w-fit" dir="ltr">
                    <div class="flex gap-2">
                        <span
                            v-for="i in 6"
                            :key="i"
                            class="flex h-12 w-10 items-center justify-center rounded-xl bg-white text-2xl font-bold tabular-nums shadow-sm ring-2 transition"
                            :class="code.length === i - 1 ? 'ring-indigo-500' : 'ring-gray-200'"
                        >{{ code[i - 1] ? '•' : '' }}</span>
                    </div>
                    <input
                        ref="codeInput"
                        :value="code"
                        type="text"
                        inputmode="numeric"
                        autocomplete="one-time-code"
                        maxlength="6"
                        class="absolute inset-0 h-full w-full cursor-text opacity-0"
                        @input="onCode"
                    />
                </div>
                <p class="mt-2 text-center text-xs text-gray-500">{{ t('supervisorCode.codeHint') }}</p>
            </div>

            <p v-if="error" class="rounded-xl bg-red-50 p-2 text-center text-sm text-red-600">{{ error }}</p>
            <div class="flex justify-end gap-2">
                <button type="button" class="rounded-full px-4 py-2 text-sm text-gray-600 hover:bg-gray-100" @click="emit('close')">{{ t('common.cancel') }}</button>
                <button type="submit" :disabled="!canSubmit" class="rounded-full bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50">
                    {{ t('supervisorCode.confirm') }}
                </button>
            </div>
        </form>
    </Modal>
</template>
