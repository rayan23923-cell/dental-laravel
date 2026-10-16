<script setup>
import Icon from '@/Components/Icon.vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Points setup of one task (2026-10-14, by request): how it is measured,
 * the points target, its weight, the kinds of work with their points and
 * the optional multipliers. Edits the object it is given in place.
 */
const { t } = useI18n();
const scoring = defineModel({ type: Object, required: true });

// Points switched off (2026-10-16, by request): the lists stay, their points and totals are hidden.
const off = computed(() => !!scoring.value.points_off);
const input = 'rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500';
// Labels wrap onto as many lines as they need (2026-10-15), so they read whole on a phone.
const rowsFor = (text) => Math.max(1, Math.ceil((text?.length ?? 0) / 28));
const addOption = () => scoring.value.options.push({ label: '', points: 0, enabled: true });
// Kinds of work can be switched off (2026-10-16, by request); the enabled ones' points are totalled below.
const isOn = (o) => o.enabled !== false;
const optionsTotal = computed(() => Math.round(scoring.value.options.filter(isOn).reduce((sum, o) => sum + (Number(o.points) || 0), 0) * 100) / 100);
const addModifier = () => scoring.value.modifiers.push({ label: '', factor: 1 });
const addCheck = () => (scoring.value.checklist ??= []).push({ label: '' });
// Steps added by hand (2026-10-16, by request) sit beside the sheet's own and are graded on the task.
const addStep = () => scoring.value.steps.push({ key: `custom_${Date.now()}`, label: '', max: 10, enabled: true, custom: true });
// Checklist parts may carry a grade (2026-10-16, by request), totalled below the list.
const checklistTotal = computed(() =>
    Math.round((scoring.value.checklist ?? []).filter((c) => c.scored).reduce((sum, c) => sum + (Number(c.max) || 0), 0) * 100) / 100,
);
const toggleScored = (c) => {
    c.scored = !c.scored;
    if (c.scored && (c.max === undefined || c.max === null || c.max === '')) c.max = 10;
};
const stepsTotal = computed(() =>
    Math.round((scoring.value.steps ?? []).filter((st) => st.enabled).reduce((sum, st) => sum + (Number(st.max) || 0), 0) * 100) / 100,
);
</script>

