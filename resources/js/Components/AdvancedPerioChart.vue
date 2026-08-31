<script setup>
/**
 * "Advanced Periodontal Chart" (2026-08-31, by request) — a 32-tooth,
 * 6-site-per-tooth periodontal charting grid, functionally modeled on
 * periodontalchart-online.com's own charting tool (same field set —
 * Mobility/Implant/Furcation/Bleeding on Probing/Plaque/Gingival Margin/
 * Probing Depth/Attachment Level — and the same "192 sites" denominator
 * for BOP%/Plaque Index%, i.e. 32 teeth × 2 zones × 3 sites, no tooth
 * ever excluded since this chart has no extraction/missing-tooth concept
 * of its own).
 *
 * The tooth-row artwork below is this app's OWN vector art — the same
 * curved molar/premolar/canine/incisor outlines already built for
 * `PlaqueChart.vue`/`App\Support\PlaqueChart::TOOTH_SHAPES`, reused here
 * rather than attempting to reproduce periodontalchart-online.com's own
 * detailed crown/root illustrations, which sidesteps any copyright concern
 * entirely (the layout concept — two arch rows, a horizontal gumline, a
 * metric grid above/below — is a generic charting convention used by many
 * such tools, not something any one of them owns). Decorative only, not
 * interactive: unlike the odontogram/Plaque Index charts, entry here
 * happens through the row cells below, not by tapping the artwork.
 *
 * `modelValue` is `chart_data.advancedChart` as already-decoded JSON:
 *   { teeth: { '18': { mobility, implant, furcation,
 *       buccal: { bop: [b,b,b], plaque: [b,b,b], gm: [n,n,n], pd: [n,n,n], al: [n,n,n] },
 *       lingual: { ...same shape... } }, ... } }
 * Sparse — only touched teeth get an entry, same convention as
 * `ToothOdontogram.vue`/`PlaqueChart.vue`.
 */
import { computed } from 'vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

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

// The 5 per-site metrics, in the order rendered outward-in from each arch's
// buccal row (upper) / lingual row (lower) — see the template for why the
// two arches render this list in opposite directions.
const SITE_ROWS = [
    { key: 'bop', label: 'Bleeding on Probing', kind: 'toggle' },
    { key: 'plaque', label: 'Plaque', kind: 'toggle' },
    { key: 'gm', label: 'Gingival Margin', kind: 'number', signed: true },
    { key: 'pd', label: 'Probing Depth', kind: 'number' },
    { key: 'al', label: 'Attachment Level', kind: 'number' },
];

// The 3 once-per-tooth metrics (not per site).
const SINGLE_ROWS = [
    { key: 'mobility', label: 'Mobility', kind: 'number', max: 3 },
    { key: 'implant', label: 'Implant', kind: 'toggle' },
    { key: 'furcation', label: 'Furcation', kind: 'number', max: 3 },
];

const teeth = computed(() => props.modelValue?.teeth ?? {});
const toothData = (tooth) => teeth.value[String(tooth)] ?? {};

const setTooth = (tooth, data) => {
    emit('update:modelValue', { teeth: { ...teeth.value, [String(tooth)]: data } });
};

const getSingle = (tooth, key) => {
    const value = toothData(tooth)[key];
    return value ?? (key === 'implant' ? false : '');
};

const setSingle = (tooth, key, value) => {
    if (props.disabled) return;
    setTooth(tooth, { ...toothData(tooth), [key]: value });
};

const getSite = (tooth, zone, metric, pos) => {
    const arr = toothData(tooth)[zone]?.[metric] ?? [];
    return arr[pos] ?? (metric === 'bop' || metric === 'plaque' ? false : '');
};

const setSite = (tooth, zone, metric, pos, value) => {
    if (props.disabled) return;
    const t = toothData(tooth);
    const z = { ...(t[zone] ?? {}) };
    const arr = [...(z[metric] ?? ['', '', ''])];
    arr[pos] = value;
    z[metric] = arr;
    setTooth(tooth, { ...t, [zone]: z });
};

const TOTAL_SITES = (UPPER.length + LOWER.length) * 2 * 3; // 32 teeth x 2 zones x 3 sites = 192

const stats = computed(() => {
    let bopMarked = 0;
    let plaqueMarked = 0;
    let pdSum = 0;
    let pdCount = 0;
    let alSum = 0;
    let alCount = 0;

    for (const [tooth] of [...UPPER, ...LOWER]) {
        for (const zone of ['buccal', 'lingual']) {
            for (let pos = 0; pos < 3; pos++) {
                if (getSite(tooth, zone, 'bop', pos) === true) bopMarked++;
                if (getSite(tooth, zone, 'plaque', pos) === true) plaqueMarked++;
                const pd = parseFloat(getSite(tooth, zone, 'pd', pos));
                if (!Number.isNaN(pd)) {
                    pdSum += pd;
                    pdCount++;
                }
                const al = parseFloat(getSite(tooth, zone, 'al', pos));
                if (!Number.isNaN(al)) {
                    alSum += al;
                    alCount++;
                }
            }
        }
    }

    return {
        avgPd: pdCount > 0 ? (pdSum / pdCount).toFixed(1) : '0.0',
        avgAl: alCount > 0 ? (alSum / alCount).toFixed(1) : '0.0',
        bopPct: ((bopMarked / TOTAL_SITES) * 100).toFixed(1),
        plaquePct: ((plaqueMarked / TOTAL_SITES) * 100).toFixed(1),
        bopMarked,
        plaqueMarked,
        totalSites: TOTAL_SITES,
    };
});

