<script setup>
import Icon from '@/Components/Icon.vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * The work done on a case (2026-10-14, by request): kind of work, how many
 * and any multipliers, with the points it adds up to. A graded task has one
 * grade per item instead (up to the item's points), and a checklist's parts
 * are ticked here ({check: index}). The server recomputes the points from
 * the task's own setup.
 */
const { t } = useI18n();
const props = defineProps({ scoring: { type: Object, required: true } });
const items = defineModel({ type: Array, required: true });

const input = 'rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500';
// Points switched off (2026-10-16): items are still recorded, without points or totals.
const off = computed(() => !!props.scoring.points_off);
const graded = computed(() => !off.value && !!props.scoring.graded);
const work = computed(() => items.value.filter((item) => item.check === undefined));
const firstOn = () => Math.max(0, (props.scoring.options ?? []).findIndex((o) => o.enabled !== false));
const add = () => items.value.push({ option: firstOn(), qty: 1, modifiers: [] });
const remove = (item) => items.value.splice(items.value.indexOf(item), 1);
const pointsOf = (item) => {
    const option = props.scoring.options?.[item.option];
    if (!option) return 0;
    const factor = item.modifiers.reduce((f, m) => f * (props.scoring.modifiers[m]?.factor ?? 1), 1);
    const base = graded.value ? Math.min(Number(item.grade) || 0, option.points) : option.points * (item.qty || 1);
    return Math.round(base * factor * 100) / 100;
};
const total = computed(() => Math.round(work.value.reduce((sum, item) => sum + pointsOf(item), 0) * 100) / 100);
const toggle = (item, m) => {
    const i = item.modifiers.indexOf(m);
    i === -1 ? item.modifiers.push(m) : item.modifiers.splice(i, 1);
};
const isChecked = (ci) => items.value.some((item) => item.check === ci);
// Graded checklist parts (2026-10-16): a ticked part takes the supervisor's grade, up to its max.
const checkItem = (ci) => items.value.find((item) => item.check === ci);
const checklistScored = computed(() => !off.value && (props.scoring.checklist ?? []).some((c) => c.scored));
const checklistPoints = computed(
    () =>
        Math.round(
            (props.scoring.checklist ?? []).reduce((sum, c, ci) => {
                const item = checkItem(ci);
                return c.scored && item ? sum + Math.min(Math.max(Number(item.grade) || 0, 0), Number(c.max) || 0) : sum;
            }, 0) * 100,
        ) / 100,
);
const checklistMax = computed(() => (props.scoring.checklist ?? []).filter((c) => c.scored).reduce((sum, c) => sum + (Number(c.max) || 0), 0));
const toggleCheck = (ci) => {
    const i = items.value.findIndex((item) => item.check === ci);
    i === -1 ? items.value.push({ check: ci }) : items.value.splice(i, 1);
};
</script>

<template>
    <div class="space-y-3">
        <div v-if="scoring.checklist?.length" class="rounded-md border border-emerald-100 bg-emerald-50/40 p-3">
            <div class="mb-2 text-sm font-medium text-gray-800">{{ t('taskScoring.checklistDone') }}</div>
            <div v-for="(c, ci) in scoring.checklist" :key="ci" class="mb-1 flex items-center gap-2 text-sm text-gray-700">
                <label class="flex min-w-0 flex-1 items-center gap-2">
                    <input type="checkbox" :checked="isChecked(ci)" class="rounded border-gray-300 text-emerald-600 focus:ring-emerald-500" @change="toggleCheck(ci)" />
                    {{ c.label }}
                </label>
                <template v-if="!off && c.scored && isChecked(ci)">
                    <input v-model.number="checkItem(ci).grade" type="number" min="0" :max="c.max" step="0.5" class="w-20 shrink-0" :class="input" />
                    <span class="w-12 shrink-0 text-xs text-gray-500">/ {{ c.max }}</span>
                </template>
                <span v-else-if="!off && c.scored" class="w-12 shrink-0 text-xs text-gray-400">/ {{ c.max }}</span>
            </div>
            <div v-if="checklistScored" class="mt-2 flex items-center justify-between border-t border-emerald-100 pt-2 text-sm font-semibold text-indigo-800">
                <span>{{ t('taskScoring.stepsTotal') }}</span>
                <span>{{ checklistPoints }} / {{ checklistMax }}</span>
            </div>
        </div>

        <div v-if="scoring.options?.length" class="rounded-md border border-indigo-100 bg-indigo-50/40 p-3">
            <div class="mb-2 flex items-center justify-between text-sm font-medium text-gray-800">
                {{ graded ? t('taskScoring.gradeItems') : t('taskScoring.workDone') }}
                <span v-if="!off" class="rounded-full bg-indigo-600 px-2 py-0.5 text-xs text-white">{{ t('taskScoring.pointsValue', { n: total }) }}</span>
            </div>
            <template v-if="graded">
                <div v-for="item in work" :key="item.option" class="mb-1 flex items-center gap-2 rounded bg-white p-2 shadow-sm">
                    <span class="min-w-0 flex-1 text-sm text-gray-700">{{ scoring.options[item.option]?.label }}</span>
                    <input v-model.number="item.grade" type="number" min="0" :max="scoring.options[item.option]?.points" step="0.5" class="w-20 shrink-0" :class="input" />
                    <span class="w-12 shrink-0 text-xs text-gray-500">/ {{ scoring.options[item.option]?.points }}</span>
                </div>
            </template>
            <template v-else>
                <div v-for="(item, i) in work" :key="i" class="mb-2 rounded bg-white p-2 shadow-sm">
                    <div class="flex items-center gap-2">
                        <select v-model.number="item.option" class="min-w-0 flex-1" :class="input">
                            <template v-for="(o, oi) in scoring.options" :key="oi">
                                <option v-if="o.enabled !== false || item.option === oi" :value="oi">{{ o.label }}<template v-if="!off"> ({{ o.points }})</template></option>
                            </template>
                        </select>
                        <input v-model.number="item.qty" type="number" min="1" max="100" class="w-16 shrink-0" :class="input" :title="t('taskScoring.qty')" />
                        <span v-if="!off" class="w-14 shrink-0 text-center text-xs text-gray-600">{{ pointsOf(item) }}</span>
                        <button type="button" class="shrink-0 text-gray-400 hover:text-red-600" :title="t('common.delete')" @click="remove(item)">
                            <Icon name="close" size="text-[18px]" />
                        </button>
                    </div>
                    <div v-if="!off && scoring.modifiers?.length" class="mt-2 flex flex-wrap gap-1">
                        <button
                            v-for="(m, mi) in scoring.modifiers"
                            :key="mi"
                            type="button"
                            class="rounded-full px-2 py-0.5 text-xs ring-1"
                            :class="item.modifiers.includes(mi) ? 'bg-indigo-600 text-white ring-indigo-600' : 'bg-white text-gray-600 ring-gray-200'"
                            @click="toggle(item, mi)"
                        >
                            {{ m.label }} ×{{ +Number(m.factor).toFixed(2) }}
                        </button>
                    </div>
                </div>
                <button type="button" class="inline-flex items-center gap-1 text-sm text-indigo-600 hover:text-indigo-800" @click="add">
                    <Icon name="add" size="text-[18px]" /> {{ t('taskScoring.addWork') }}
                </button>
            </template>
        </div>
    </div>
</template>
