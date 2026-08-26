<script setup>
import { computed, ref } from 'vue';

const props = defineProps({
    modelValue: {
        type: Array,
        default: () => [],
    },
    chartType: {
        type: String,
        default: 'permanent',
    },
});

const emit = defineEmits(['update:modelValue']);

const CONDITIONS = ['healthy', 'cavity', 'decay', 'crack', 'fracture', 'discoloration', 'wear', 'missing', 'other'];

// FDI notation. Permanent quadrants 1-4 (18..11, 21..28, 31..38, 48..41),
// primary (deciduous) quadrants 5-8 (55..51, 61..65, 71..75, 85..81).
const quadrants = computed(() => {
    if (props.chartType === 'primary') {
        return {
            upperRight: [55, 54, 53, 52, 51],
            upperLeft: [61, 62, 63, 64, 65],
            lowerLeft: [71, 72, 73, 74, 75],
            lowerRight: [85, 84, 83, 82, 81],
        };
    }
    return {
        upperRight: [18, 17, 16, 15, 14, 13, 12, 11],
        upperLeft: [21, 22, 23, 24, 25, 26, 27, 28],
        lowerLeft: [31, 32, 33, 34, 35, 36, 37, 38],
        lowerRight: [48, 47, 46, 45, 44, 43, 42, 41],
    };
});

const positionFor = (quadrantKey) => ({
    upperRight: 'upper_right',
    upperLeft: 'upper_left',
    lowerLeft: 'lower_left',
    lowerRight: 'lower_right',
}[quadrantKey]);

const findEntry = (toothNumber) => props.modelValue.find((t) => String(t.tooth_number) === String(toothNumber));

const activeTooth = ref(null);

const toothClass = (toothNumber) => {
    const entry = findEntry(toothNumber);
    if (!entry || entry.condition_type === 'healthy') return 'bg-white border-gray-300 text-gray-700';
    if (entry.condition_type === 'missing') return 'bg-gray-300 border-gray-400 text-gray-500 line-through';
    return 'bg-amber-100 border-amber-400 text-amber-900';
};

const toggleTooth = (toothNumber) => {
    activeTooth.value = activeTooth.value === toothNumber ? null : toothNumber;
};

const setCondition = (toothNumber, quadrantKey, condition) => {
    const list = props.modelValue.filter((t) => String(t.tooth_number) !== String(toothNumber));
    if (condition !== 'healthy') {
        list.push({
            tooth_number: String(toothNumber),
            tooth_position: positionFor(quadrantKey),
            condition_type: condition,
            severity: 'moderate',
            notes: '',
        });
    }
    emit('update:modelValue', list);
    activeTooth.value = null;
};
</script>

<template>
    <div class="space-y-6">
        <div class="grid grid-cols-2 gap-4">
            <div>
                <p class="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">Upper Right</p>
                <div class="flex flex-wrap gap-1">
                    <div v-for="tooth in quadrants.upperRight" :key="tooth" class="relative">
                        <button
                            type="button"
                            class="h-9 w-9 rounded border text-xs font-medium"
                            :class="toothClass(tooth)"
                            @click="toggleTooth(tooth)"
                        >
                            {{ tooth }}
                        </button>
                        <div v-if="activeTooth === tooth" class="absolute z-10 mt-1 w-40 rounded-md border border-gray-200 bg-white p-2 shadow-lg">
                            <button
                                v-for="c in CONDITIONS"
                                :key="c"
                                type="button"
                                class="block w-full rounded px-2 py-1 text-left text-xs hover:bg-gray-100"
                                @click="setCondition(tooth, 'upperRight', c)"
                            >
                                {{ c }}
                            </button>
                        </div>
                    </div>
                </div>
            </div>
            <div>
                <p class="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">Upper Left</p>
                <div class="flex flex-wrap gap-1">
                    <div v-for="tooth in quadrants.upperLeft" :key="tooth" class="relative">
                        <button
                            type="button"
                            class="h-9 w-9 rounded border text-xs font-medium"
                            :class="toothClass(tooth)"
                            @click="toggleTooth(tooth)"
                        >
                            {{ tooth }}
                        </button>
                        <div v-if="activeTooth === tooth" class="absolute z-10 mt-1 w-40 rounded-md border border-gray-200 bg-white p-2 shadow-lg">
                            <button
                                v-for="c in CONDITIONS"
                                :key="c"
                                type="button"
                                class="block w-full rounded px-2 py-1 text-left text-xs hover:bg-gray-100"
                                @click="setCondition(tooth, 'upperLeft', c)"
                            >
                                {{ c }}
                            </button>
                        </div>
                    </div>
                </div>
            </div>
            <div>
                <p class="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">Lower Right</p>
                <div class="flex flex-wrap gap-1">
                    <div v-for="tooth in quadrants.lowerRight" :key="tooth" class="relative">
                        <button
                            type="button"
                            class="h-9 w-9 rounded border text-xs font-medium"
                            :class="toothClass(tooth)"
                            @click="toggleTooth(tooth)"
                        >
                            {{ tooth }}
                        </button>
                        <div v-if="activeTooth === tooth" class="absolute z-10 mt-1 w-40 rounded-md border border-gray-200 bg-white p-2 shadow-lg">
                            <button
                                v-for="c in CONDITIONS"
                                :key="c"
                                type="button"
                                class="block w-full rounded px-2 py-1 text-left text-xs hover:bg-gray-100"
                                @click="setCondition(tooth, 'lowerRight', c)"
                            >
                                {{ c }}
                            </button>
                        </div>
                    </div>
                </div>
            </div>
            <div>
                <p class="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">Lower Left</p>
                <div class="flex flex-wrap gap-1">
                    <div v-for="tooth in quadrants.lowerLeft" :key="tooth" class="relative">
                        <button
                            type="button"
                            class="h-9 w-9 rounded border text-xs font-medium"
                            :class="toothClass(tooth)"
                            @click="toggleTooth(tooth)"
                        >
                            {{ tooth }}
                        </button>
                        <div v-if="activeTooth === tooth" class="absolute z-10 mt-1 w-40 rounded-md border border-gray-200 bg-white p-2 shadow-lg">
                            <button
                                v-for="c in CONDITIONS"
                                :key="c"
                                type="button"
                                class="block w-full rounded px-2 py-1 text-left text-xs hover:bg-gray-100"
                                @click="setCondition(tooth, 'lowerLeft', c)"
                            >
                                {{ c }}
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div v-if="modelValue.length > 0" class="rounded-md border border-gray-200 p-3">
            <p class="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">Selected Teeth</p>
            <div class="flex flex-wrap gap-2">
                <span
                    v-for="entry in modelValue"
                    :key="entry.tooth_number"
                    class="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-xs text-amber-900"
                >
                    #{{ entry.tooth_number }} — {{ entry.condition_type }}
                </span>
            </div>
        </div>
    </div>
</template>