const archLabel = (isUpper, zone) => {
    if (zone === 'buccal') return 'Buccal';
    return isUpper ? 'Palatal' : 'Lingual';
};
</script>

<template>
    <div class="space-y-4">
        <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-1 rounded-md bg-gray-50 px-4 py-2 text-sm text-gray-700">
            <span>Avg. Probing Depth: <strong>{{ stats.avgPd }} mm</strong></span>
            <span>Avg. Attachment Level: <strong>{{ stats.avgAl }} mm</strong></span>
            <span>BOP: <strong>{{ stats.bopPct }}%</strong> ({{ stats.bopMarked }} / {{ stats.totalSites }})</span>
            <span>PI: <strong>{{ stats.plaquePct }}%</strong> ({{ stats.plaqueMarked }} / {{ stats.totalSites }})</span>
        </div>

        <div v-for="isUpper in [true, false]" :key="isUpper ? 'upper' : 'lower'" class="overflow-x-auto rounded-lg border border-gray-200" style="-webkit-overflow-scrolling: touch;">
            <table class="min-w-max border-collapse text-center text-[10px]">
                <tbody>
                    <!-- Single-per-tooth rows: above the arch for upper, below for lower — mirrors the reference tool's own "framing" without duplicating the same 3 rows on both sides of one arch. -->
                    <template v-if="isUpper">
                        <tr v-for="row in SINGLE_ROWS" :key="`single-${row.key}`">
                            <th class="whitespace-nowrap border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">{{ row.label }}</th>
                            <td v-for="[tooth] in UPPER" :key="tooth" class="border border-gray-300 p-0">
                                <button
                                    v-if="row.kind === 'toggle'"
                                    type="button"
                                    class="h-5 w-11"
                                    :class="getSingle(tooth, row.key) ? 'bg-indigo-500 text-white' : 'bg-white hover:bg-gray-100'"
                                    :disabled="disabled"
                                    @click="setSingle(tooth, row.key, !getSingle(tooth, row.key))"
                                >
                                    {{ getSingle(tooth, row.key) ? '✓' : '' }}
                                </button>
                                <input
                                    v-else
                                    type="text"
                                    inputmode="numeric"
                                    :maxlength="1"
                                    :disabled="disabled"
                                    class="h-5 w-11 border-0 p-0 text-center text-[10px] focus:ring-1 focus:ring-indigo-400"
                                    :value="getSingle(tooth, row.key)"
                                    @input="setSingle(tooth, row.key, $event.target.value)"
                                />
                            </td>
                        </tr>
                    </template>

                    <!-- Outer zone (buccal for both arches) for upper; inner zone (lingual/palatal) first for lower — matches the anatomical row order PerioChart.vue already established (the two tongue-facing rows sit adjacent to the arch boundary). -->
                    <template v-for="row in (isUpper ? SITE_ROWS : [...SITE_ROWS].reverse())" :key="`${isUpper ? 'buccal' : 'lingual'}-${row.key}`">
                        <tr>
                            <th class="whitespace-nowrap border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">
                                {{ archLabel(isUpper, isUpper ? 'buccal' : 'lingual') }} — {{ row.label }}
                            </th>
                            <template v-for="[tooth] in (isUpper ? UPPER : LOWER)" :key="tooth">
                                <td v-for="pos in [0, 1, 2]" :key="pos" class="border border-gray-300 p-0">
                                    <button
                                        v-if="row.kind === 'toggle'"
                                        type="button"
                                        class="h-5 w-5"
                                        :class="getSite(tooth, isUpper ? 'buccal' : 'lingual', row.key, pos) ? (row.key === 'bop' ? 'bg-red-500 text-white' : 'bg-yellow-400') : 'bg-white hover:bg-gray-100'"
                                        :disabled="disabled"
                                        @click="setSite(tooth, isUpper ? 'buccal' : 'lingual', row.key, pos, !getSite(tooth, isUpper ? 'buccal' : 'lingual', row.key, pos))"
                                    ></button>
                                    <input
                                        v-else
                                        type="text"
                                        inputmode="numeric"
                                        maxlength="3"
                                        :disabled="disabled"
                                        class="h-5 w-5 border-0 p-0 text-center text-[10px] focus:ring-1 focus:ring-indigo-400"
                                        :value="getSite(tooth, isUpper ? 'buccal' : 'lingual', row.key, pos)"
                                        @input="setSite(tooth, isUpper ? 'buccal' : 'lingual', row.key, pos, $event.target.value)"
                                    />
                                </td>
                            </template>
                        </tr>
                    </template>

                    <!-- Tooth numbers -->
                    <tr>
                        <th class="border border-gray-300 bg-gray-100"></th>
                        <td v-for="[tooth] in (isUpper ? UPPER : LOWER)" :key="tooth" colspan="3" class="border border-gray-400 bg-gray-100 px-1 py-0.5 font-semibold">
                            {{ tooth }}
                        </td>
                    </tr>

                    <!-- Decorative tooth-row artwork — see this component's own doc comment for why it's non-interactive and original artwork. -->
                    <tr>
                        <th class="border border-gray-300 bg-white"></th>
                        <td :colspan="(isUpper ? UPPER : LOWER).length * 3" class="border border-gray-300 bg-white p-1">
                            <svg :width="(isUpper ? UPPER : LOWER).length * 40" height="46" :viewBox="`0 0 ${(isUpper ? UPPER : LOWER).length * 40} 46`">
                                <line x1="0" y1="23" :x2="(isUpper ? UPPER : LOWER).length * 40" y2="23" stroke="#dc2626" stroke-width="1" stroke-dasharray="2,2" />
                                <g v-for="([tooth, type], idx) in (isUpper ? UPPER : LOWER)" :key="tooth" :transform="`translate(${idx * 40}, 3)`">
                                    <path :d="TOOTH_SHAPES[type]" fill="#f4f4f5" stroke="#9ca3af" stroke-width="1" />
                                </g>
                            </svg>
                        </td>
                    </tr>

                    <!-- Inner zone (lingual/palatal) for upper; outer zone (buccal) for lower. -->
                    <template v-for="row in (isUpper ? SITE_ROWS : [...SITE_ROWS].reverse())" :key="`${isUpper ? 'lingual' : 'buccal'}-${row.key}`">
                        <tr>
                            <th class="whitespace-nowrap border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">
                                {{ archLabel(isUpper, isUpper ? 'lingual' : 'buccal') }} — {{ row.label }}
                            </th>
                            <template v-for="[tooth] in (isUpper ? UPPER : LOWER)" :key="tooth">
                                <td v-for="pos in [0, 1, 2]" :key="pos" class="border border-gray-300 p-0">
                                    <button
                                        v-if="row.kind === 'toggle'"
                                        type="button"
                                        class="h-5 w-5"
                                        :class="getSite(tooth, isUpper ? 'lingual' : 'buccal', row.key, pos) ? (row.key === 'bop' ? 'bg-red-500 text-white' : 'bg-yellow-400') : 'bg-white hover:bg-gray-100'"
                                        :disabled="disabled"
                                        @click="setSite(tooth, isUpper ? 'lingual' : 'buccal', row.key, pos, !getSite(tooth, isUpper ? 'lingual' : 'buccal', row.key, pos))"
                                    ></button>
                                    <input
                                        v-else
                                        type="text"
                                        inputmode="numeric"
                                        maxlength="3"
                                        :disabled="disabled"
                                        class="h-5 w-5 border-0 p-0 text-center text-[10px] focus:ring-1 focus:ring-indigo-400"
                                        :value="getSite(tooth, isUpper ? 'lingual' : 'buccal', row.key, pos)"
                                        @input="setSite(tooth, isUpper ? 'lingual' : 'buccal', row.key, pos, $event.target.value)"
                                    />
                                </td>
                            </template>
                        </tr>
                    </template>

                    <template v-if="!isUpper">
                        <tr v-for="row in SINGLE_ROWS" :key="`single-${row.key}`">
                            <th class="whitespace-nowrap border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">{{ row.label }}</th>
                            <td v-for="[tooth] in LOWER" :key="tooth" class="border border-gray-300 p-0">
                                <button
                                    v-if="row.kind === 'toggle'"
                                    type="button"
                                    class="h-5 w-11"
                                    :class="getSingle(tooth, row.key) ? 'bg-indigo-500 text-white' : 'bg-white hover:bg-gray-100'"
                                    :disabled="disabled"
                                    @click="setSingle(tooth, row.key, !getSingle(tooth, row.key))"
                                >
                                    {{ getSingle(tooth, row.key) ? '✓' : '' }}
                                </button>
                                <input
                                    v-else
                                    type="text"
                                    inputmode="numeric"
                                    :maxlength="1"
                                    :disabled="disabled"
                                    class="h-5 w-11 border-0 p-0 text-center text-[10px] focus:ring-1 focus:ring-indigo-400"
                                    :value="getSingle(tooth, row.key)"
                                    @input="setSingle(tooth, row.key, $event.target.value)"
                                />
                            </td>
                        </tr>
                    </template>
                </tbody>
            </table>
        </div>

        <p class="text-xs text-gray-400">
            Bleeding on Probing / Plaque: click a site to toggle. Gingival Margin (mm, negative = recession) / Probing Depth (mm) / Attachment Level (mm): enter a value per site. Mobility (0–3) / Furcation (0–3): one value per tooth. Implant: click to toggle.
        </p>
    </div>
</template>
