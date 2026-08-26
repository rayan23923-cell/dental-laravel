<script setup>
/**
 * "Number of Teeth" marking grid — port of orthodontics.php's
 * `number-of-teeth-table`: 4 rows (Unerupted / Erupted / Erupted /
 * Unerupted) × 16 columns (header `array_merge(range(8,1), range(1,8))`,
 * quadrant-style: 8→1 then 1→8), each cell clickable and opening a picker
 * (the original's `toothSquareModal`) offering Primary teeth A–E, Permanent
 * teeth 1–8, the "/" (Extracted) special mark, or Clear.
 *
 * modelValue is `{ [square_id]: value }`, square_id = `${row_type}_${col}`
 * exactly as `teeth_squares[<?= $square_id ?>]` posts it, so a chart filled
 * in either app parses in the other.
 */
import { ref } from 'vue';
import Modal from '@/Components/Modal.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const ROW_LABELS = ['Unerupted', 'Erupted', 'Erupted', 'Unerupted'];
const ROW_TYPES = ['unerupted1', 'erupted1', 'erupted2', 'unerupted2'];
const HEADER_NUMBERS = [8, 7, 6, 5, 4, 3, 2, 1, 1, 2, 3, 4, 5, 6, 7, 8];
const PRIMARY = ['A', 'B', 'C', 'D', 'E'];
const PERMANENT = [1, 2, 3, 4, 5, 6, 7, 8];

const activeSquare = ref(null);
const showPicker = ref(false);

const openPicker = (squareId) => {
    if (props.disabled) return;
    activeSquare.value = squareId;
    showPicker.value = true;
};

const select = (value) => {
    emit('update:modelValue', { ...props.modelValue, [activeSquare.value]: value });
    showPicker.value = false;
};

const clearSquare = () => {
    const next = { ...props.modelValue };
    delete next[activeSquare.value];
    emit('update:modelValue', next);
    showPicker.value = false;
};
</script>

<template>
    <div>
        <div class="max-w-full overflow-x-auto rounded-lg border-2 border-gray-700" style="-webkit-overflow-scrolling: touch;">
            <table class="w-max border-collapse text-sm" style="table-layout: fixed;">
                <thead>
                    <tr>
                        <th class="border border-gray-700 bg-gray-100 px-2 py-1" style="width: 110px;"></th>
                        <th v-for="(n, i) in HEADER_NUMBERS" :key="i" class="border border-gray-700 bg-gray-100 px-2 py-1 text-center font-semibold" style="width: 40px;">
                            {{ n }}
                        </th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="(label, rowIdx) in ROW_LABELS" :key="rowIdx">
                        <td class="border border-gray-700 bg-gray-50 px-2 py-1 font-bold">{{ label }}</td>
                        <td
                            v-for="col in 16"
                            :key="col"
                            class="h-10 shrink-0 border border-gray-700 text-center align-middle"
                            :class="disabled ? '' : 'cursor-pointer hover:bg-indigo-50'"
                            @click="openPicker(`${ROW_TYPES[rowIdx]}_${col - 1}`)"
                        >
                            {{ modelValue[`${ROW_TYPES[rowIdx]}_${col - 1}`] || '' }}
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>

        <Modal :show="showPicker" @close="showPicker = false" max-width="md">
            <div class="p-6">
                <h3 class="mb-3 text-sm font-semibold text-gray-800">Select Tooth Number</h3>

                <p class="mb-1 text-xs font-bold text-gray-600">Primary Teeth (A-E):</p>
                <div class="mb-3 flex flex-wrap gap-2">
                    <button
                        v-for="letter in PRIMARY"
                        :key="letter"
                        type="button"
                        class="h-9 w-9 rounded border border-indigo-300 text-sm text-indigo-700 hover:bg-indigo-600 hover:text-white"
                        @click="select(letter)"
                    >
                        {{ letter }}
                    </button>
                </div>

                <p class="mb-1 text-xs font-bold text-gray-600">Permanent Teeth (1-8):</p>
                <div class="mb-3 flex flex-wrap gap-2">
                    <button
                        v-for="n in PERMANENT"
                        :key="n"
                        type="button"
                        class="h-9 w-9 rounded border border-green-300 text-sm text-green-700 hover:bg-green-600 hover:text-white"
                        @click="select(String(n))"
                    >
                        {{ n }}
                    </button>
                </div>

                <p class="mb-1 text-xs font-bold text-gray-600">Special Options:</p>
                <div class="mb-4">
                    <button type="button" class="rounded border border-red-300 px-3 py-1.5 text-sm text-red-700 hover:bg-red-600 hover:text-white" @click="select('/')">
                        / Extracted
                    </button>
                </div>

                <button type="button" class="mb-4 w-full rounded border border-red-300 py-1.5 text-sm text-red-700 hover:bg-red-50" @click="clearSquare">
                    Clear
                </button>

                <div class="flex justify-end">
                    <SecondaryButton @click="showPicker = false">Close</SecondaryButton>
                </div>
            </div>
        </Modal>
    </div>
</template>
