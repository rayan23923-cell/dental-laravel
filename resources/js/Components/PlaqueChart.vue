<script setup>
/**
 * Periodontal's "Plaque Index" per-visit dental chart — a completely
 * separate feature from PerioChart.vue's BOP/PPD/CAL tables despite
 * sharing the same `chart_data` column, under its own `dentalCharts`
 * top-level key (see `App\Support\PlaqueChart`'s own doc comment for why
 * the two features live side by side rather than merged).
 *
 * Interactive real-tooth-shape SVG (2026-08-31, by request) — the original
 * `dental_clinics2/doctor/periodontal_chart.php`'s `createToothForVisit()`
 * draws each tooth as its real curved outline clipped over 4 quadrant
 * triangles (buccal/distal/lingual/mesial), click-to-toggle per triangle.
 * This ports that exact shape/geometry (also shared with the print-side
 * Blade partial and Flutter's `periodontal_plaque_chart_svg.dart`, so all
 * three surfaces draw identical art), simplified from the original's
 * desktop-click-vs-mobile-modal-vs-Surface/Extract-mode-toggle into one
 * direct interaction that works the same on every device: tap a quadrant
 * triangle to mark/unmark it, tap the small "✕" chip under a tooth to
 * mark it extracted (extracted teeth stop accepting surface taps, mirroring
 * `App\Support\PlaqueChart::visitData()`'s own "extracted teeth never
 * count" rule).
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

// Tooth shapes and FDI→type maps — copied verbatim from
// App\Support\PlaqueChart::TOOTH_SHAPES/UPPER_TEETH/LOWER_TEETH and mirrored
// in periodontal_plaque_chart_svg.dart's kPlaqueToothShapes/kPlaqueUpperTeeth/
// kPlaqueLowerTeeth, so all three surfaces draw the identical outlines.
const TOOTH_SHAPES = {
    molar: 'M 5,10 Q 20,0 35,10 Q 40,20 35,35 Q 20,40 5,35 Q 0,20 5,10 Z',
    premolar: 'M 5,10 Q 20,2 35,10 Q 38,25 30,35 Q 20,38 10,35 Q 2,25 5,10 Z',
    canine: 'M 5,15 L 20,2 L 35,15 L 30,35 L 10,35 Z',
    incisorUpper: 'M 0,0 L 40,0 L 34,40 L 6,40 Z',
    incisorLower: 'M 5,2 L 35,2 L 32,38 L 8,38 Z',
};

const UPPER = [
    [18, 'molar'], [17, 'molar'], [16, 'molar'], [15, 'premolar'], [14, 'premolar'], [13, 'canine'],
    [12, 'incisorUpper'], [11, 'incisorUpper'], [21, 'incisorUpper'], [22, 'incisorUpper'],
    [23, 'canine'], [24, 'premolar'], [25, 'premolar'], [26, 'molar'], [27, 'molar'], [28, 'molar'],
];
const LOWER = [
    [48, 'molar'], [47, 'molar'], [46, 'molar'], [45, 'premolar'], [44, 'premolar'], [43, 'canine'],
    [42, 'incisorLower'], [41, 'incisorLower'], [31, 'incisorLower'], [32, 'incisorLower'],
    [33, 'canine'], [34, 'premolar'], [35, 'premolar'], [36, 'molar'], [37, 'molar'], [38, 'molar'],
];

// The 4 quadrant sectors, as triangles fanning out from the tooth's centre
// (20,20) in a 0–40 box — same points the print Blade partial's
// `$sectorPoints` and Flutter's `kPlaqueSectorPoints` use.
const SECTORS = [
    { key: 'buccal', label: 'Buccal', points: '0,0 40,0 20,20' },
    { key: 'distal', label: 'Distal', points: '40,0 40,40 20,20' },
    { key: 'lingual', label: 'Lingual', points: '40,40 0,40 20,20' },
    { key: 'mesial', label: 'Mesial', points: '0,40 0,0 20,20' },
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
    if (props.disabled) return;
    const data = { ...toothData(visitKey, tooth) };
    data.extracted = !data.extracted;
    setTooth(visitKey, tooth, data);
};

const toggleSurface = (visitKey, tooth, surface) => {
    if (props.disabled || isExtracted(visitKey, tooth)) return;
    const data = { ...toothData(visitKey, tooth) };
    data.surfaces = { ...(data.surfaces ?? {}), [surface]: !data.surfaces?.[surface] };
    setTooth(visitKey, tooth, data);
};

// Mirrors App\Support\PlaqueChart::visitData()'s own stats exactly — an
// extracted tooth's surfaces never count toward the total.
const stats = (visitKey) => {
    let marked = 0;
    let total = 0;
    for (const [tooth] of [...UPPER, ...LOWER]) {
        if (isExtracted(visitKey, tooth)) continue;
        total += 4;
        for (const s of SECTORS) {
            if (isMarked(visitKey, tooth, s.key)) marked++;
        }
    }
    return { marked, total, index: total > 0 ? ((marked / total) * 100).toFixed(1) : '0.0' };
};

const visitStats = computed(() => Object.fromEntries(props.visits.map((v) => [v.key, stats(v.key)])));

const sectorFill = (visitKey, tooth, surface) => (isMarked(visitKey, tooth, surface) ? '#4caf50' : '#ffffff');
const sectorOpacity = (visitKey, tooth, surface) => (isMarked(visitKey, tooth, surface) ? 0.7 : 0);
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
                <p class="text-xs text-gray-400">اضغط على أي جزء من السن لتحديد السطح المصاب باللويحة، واضغط ✕ لتحديد سن مخلوع.</p>

                <div v-for="(arch, archLabel) in { 'Upper Arch': UPPER, 'Lower Arch': LOWER }" :key="archLabel">
                    <div class="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-400">{{ archLabel }}</div>
                    <div class="overflow-x-auto" style="-webkit-overflow-scrolling: touch;">
                        <div class="flex w-max gap-1 pb-1">
                            <div v-for="[tooth, type] in arch" :key="tooth" class="flex shrink-0 flex-col items-center gap-0.5">
                                <svg width="34" height="34" viewBox="0 0 40 40" class="drop-shadow-sm" :style="{ opacity: isExtracted(visit.key, tooth) ? 0.4 : 1 }">
                                    <defs>
                                        <clipPath :id="`plaque-clip-${visit.key}-${tooth}`">
                                            <path :d="TOOTH_SHAPES[type]" />
                                        </clipPath>
                                    </defs>
                                    <g :clip-path="`url(#plaque-clip-${visit.key}-${tooth})`">
                                        <polygon
                                            v-for="sector in SECTORS"
                                            :key="sector.key"
                                            :points="sector.points"
                                            :fill="sectorFill(visit.key, tooth, sector.key)"
                                            :fill-opacity="sectorOpacity(visit.key, tooth, sector.key)"
                                            stroke="none"
                                            :class="{ 'cursor-pointer': !disabled && !isExtracted(visit.key, tooth) }"
                                            :title="sector.label"
                                            @click="toggleSurface(visit.key, tooth, sector.key)"
                                        />
                                    </g>
                                    <path :d="TOOTH_SHAPES[type]" fill="none" stroke="#333" stroke-width="1.5" vector-effect="non-scaling-stroke" />
                                    <path
                                        v-if="isExtracted(visit.key, tooth)"
                                        d="M 0,0 L 40,40 M 40,0 L 0,40"
                                        stroke="#dc2626"
                                        stroke-width="2.5"
                                        stroke-linecap="round"
                                    />
                                </svg>
                                <span class="text-[10px] leading-none text-gray-600">{{ tooth }}</span>
                                <button
                                    type="button"
                                    :disabled="disabled"
                                    class="rounded px-1 text-[9px] leading-tight"
                                    :class="isExtracted(visit.key, tooth) ? 'bg-red-100 text-red-700' : 'text-gray-400 hover:bg-gray-100'"
                                    @click="toggleExtracted(visit.key, tooth)"
                                >
                                    ✕
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</template>