<template>
    <div class="space-y-3">
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
            <label v-if="!off" class="text-xs text-gray-600">
                {{ t('taskScoring.measure') }}
                <select v-model="scoring.measure" :class="input" class="mt-1 block w-full">
                    <option value="count">{{ t('taskScoring.measureCount') }}</option>
                    <option value="points">{{ t('taskScoring.measurePoints') }}</option>
                    <option value="both">{{ t('taskScoring.measureBoth') }}</option>
                </select>
            </label>
            <label v-if="!off" class="text-xs text-gray-600">
                {{ t('taskScoring.minPoints') }}
                <input v-model.number="scoring.min_points" type="number" min="0" step="0.5" :disabled="scoring.measure === 'count' || !!scoring.steps?.length" :class="input" class="mt-1 block w-full disabled:bg-gray-100" />
            </label>
            <label class="text-xs text-gray-600">
                {{ t('taskScoring.weight') }}
                <input v-model.number="scoring.weight" type="number" min="0" max="100" step="0.5" :placeholder="t('taskScoring.weightAuto')" :class="input" class="mt-1 block w-full" />
            </label>
        </div>

        <div v-if="scoring.steps?.length">
            <div class="mb-1 text-xs font-medium text-gray-700">{{ t('taskScoring.steps') }}</div>
            <p class="mb-1 text-xs text-gray-500">{{ t('taskScoring.stepsHint') }}</p>
            <div v-for="(st, i) in scoring.steps" :key="st.key" class="mb-1 flex items-center gap-2" :class="st.enabled ? '' : 'opacity-50'">
                <input v-model="st.enabled" type="checkbox" class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                <textarea v-if="st.custom" v-model="st.label" :rows="rowsFor(st.label)" :placeholder="t('taskScoring.stepLabel')" class="min-w-0 flex-1 resize-y leading-6" :class="input" required maxlength="100" @keydown.enter.prevent></textarea>
                <span v-else class="min-w-0 flex-1 text-sm text-gray-700">{{ st.label }}</span>
                <input v-if="!off" v-model.number="st.max" type="number" min="0" step="0.5" class="w-24 shrink-0" :class="input" :disabled="!st.enabled" :title="t('taskScoring.stepMax')" />
                <button v-if="st.custom" type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="scoring.steps.splice(i, 1)">
                    <Icon name="close" size="text-[18px]" />
                </button>
            </div>
            <button type="button" class="mt-1 inline-flex items-center gap-1 text-xs font-medium text-indigo-600 hover:text-indigo-800" @click="addStep">
                <Icon name="add" size="text-[16px]" /> {{ t('taskScoring.addStep') }}
            </button>
            <div v-if="!off" class="mt-2 flex items-center justify-between rounded-md bg-indigo-50 px-3 py-2 text-sm font-semibold text-indigo-800">
                <span>{{ t('taskScoring.stepsTotal') }}</span>
                <span>{{ stepsTotal }}</span>
            </div>
        </div>

        <div v-if="!scoring.steps?.length">
            <div class="mb-1 flex items-center justify-between text-xs font-medium text-gray-700">
                {{ t('taskScoring.options') }}
                <button type="button" class="inline-flex items-center gap-1 text-indigo-600 hover:text-indigo-800" @click="addOption">
                    <Icon name="add" size="text-[16px]" /> {{ t('taskScoring.addOption') }}
                </button>
            </div>
            <div v-for="(o, i) in scoring.options" :key="i" class="mb-1 flex items-start gap-2" :class="isOn(o) ? '' : 'opacity-50'">
                <input type="checkbox" :checked="isOn(o)" class="mt-3 shrink-0 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" @change="o.enabled = !isOn(o)" />
                <textarea v-model="o.label" :rows="rowsFor(o.label)" :placeholder="t('taskScoring.optionLabel')" class="min-w-0 flex-1 resize-y leading-6" :class="input" required @keydown.enter.prevent></textarea>
                <input v-if="!off" v-model.number="o.points" type="number" min="0" step="0.5" class="w-24 shrink-0" :class="input" required />
                <button type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="scoring.options.splice(i, 1)">
                    <Icon name="close" size="text-[18px]" />
                </button>
            </div>
            <p v-if="!scoring.options.length" class="text-xs text-gray-400">{{ t('taskScoring.noOptions') }}</p>
            <div v-else-if="!off" class="mt-2 flex items-center justify-between rounded-md bg-indigo-50 px-3 py-2 text-sm font-semibold text-indigo-800">
                <span>{{ t('taskScoring.stepsTotal') }}</span>
                <span>{{ optionsTotal }}</span>
            </div>
            <label v-if="scoring.options.length && !off" class="mt-1 flex items-center gap-2 text-xs text-gray-600">
                <input v-model="scoring.graded" type="checkbox" class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                {{ t('taskScoring.graded') }}
            </label>
        </div>

        <label class="flex items-center gap-2 text-xs text-gray-700">
            <input v-model="scoring.endo" type="checkbox" class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" />
            {{ t('taskScoring.endoHint') }}
        </label>

        <div>
            <div class="mb-1 flex items-center justify-between text-xs font-medium text-gray-700">
                {{ t('taskScoring.checklist') }}
                <button type="button" class="inline-flex items-center gap-1 text-indigo-600 hover:text-indigo-800" @click="addCheck">
                    <Icon name="add" size="text-[16px]" /> {{ t('taskScoring.addCheck') }}
                </button>
            </div>
            <div v-for="(c, i) in scoring.checklist ?? []" :key="i" class="mb-2">
                <div class="flex items-center gap-2">
                    <textarea v-model="c.label" :rows="rowsFor(c.label)" :placeholder="t('taskScoring.checkLabel')" class="min-w-0 flex-1 resize-y leading-6" :class="input" required @keydown.enter.prevent></textarea>
                    <button type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="scoring.checklist.splice(i, 1)">
                        <Icon name="close" size="text-[18px]" />
                    </button>
                </div>
                <div v-if="!off" class="mt-1 flex items-center gap-2 text-xs text-gray-600">
                    <label class="flex items-center gap-1">
                        <input type="checkbox" :checked="!!c.scored" class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" @change="toggleScored(c)" />
                        {{ t('taskScoring.checkScored') }}
                    </label>
                    <input v-if="c.scored" v-model.number="c.max" type="number" min="0" step="0.5" class="w-24" :class="input" :title="t('taskScoring.stepMax')" required />
                </div>
            </div>
            <p v-if="scoring.checklist?.length" class="text-xs text-gray-500">{{ t('taskScoring.checklistHint') }}</p>
            <div v-if="!off && scoring.checklist?.some((c) => c.scored)" class="mt-2 flex items-center justify-between rounded-md bg-indigo-50 px-3 py-2 text-sm font-semibold text-indigo-800">
                <span>{{ t('taskScoring.stepsTotal') }}</span>
                <span>{{ checklistTotal }}</span>
            </div>
        </div>

        <div v-if="!off">
            <div class="mb-1 flex items-center justify-between text-xs font-medium text-gray-700">
                {{ t('taskScoring.modifiers') }}
                <button type="button" class="inline-flex items-center gap-1 text-indigo-600 hover:text-indigo-800" @click="addModifier">
                    <Icon name="add" size="text-[16px]" /> {{ t('taskScoring.addModifier') }}
                </button>
            </div>
            <div v-for="(m, i) in scoring.modifiers" :key="i" class="mb-1 flex items-center gap-2">
                <textarea v-model="m.label" :rows="rowsFor(m.label)" :placeholder="t('taskScoring.modifierLabel')" class="min-w-0 flex-1 resize-y leading-6" :class="input" required @keydown.enter.prevent></textarea>
                <span class="text-xs text-gray-500">×</span>
                <input v-model.number="m.factor" type="number" min="0" max="10" step="0.0001" class="w-24 shrink-0" :class="input" required />
                <button type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="scoring.modifiers.splice(i, 1)">
                    <Icon name="close" size="text-[18px]" />
                </button>
            </div>
        </div>
    </div>
</template>
