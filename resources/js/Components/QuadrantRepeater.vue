<script setup>
/**
 * Repeating "info + quadrant tooth picker" rows — port of orthodontics.php's
 * two repeaters that share this exact shape: "Stages of treatment"
 * (`treatment_stages`) and "Appliance type & Design" (`appliance_designs`).
 * Both store `{ [index]: { info: string, quadrants: string } }`, 1-based
 * indices, exactly as `treatment_stage_info_N`/`treatment_stage_N` (and the
 * appliance_design_* equivalents) collect them.
 */
import { computed } from 'vue';
import QuadrantTeeth from '@/Components/QuadrantTeeth.vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
    itemLabel: { type: String, default: 'Item' },
    infoLabel: { type: String, default: 'Information' },
});

const emit = defineEmits(['update:modelValue']);

// Rows are keyed 1..N with no gaps, same as the original's counters.
const indices = computed(() => {
    const keys = Object.keys(props.modelValue)
        .map(Number)
        .filter((n) => Number.isInteger(n) && n > 0);
    return keys.length ? keys.sort((a, b) => a - b) : [1];
});

const rowValue = (i) => props.modelValue[i] ?? { info: '', quadrants: '' };

const setInfo = (i, info) => {
    emit('update:modelValue', { ...props.modelValue, [i]: { ...rowValue(i), info } });
};
const setQuadrants = (i, quadrants) => {
    emit('update:modelValue', { ...props.modelValue, [i]: { ...rowValue(i), quadrants } });
};

const addRow = () => {
    const next = { ...props.modelValue };
    const nextIndex = (indices.value.length ? Math.max(...indices.value) : 0) + 1;
    next[nextIndex] = { info: '', quadrants: '' };
    emit('update:modelValue', next);
};

const removeRow = (i) => {
    const next = { ...props.modelValue };
    delete next[i];
    emit('update:modelValue', next);
};
</script>

<template>
    <div class="space-y-4">
        <div v-for="i in indices" :key="i" class="rounded-lg border border-gray-200 bg-gray-50 p-3">
            <div class="mb-2 flex items-center justify-between">
                <span class="text-sm font-bold text-gray-700">{{ itemLabel }} {{ i }}</span>
                <button
                    v-if="!disabled && indices.length > 1"
                    type="button"
                    class="text-xs text-red-600 hover:underline"
                    @click="removeRow(i)"
                >
                    Remove
                </button>
            </div>

            <label class="mb-1 block text-xs font-medium text-gray-600">{{ infoLabel }}</label>
            <input
                type="text"
                :disabled="disabled"
                :value="rowValue(i).info"
                class="mb-3 block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                @input="setInfo(i, $event.target.value)"
            />

            <label class="mb-1 block text-xs font-medium text-gray-600">Teeth Selection</label>
            <QuadrantTeeth :model-value="rowValue(i).quadrants" :disabled="disabled" @update:model-value="setQuadrants(i, $event)" />
        </div>

        <button v-if="!disabled" type="button" class="rounded-md border border-green-300 px-3 py-1.5 text-sm text-green-700 hover:bg-green-50" @click="addRow">
            + Add {{ itemLabel }}
        </button>
    </div>
</template>
