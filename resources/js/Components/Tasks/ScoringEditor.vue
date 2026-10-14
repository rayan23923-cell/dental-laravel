<script setup>
import Icon from '@/Components/Icon.vue';
import { useI18n } from 'vue-i18n';

/**
 * Points setup of one task (2026-10-14, by request): how it is measured,
 * the points target, its weight, the kinds of work with their points and
 * the optional multipliers. Edits the object it is given in place.
 */
const { t } = useI18n();
const scoring = defineModel({ type: Object, required: true });

const input = 'rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500';
const addOption = () => scoring.value.options.push({ label: '', points: 0 });
const addModifier = () => scoring.value.modifiers.push({ label: '', factor: 1 });
const addCheck = () => (scoring.value.checklist ??= []).push({ label: '' });
</script>

<template>
    <div class="space-y-3">
        <div class="grid grid-cols-3 gap-2">
            <label class="text-xs text-gray-600">
                {{ t('taskScoring.measure') }}
                <select v-model="scoring.measure" :class="input" class="mt-1 block w-full">
                    <option value="count">{{ t('taskScoring.measureCount') }}</option>
                    <option value="points">{{ t('taskScoring.measurePoints') }}</option>
                    <option value="both">{{ t('taskScoring.measureBoth') }}</option>
                </select>
            </label>
            <label class="text-xs text-gray-600">
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
            <div v-for="(st, i) in scoring.steps" :key="i" class="mb-1 flex items-center gap-2" :class="st.enabled ? '' : 'opacity-50'">
                <input v-model="st.enabled" type="checkbox" class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                <span class="min-w-0 flex-1 text-sm text-gray-700">{{ st.label }}</span>
                <input v-model.number="st.max" type="number" min="0" step="0.5" class="w-24 shrink-0" :class="input" :disabled="!st.enabled" :title="t('taskScoring.stepMax')" />
            </div>
        </div>

        <div v-if="!scoring.steps?.length">
            <div class="mb-1 flex items-center justify-between text-xs font-medium text-gray-700">
                {{ t('taskScoring.options') }}
                <button type="button" class="inline-flex items-center gap-1 text-indigo-600 hover:text-indigo-800" @click="addOption">
                    <Icon name="add" size="text-[16px]" /> {{ t('taskScoring.addOption') }}
                </button>
            </div>
            <div v-for="(o, i) in scoring.options" :key="i" class="mb-1 flex items-center gap-2">
                <input v-model="o.label" type="text" :placeholder="t('taskScoring.optionLabel')" class="min-w-0 flex-1" :class="input" required />
                <input v-model.number="o.points" type="number" min="0" step="0.5" class="w-24 shrink-0" :class="input" required />
                <button type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="scoring.options.splice(i, 1)">
                    <Icon name="close" size="text-[18px]" />
                </button>
            </div>
            <p v-if="!scoring.options.length" class="text-xs text-gray-400">{{ t('taskScoring.noOptions') }}</p>
            <label v-if="scoring.options.length" class="mt-1 flex items-center gap-2 text-xs text-gray-600">
                <input v-model="scoring.graded" type="checkbox" class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                {{ t('taskScoring.graded') }}
            </label>
        </div>

        <div>
            <div class="mb-1 flex items-center justify-between text-xs font-medium text-gray-700">
                {{ t('taskScoring.checklist') }}
                <button type="button" class="inline-flex items-center gap-1 text-indigo-600 hover:text-indigo-800" @click="addCheck">
                    <Icon name="add" size="text-[16px]" /> {{ t('taskScoring.addCheck') }}
                </button>
            </div>
            <div v-for="(c, i) in scoring.checklist ?? []" :key="i" class="mb-1 flex items-center gap-2">
                <input v-model="c.label" type="text" :placeholder="t('taskScoring.checkLabel')" class="min-w-0 flex-1" :class="input" required />
                <button type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="scoring.checklist.splice(i, 1)">
                    <Icon name="close" size="text-[18px]" />
                </button>
            </div>
            <p v-if="scoring.checklist?.length" class="text-xs text-gray-500">{{ t('taskScoring.checklistHint') }}</p>
        </div>

        <div>
            <div class="mb-1 flex items-center justify-between text-xs font-medium text-gray-700">
                {{ t('taskScoring.modifiers') }}
                <button type="button" class="inline-flex items-center gap-1 text-indigo-600 hover:text-indigo-800" @click="addModifier">
                    <Icon name="add" size="text-[16px]" /> {{ t('taskScoring.addModifier') }}
                </button>
            </div>
            <div v-for="(m, i) in scoring.modifiers" :key="i" class="mb-1 flex items-center gap-2">
                <input v-model="m.label" type="text" :placeholder="t('taskScoring.modifierLabel')" class="min-w-0 flex-1" :class="input" required />
                <span class="text-xs text-gray-500">×</span>
                <input v-model.number="m.factor" type="number" min="0" max="10" step="0.0001" class="w-24 shrink-0" :class="input" required />
                <button type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="scoring.modifiers.splice(i, 1)">
                    <Icon name="close" size="text-[18px]" />
                </button>
            </div>
        </div>
    </div>
</template>
