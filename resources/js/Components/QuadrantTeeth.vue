<script setup>
/**
 * Quadrant tooth picker — port of the `fdi-cross` selector used across the
 * original app's case sheets (complete_denture.php, prosthodontics.php,
 * surgery.php …).
 *
 * Teeth are identified by quadrant code + number (UR8, UL1, LR6 …), and the
 * field stores a comma-separated list of those codes exactly as the original
 * does (`placeholder="مثال: UR8, UL1"`). Quadrant ordering is the original's
 * $quadrantOrderConfig — outer-to-inner on the right quadrants, inner-to-outer
 * on the left, so the four blocks read as a real mouth chart.
 */
import { computed } from 'vue';

const props = defineProps({
    modelValue: { type: String, default: '' },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const QUADRANTS = {
    UR: [8, 7, 6, 5, 4, 3, 2, 1],
    UL: [1, 2, 3, 4, 5, 6, 7, 8],
    LR: [8, 7, 6, 5, 4, 3, 2, 1],
    LL: [1, 2, 3, 4, 5, 6, 7, 8],
};

const selected = computed(() =>
    (props.modelValue ?? '')
        .split(',')
        .map((c) => c.trim())
        .filter(Boolean)
);

const isSelected = (code) => selected.value.includes(code);

const toggle = (code) => {
    if (props.disabled) return;
    const next = isSelected(code) ? selected.value.filter((c) => c !== code) : [...selected.value, code];
    emit('update:modelValue', next.join(', '));
};

const clear = () => {
    if (props.disabled) return;
    emit('update:modelValue', '');
};
</script>

<template>
    <div>
        <div class="flex items-center gap-2">
            <input
                type="text"
                :value="modelValue"
                readonly
                placeholder="e.g. UR8, UL1"
                class="block w-full rounded-md border-gray-300 bg-gray-50 text-sm shadow-sm"
            />
            <button v-if="!disabled && modelValue" type="button" @click="clear" class="shrink-0 text-xs text-red-600 hover:underline">
                Clear
            </button>
        </div>

        <!--
            Same horizontal-scroll fix as ToothOdontogram.vue's main grid:
            `overflow-x-auto` on the outer wrapper did nothing on its own
            here — it wasn't even present — and a flex row with no explicit
            width shrinks its buttons to fit a narrow screen instead of
            overflowing it, which is what the cramped, sliced-off columns in
            a mobile screenshot were. `w-max` keeps the row at its natural,
            un-shrunk width and `shrink-0` stops the browser compressing
            individual buttons, so the row genuinely overflows and this
            wrapper's `overflow-x-auto` can scroll it.
        -->
        <div class="mt-3 max-w-full overflow-x-auto rounded-lg border border-gray-200 p-2" style="-webkit-overflow-scrolling: touch;">
            <div v-for="row in [['UR', 'UL'], ['LR', 'LL']]" :key="row.join()" class="flex w-max">
                <div
                    v-for="q in row"
                    :key="q"
                    class="flex shrink-0 gap-0.5 px-2 py-1"
                    :class="q === 'UR' || q === 'LR' ? 'border-r border-gray-300' : ''"
                >
                    <button
                        v-for="n in QUADRANTS[q]"
                        :key="`${q}${n}`"
                        type="button"
                        :disabled="disabled"
                        class="h-7 w-7 shrink-0 rounded border text-xs transition"
                        :class="isSelected(`${q}${n}`)
                            ? 'border-indigo-600 bg-indigo-600 text-white'
                            : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-100 disabled:opacity-50'"
                        :title="`${q}${n}`"
                        @click="toggle(`${q}${n}`)"
                    >
                        {{ n }}
                    </button>
                </div>
            </div>
        </div>
    </div>
</template>
