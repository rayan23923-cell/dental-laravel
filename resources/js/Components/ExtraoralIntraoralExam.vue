<script setup>
/**
 * Extraoral/Intraoral Examination — port of oral_medicine.php: a 7-muscle
 * tenderness grid (right/left text per muscle), four more right/left pairs
 * (TMJ clicking, preauricular pain, swelling, deviation on opening), plus
 * max mouth opening, facial defects and oral mucosa condition as free text,
 * and the four head pain-location diagrams (`head_diagrams`) — see
 * Components/HeadDiagramsBoard.vue for the click-to-mark mechanics.
 */
import HeadDiagramsBoard from '@/Components/HeadDiagramsBoard.vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const set = (key, value) => emit('update:modelValue', { ...props.modelValue, [key]: value });

// Preserves whatever's already under `key` (an object) while updating one
// of its own sub-keys — used for the right/left paired fields below.
const setPaired = (key, side, value) => {
    set(key, { ...(props.modelValue?.[key] ?? {}), [side]: value });
};
const pairedValue = (key, side) => props.modelValue?.[key]?.[side] ?? '';

const MUSCLES = [
    ['masseter', 'Masseter'], ['temporalis', 'Temporalis'], ['m_pterygoid', 'M. Pterygoid'],
    ['l_pterygoid', 'L. Pterygoid'], ['suprahyoids', 'Suprahyoids'],
    ['sternocleidomastoid', 'Sternocleidomastoid'], ['occipital', 'Occipital M.'],
];

const setMuscle = (key, side, value) => {
    const muscles = { ...(props.modelValue?.muscles ?? {}) };
    muscles[key] = { ...(muscles[key] ?? {}), [side]: value };
    set('muscles', muscles);
};
const muscleValue = (key, side) => props.modelValue?.muscles?.[key]?.[side] ?? '';
</script>

<template>
    <div class="space-y-5">
        <div>
            <h4 class="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500">Muscle tenderness</h4>
            <div class="space-y-1.5">
                <div v-for="[key, label] in MUSCLES" :key="key" class="grid grid-cols-3 items-center gap-2 text-sm">
                    <span class="text-gray-700">{{ label }}</span>
                    <input type="text" :disabled="disabled" :value="muscleValue(key, 'right')" placeholder="R" class="rounded border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="setMuscle(key, 'right', $event.target.value)" />
                    <input type="text" :disabled="disabled" :value="muscleValue(key, 'left')" placeholder="L" class="rounded border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="setMuscle(key, 'left', $event.target.value)" />
                </div>
            </div>
        </div>

        <div class="space-y-1.5">
            <div v-for="[key, label] in [['tmj_clicking', 'TMJ Clicking or crepitation'], ['preauricular_pain', 'Preauricular pain'], ['swelling', 'Swelling or asymmetry of the face'], ['deviation_opening', 'Deviation on opening']]" :key="key" class="grid grid-cols-3 items-center gap-2 text-sm">
                <span class="text-gray-700">{{ label }}</span>
                <input type="text" :disabled="disabled" :value="pairedValue(key, 'right')" placeholder="R" class="rounded border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="setPaired(key, 'right', $event.target.value)" />
                <input type="text" :disabled="disabled" :value="pairedValue(key, 'left')" placeholder="L" class="rounded border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="setPaired(key, 'left', $event.target.value)" />
            </div>
        </div>

        <div>
            <label class="mb-1 block text-xs font-medium text-gray-600">Maximum mouth opening (or interincisal distance), cm</label>
            <input type="text" :disabled="disabled" :value="modelValue.max_mouth_opening ?? ''" class="block w-40 rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="set('max_mouth_opening', $event.target.value)" />
        </div>

        <div>
            <label class="mb-1 block text-xs font-medium text-gray-600">Facial Defects or congenital abnormalities</label>
            <textarea :disabled="disabled" :value="modelValue.facial_defects ?? ''" rows="2" class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="set('facial_defects', $event.target.value)"></textarea>
        </div>

        <div>
            <label class="mb-1 block text-xs font-medium text-gray-600">Condition of the oral mucosa (ulcer, traumatic, white or red lesions…)</label>
            <textarea :disabled="disabled" :value="modelValue.oral_mucosa_condition ?? ''" rows="2" class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="set('oral_mucosa_condition', $event.target.value)"></textarea>
        </div>

        <div>
            <h4 class="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500">Head pain-location diagrams</h4>
            <HeadDiagramsBoard :model-value="modelValue.head_diagrams ?? {}" :disabled="disabled" @update:model-value="set('head_diagrams', $event)" />
        </div>
    </div>
</template>
