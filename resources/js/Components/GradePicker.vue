<script setup>
/**
 * Picks a grade with a tap (2026-10-22, by request: "سكرول ارقام او اي
 * طريقة اسهل ... بصورة سهلة وسريعة"): a big readout, a grid of the whole
 * numbers up to the max (or quick percentages for a large max), a "+ half"
 * chip, a slider for fine control and −/+ buttons. v-model is a number or
 * null.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    modelValue: { type: Number, default: null },
    max: { type: Number, required: true },
    step: { type: Number, default: 0.5 },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const clamp = (v) => Math.min(props.max, Math.max(0, Math.round(v / props.step) * props.step));
const set = (v) => emit('update:modelValue', v === null ? null : clamp(v));

const whole = computed(() => Math.floor(props.modelValue ?? -1));
const hasHalf = computed(() => props.modelValue !== null && props.modelValue % 1 !== 0);
const grid = computed(() => (props.max <= 20 ? Array.from({ length: Math.floor(props.max) + 1 }, (_, i) => i) : null));
const quick = computed(() => [100, 90, 80, 70, 60, 50].map((p) => ({ p, v: clamp((props.max * p) / 100) })));
const pickWhole = (n) => set(hasHalf.value && n + 0.5 <= props.max ? n + 0.5 : n);
const toggleHalf = () => {
    if (props.modelValue === null) return set(0.5);
    set(hasHalf.value ? Math.floor(props.modelValue) : Math.floor(props.modelValue) + 0.5);
};
const ratio = computed(() => (props.modelValue === null ? 0 : props.modelValue / props.max));
const tone = computed(() => (ratio.value >= 0.85 ? 'text-emerald-600' : ratio.value >= 0.6 ? 'text-indigo-600' : ratio.value >= 0.4 ? 'text-amber-600' : 'text-rose-600'));
</script>

<template>
    <div class="space-y-4 select-none">
        <div class="flex items-center justify-between gap-3 rounded-2xl bg-gradient-to-l from-indigo-50 to-white p-4 ring-1 ring-indigo-100">
            <button
                type="button"
                class="flex h-11 w-11 items-center justify-center rounded-full bg-white text-2xl font-bold text-gray-700 shadow ring-1 ring-gray-200 hover:bg-gray-50 active:scale-95"
                @click="set((modelValue ?? 0) - step)"
            >
                −
            </button>
            <div class="text-center">
                <div class="text-5xl font-bold tabular-nums leading-none" :class="modelValue === null ? 'text-gray-300' : tone">
                    {{ modelValue === null ? '—' : modelValue }}
                </div>
                <div class="mt-1 text-xs text-gray-500">{{ t('gradePicker.outOf', { max }) }}</div>
            </div>
            <button
                type="button"
                class="flex h-11 w-11 items-center justify-center rounded-full bg-indigo-600 text-2xl font-bold text-white shadow hover:bg-indigo-700 active:scale-95"
                @click="set((modelValue ?? -step) + step)"
            >
                +
            </button>
        </div>

        <div v-if="grid" class="grid grid-cols-6 gap-2 sm:grid-cols-7" dir="ltr">
            <button
                v-for="n in grid"
                :key="n"
                type="button"
                class="h-11 rounded-xl text-base font-semibold tabular-nums transition active:scale-95"
                :class="whole === n ? 'bg-indigo-600 text-white shadow-md ring-2 ring-indigo-300' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-indigo-50'"
                @click="pickWhole(n)"
            >
                {{ n }}
            </button>
        </div>
        <div v-else class="grid grid-cols-3 gap-2">
            <button
                v-for="q in quick"
                :key="q.p"
                type="button"
                class="rounded-xl px-2 py-2.5 text-sm font-semibold tabular-nums transition active:scale-95"
                :class="modelValue === q.v ? 'bg-indigo-600 text-white shadow-md' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-indigo-50'"
                @click="set(q.v)"
            >
                {{ q.v }} <span class="text-xs font-normal opacity-70">({{ q.p }}%)</span>
            </button>
        </div>

        <input
            type="range"
            min="0"
            :max="max"
            :step="step"
            :value="modelValue ?? 0"
            class="w-full accent-indigo-600"
            dir="ltr"
            @input="set(Number($event.target.value))"
        />

        <div class="flex flex-wrap gap-2">
            <button
                v-if="step <= 0.5"
                type="button"
                class="rounded-full px-3 py-1.5 text-sm font-medium transition"
                :class="hasHalf ? 'bg-amber-500 text-white' : 'bg-amber-50 text-amber-700 ring-1 ring-amber-200 hover:bg-amber-100'"
                @click="toggleHalf"
            >
                {{ t('gradePicker.half') }}
            </button>
            <button type="button" class="rounded-full bg-emerald-50 px-3 py-1.5 text-sm font-medium text-emerald-700 ring-1 ring-emerald-200 hover:bg-emerald-100" @click="set(max)">
                {{ t('gradePicker.full') }} ({{ max }})
            </button>
            <button type="button" class="rounded-full px-3 py-1.5 text-sm text-gray-500 hover:bg-gray-100" @click="set(null)">{{ t('gradePicker.clear') }}</button>
        </div>
    </div>
</template>
