<script setup>
/**
 * Periodontal's "Plaque Index" per-visit dental chart — a completely
 * separate feature from PerioChart.vue's BOP/PPD/CAL tables despite
 * sharing the same `chart_data` column, under its own `dentalCharts`
 * top-level key (see `App\Support\PlaqueChart`'s own doc comment for why
 * the two features live side by side rather than merged).
 *
 * Deliberately a plain checkbox grid rather than the original's own
 * tap-a-curved-tooth-diagram editor (`dental_clinics2/doctor/
 * periodontal_chart.php`'s `createToothSVG`, click-to-toggle on an actual
 * anatomical shape): this is a boolean present/absent mark per surface,
 * not a multi-status picker the way ToothOdontogram.vue's flower chart
 * is, so a checkbox conveys the same information with far less code and
 * no SVG-hit-testing to build. The *printed* chart still draws the
 * original's real curved tooth shapes (see the print Blade partial) —
 * this simplification is on-screen only.
 *
 * `modelValue` is `chart_data.dentalCharts` as already-decoded JSON:
 *   { visit2: { teeth: { '11': { extracted: bool, surfaces: {...} } } }, ... }
 */
import { computed, ref } from 'vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    visits: { type: Array, default: () => [] }, // [{ key, label }]
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const UPPER = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const LOWER = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];
const SURFACES = [
    { key: 'buccal', label: 'B' },
    { key: 'distal', label: 'D' },
    { key: 'lingual', label: 'L' },
    { key: 'mesial', label: 'M' },
];

const openVisit = ref(props.visits[0]?.key ?? null);
const toggleOpen = (key) => (openVisit.value = openVisit.value === key ? null : key);

const teethFor = (visitKey) => props.modelValue?.[visitKey]?.teeth ?? {};
const toothData = (visitKey, tooth) => teethFor(visitKey)[String(tooth)] ?? {};
const isExtracted = (visitKey, tooth) => toothData(visitKey, tooth).extracted === true;
const isMarked = (visitKey, tooth, surface) => toothData(visitKey, tooth).surfaces?.[surface] === true;

const setTooth = (visitKey, tooth, data) => {
    const next = { ...props.modelValue };
    const visit = { teeth: { ...(next[visitKey]?.teeth ?? {}) } };
    visit.teeth[String(tooth)] = data;
    next[visitKey] = visit;
    emit('update:modelValue', next);
};

const toggleExtracted = (visitKey, tooth) => {
    const data = { ...toothData(visitKey, tooth) };
    data.extracted = !data.extracted;
    setTooth(visitKey, tooth, data);
};

const toggleSurface = (visitKey, tooth, surface) => {
    const data = { ...toothData(visitKey, tooth) };
    data.surfaces = { ...(data.surfaces ?? {}), [surface]: !data.surfaces?.[surface] };
    setTooth(visitKey, tooth, data);
};

// Mirrors App\Support\PlaqueChart::visitData()'s own stats exactly — an
// extracted tooth's surfaces never count toward the total.
const stats = (visitKey) => {
    let marked = 0;
    let total = 0;
    for (const tooth of [...UPPER, ...LOWER]) {
        if (isExtracted(visitKey, tooth)) continue;
        total += 4;
        for (const s of SURFACES) {
            if (isMarked(visitKey, tooth, s.key)) marked++;
        }
    }
    return { marked, total, index: total > 0 ? ((marked / total) * 100).toFixed(1) : '0.0' };
};

const visitStats = computed(() => Object.fromEntries(props.visits.map((v) => [v.key, stats(v.key)])));
</script>

<template>
    <div class="space-y-3">
        <div v-for="visit in visits" :key="visit.key" class="overflow-hidden rounded-lg border border-gray-200">
            <button
                type="button"
                class="flex w-full items-center justify-between bg-gray-50 px-4 py-3 text-right hover:bg-gray-100"
                @click="toggleOpen(visit.key)"
            >
                <span class="font-medium text-gray-800">{{ visit.label }}</span>
                <span class="text-sm text-gray-500">
                    Plaque Index: {{ visitStats[visit.key].index }}% ({{ visitStats[visit.key].marked }} / {{ visitStats[visit.key].total }})
                </span>
            </button>

            <div v-if="openVisit === visit.key" class="space-y-4 p-4">
                <div v-for="(arch, archLabel) in { 'Upper Arch': UPPER, 'Lower Arch': LOWER }" :key="archLabel">
                    <div class="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-400">{{ archLabel }}</div>
                    <div class="space-y-1">
                        <div v-for="tooth in arch" :key="tooth" class="flex items-center gap-2 text-sm">
                            <span class="w-6 font-semibold text-gray-700">{{ tooth }}</span>
                            <label
                                v-for="surface in SURFACES"
                                :key="surface.key"
                                class="flex items-center gap-1 rounded border px-1.5 py-0.5 text-xs"
                                :class="!isExtracted(visit.key, tooth) && isMarked(visit.key, tooth, surface.key)
                                    ? 'border-green-500 bg-green-50 text-green-700'
                                    : 'border-gray-200 text-gray-500'"
                            >
                                <input
                                    type="checkbox"
                                    class="sr-only"
                                    :disabled="disabled || isExtracted(visit.key, tooth)"
                                    :checked="!isExtracted(visit.key, tooth) && isMarked(visit.key, tooth, surface.key)"
                                    @change="toggleSurface(visit.key, tooth, surface.key)"
                                />
                                {{ surface.label }}
                            </label>
                            <label
                                class="flex items-center gap-1 rounded border px-1.5 py-0.5 text-xs"
                                :class="isExtracted(visit.key, tooth) ? 'border-red-500 bg-red-50 text-red-700' : 'border-gray-200 text-gray-500'"
                            >
                                <input
                                    type="checkbox"
                                    class="sr-only"
                                    :disabled="disabled"
                                    :checked="isExtracted(visit.key, tooth)"
                                    @change="toggleExtracted(visit.key, tooth)"
                                />
                                Extracted
                            </label>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>
