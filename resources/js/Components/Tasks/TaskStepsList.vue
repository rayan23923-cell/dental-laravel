<script setup>
import GradeInput from '@/Components/GradeInput.vue';
import { stepsFromScoring } from '@/Components/Tasks/workItems.js';
import axios from 'axios';
import { usePage } from '@inertiajs/vue3';
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * A case's steps, signed one after another with each one's grade
 * (2026-10-18, by request); see App\Support\TaskSteps.
 *
 * With `instanceId` it signs on the server and emits `updated` with the
 * case's new work data. Without one (the start dialog, before the case
 * exists) it lists the task's steps from `scoring` and keeps the ticked
 * ones in v-model as [{step, grade}], which the start request signs.
 */
const { t } = useI18n();
const props = defineProps({
    steps: { type: Array, default: null },
    scoring: { type: Object, default: null },
    instanceId: { type: [Number, String], default: null },
    canSign: { type: Boolean, default: true },
    // Adding a step is its own permission (2026-10-22).
    canAddStep: { type: Boolean, default: false },
    modelValue: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue', 'updated']);

const local = computed(() => !props.instanceId);
const rows = computed(() => {
    if (!local.value) return props.steps ?? [];
    return stepsFromScoring(props.scoring).map((s) => {
        const picked = props.modelValue.find((m) => m.step === s.key);
        return { ...s, signed: !!picked, grade: picked?.grade ?? null, signed_by: picked ? t('taskSteps.atStart') : null };
    });
});
const nextIndex = computed(() => rows.value.findIndex((r) => !r.signed));
const lastSigned = computed(() => {
    const signed = rows.value.filter((r) => r.signed);
    return signed.length ? signed[signed.length - 1].key : null;
});

const grades = reactive({});
// System-wide switches (2026-10-22): grades and added steps can be off.
const switches = computed(() => usePage().props.taskSwitches ?? {});
const gradesOn = computed(() => switches.value.grade_entry_enabled !== false);
const busy = ref(false);
const error = ref('');

const sign = async (row) => {
    error.value = '';
    const grade = row.max === null || !gradesOn.value ? null : grades[row.key];
    if (row.max !== null && gradesOn.value && (grade === undefined || grade === null || grade === '' || grade < 0 || grade > row.max)) {
        error.value = t('taskSteps.gradeRange', { max: row.max });
        return;
    }
    if (local.value) {
        emit('update:modelValue', [...props.modelValue, { step: row.key, grade }]);
        return;
    }
    busy.value = true;
    try {
        const { data } = await axios.post(route('case-sheets.instance-steps.sign', props.instanceId), { step: row.key, grade });
        emit('updated', data);
    } catch (e) {
        error.value = Object.values(e.response?.data?.errors ?? {})[0]?.[0] ?? e.response?.data?.message ?? t('taskSteps.failed');
    } finally {
        busy.value = false;
    }
};

// A step added to this case alone, with its name and top grade (2026-10-19, by request).
const adding = ref(false);
const extra = reactive({ label: '', max: 10 });
const addExtra = async () => {
    error.value = '';
    busy.value = true;
    try {
        const { data } = await axios.post(route('case-sheets.instance-steps.add', props.instanceId), { label: extra.label, max: extra.max });
        extra.label = '';
        extra.max = 10;
        adding.value = false;
        emit('updated', data);
    } catch (e) {
        error.value = Object.values(e.response?.data?.errors ?? {})[0]?.[0] ?? e.response?.data?.message ?? t('taskSteps.failed');
    } finally {
        busy.value = false;
    }
};
const removeExtra = async (row) => {
    error.value = '';
    busy.value = true;
    try {
        const { data } = await axios.delete(route('case-sheets.instance-steps.remove', props.instanceId), { data: { step: row.key } });
        emit('updated', data);
    } catch (e) {
        error.value = Object.values(e.response?.data?.errors ?? {})[0]?.[0] ?? e.response?.data?.message ?? t('taskSteps.failed');
    } finally {
        busy.value = false;
    }
};

const undo = async (row) => {
    error.value = '';
    if (local.value) {
        emit('update:modelValue', props.modelValue.filter((m) => m.step !== row.key));
        return;
    }
    busy.value = true;
    try {
        const { data } = await axios.delete(route('case-sheets.instance-steps.undo', props.instanceId), { data: { step: row.key } });
        emit('updated', data);
    } catch (e) {
        error.value = Object.values(e.response?.data?.errors ?? {})[0]?.[0] ?? e.response?.data?.message ?? t('taskSteps.failed');
    } finally {
        busy.value = false;
    }
};
</script>

<template>
    <div v-if="rows.length || (!local && canSign)" class="space-y-2">
        <div v-if="rows.length" class="flex items-center justify-between">
            <h4 class="text-sm font-semibold text-gray-800">{{ t('taskSteps.title') }}</h4>
            <span class="text-xs text-gray-500">{{ t('taskSteps.progress', { done: rows.filter((r) => r.signed).length, total: rows.length }) }}</span>
        </div>
        <ol class="space-y-2">
            <li
                v-for="(row, i) in rows"
                :key="row.key"
                class="rounded-lg border p-2 text-sm"
                :class="row.signed ? 'border-emerald-200 bg-emerald-50' : i === nextIndex ? 'border-indigo-300 bg-indigo-50' : 'border-gray-200 bg-white opacity-70'"
            >
                <div class="flex flex-wrap items-center gap-2">
                    <span
                        class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white"
                        :class="row.signed ? 'bg-emerald-600' : i === nextIndex ? 'bg-indigo-600' : 'bg-gray-400'"
                    >
                        <template v-if="row.signed">✓</template><template v-else>{{ i + 1 }}</template>
                    </span>
                    <span class="flex-1 font-medium text-gray-800">
                        {{ row.label }}
                        <span v-if="row.extra" class="ms-1 rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-normal text-amber-800">{{ t('taskSteps.extraBadge') }}</span>
                    </span>
                    <template v-if="row.signed">
                        <span v-if="row.max !== null" class="rounded-full bg-white px-2 py-0.5 text-xs text-emerald-800 ring-1 ring-emerald-200">{{ row.grade ?? '—' }} / {{ row.max }}</span>
                        <button
                            v-if="canSign && row.key === lastSigned"
                            type="button"
                            class="text-xs text-red-600 hover:underline disabled:opacity-50"
                            :disabled="busy"
                            @click="undo(row)"
                        >
                            {{ t('taskSteps.undo') }}
                        </button>
                    </template>
                    <template v-else-if="canSign && i === nextIndex">
                        <span v-if="row.max !== null && gradesOn" class="flex items-center gap-1">
                            <!-- Picked with a tap (2026-10-22, by request). -->
                            <GradeInput v-model="grades[row.key]" :max="row.max" :title="row.label" />
                        </span>
                        <button type="button" class="rounded-md bg-indigo-600 px-3 py-1 text-xs text-white hover:bg-indigo-700 disabled:opacity-50" :disabled="busy" @click="sign(row)">
                            {{ t('taskSteps.sign') }}
                        </button>
                    </template>
                    <span v-else-if="row.max !== null" class="text-xs text-gray-500">/ {{ row.max }}</span>
                    <button
                        v-if="row.extra && !row.signed && canSign && !local"
                        type="button"
                        class="text-xs text-red-600 hover:underline disabled:opacity-50"
                        :disabled="busy"
                        @click="removeExtra(row)"
                    >
                        {{ t('taskSteps.removeStep') }}
                    </button>
                </div>
                <p v-if="row.signed && row.signed_by" class="mt-1 ps-8 text-xs text-gray-600">
                    {{ t('taskSteps.signedBy', { name: row.signed_by }) }}<template v-if="row.signed_at"> — {{ row.signed_at }}</template>
                </p>
            </li>
        </ol>
        <template v-if="!local && canAddStep && switches.step_add_enabled !== false">
            <form v-if="adding" class="flex flex-wrap items-center gap-2 rounded-lg border border-dashed border-indigo-300 p-2" @submit.prevent="addExtra">
                <input
                    v-model="extra.label"
                    type="text"
                    required
                    maxlength="100"
                    :placeholder="t('taskSteps.addStepName')"
                    class="min-w-0 flex-1 rounded-md border-gray-300 py-1 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
                <input
                    v-model.number="extra.max"
                    type="number"
                    required
                    min="0.5"
                    max="100"
                    step="0.5"
                    :title="t('taskSteps.addStepMax')"
                    class="w-20 rounded-md border-gray-300 py-1 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
                <button type="submit" class="rounded-md bg-indigo-600 px-3 py-1 text-xs text-white hover:bg-indigo-700 disabled:opacity-50" :disabled="busy">
                    {{ t('taskSteps.addStepSave') }}
                </button>
                <button type="button" class="text-xs text-gray-500 hover:underline" @click="adding = false">✕</button>
            </form>
            <button v-else type="button" class="text-sm text-indigo-600 hover:underline" @click="adding = true">+ {{ t('taskSteps.addStep') }}</button>
        </template>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
    </div>
</template>
