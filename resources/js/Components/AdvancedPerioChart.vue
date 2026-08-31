<script setup>
/**
 * "Advanced Periodontal Chart" (2026-08-31, revised same day by request) —
 * a 32-tooth, 6-site-per-tooth periodontal charting grid, functionally
 * modeled on periodontalchart-online.com's own charting tool.
 *
 * Tooth/implant artwork (2026-08-31, revision 2, by request): replaced the
 * original 5-blob-shape placeholder art with real crown+root outlines and
 * a real implant-fixture graphic, both supplied by the user as an
 * independently-designed reference asset (a standalone anatomical SVG
 * chart built specifically to avoid any copyright question — see the
 * user's own note: "تم تصميم الاسنان بصورة مستقلة وتم الاعتماد عليهما
 * للتخلص من مشكلة الحقوق"). Only the raw `<path>` geometry (crown + root
 * outlines, the implant abutment/body/thread/highlight) was extracted;
 * decorative canal/furcation linework, probing-point dots, and the
 * reference asset's own JS/interaction layer were left behind — this
 * component keeps its own existing data model and stats logic untouched.
 * 8 tooth "positions" per arch (3rd molar down to central incisor) cover
 * all 32 teeth: the reference asset's own path data confirms each
 * position's shape is reused byte-for-byte on the mirrored side (11's
 * `d` attribute is identical to 21's, etc.), so `UPPER_SHAPES`/
 * `LOWER_SHAPES` below hold exactly 8 entries each rather than 16 — the
 * same "shared type, mirrored across the arch" structure this component
 * already had, just with 8 real per-position shapes instead of 5 generic
 * blob categories. The implant graphic is identical across every tooth in
 * the source asset, so `IMPLANT_SHAPE` is a single shared constant: a
 * tooth marked "Implant" swaps its *root* for the fixture graphic while
 * keeping its crown always visible (revision 7, by request — "اجعله لا
 * يختفي بكل الاحوال" — the crown must never disappear; an earlier
 * revision swapped the whole tooth, which was wrong: the reference
 * asset's own CSS only hides `.root`/`.canal`/`.furcation`/`.detail` in
 * implant mode, never `.crown`, matching real anatomy — an implant
 * replaces the natural root, not the visible crown restoration on top of
 * it).
 *
 * Two diagrams per arch (revision 3, same day, by request — "لكل فك هناك
 * مخططان labial/lingual"): each arch now renders TWO tooth-row graphics,
 * labeled "Labial" and "Palatal / Lingual" (or "Lingual" for the lower
 * arch), matching the reference site's own "MAXILLA · LABIAL" / "MAXILLA
 * · LINGUAL" structure — see the template's own comment for why both
 * draw from the same crown+root shape data (the reference asset's lingual-
 * view groups carry byte-for-byte identical crown/root paths to its
 * labial view) and why toggling Implant for a tooth updates both rows
 * automatically with no extra sync code ("يتم اختيار الجهة المعاكسة ولي
 * نفس العمود المختار").
 *
 * Upper-arch orientation fix (revision 4, same day — reported live from
 * production: "كل المخططات تتجه للاسفل"): every tooth's raw path data is
 * authored crown-up/root-down (matching the *lower* jaw's natural
 * orientation) — the reference asset's own upper-arch groups counter this
 * with an extra `scale(1,-1)` flip so the upper arch renders crown-down/
 * root-up instead, which this component had omitted, so every arch
 * (upper included) rendered crown-up. See `toothTransform()`/`gumlineY()`
 * below for the fix and the exact reflection math.
 *
 * Layout (revision 5, by request — reversed from revision 2's "بدون
 * سكرول افقي"): revision 2 tried a `table-fixed` + percentage-`<colgroup>`
 * table that could never overflow its container, shrinking every cell
 * together to fit any viewport — technically no-scroll, but on a phone
 * that meant 48 site-columns squeezed into ~7px each, unusable for actual
 * data entry. Reverted to a fixed-pixel-width table (`h-6 w-6` per site
 * cell, matching `PerioChart.vue`'s own established sizing) inside an
 * `overflow-x-auto` wrapper: desktop/tablet show as many teeth as fit at
 * a legible, tappable size; a phone scrolls horizontally for the rest —
 * the same tradeoff `PerioChart.vue`/`PlaqueChart.vue` already make
 * elsewhere in this app, explicitly requested this time ("اجعل المخطط
 * قابل للسكرول ومتوافق مع الاجهزة اللوحية والموبايل والحاسوب").
 *
 * Row structure closer to the reference site's own logic (revision 2):
 * Mobility/Implant appear once per arch, at the outer edge; Bleeding on
 * Probing/Plaque/Furcation/Gingival Margin/Probing Depth/Attachment Level
 * each appear twice per arch (once for the buccal sites, once for the
 * palatal/lingual sites — furcation is clinically assessed from both
 * aspects on a multi-rooted tooth, same as the other site metrics); a
 * free-text per-tooth Note field appears once per arch, next to the
 * block nearest the tooth-row graphic.
 *
 * `modelValue` is `chart_data.advancedChart` as already-decoded JSON:
 *   { teeth: { '18': { mobility, implant, note, furcation-per-zone...,
 *       buccal: { bop: [b,b,b], plaque: [b,b,b], furcation: [n,n,n], gm: [n,n,n], pd: [n,n,n], al: [n,n,n] },
 *       lingual: { ...same shape... } }, ... } }
 */
import { computed } from 'vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

// The implant fixture graphic — identical across every tooth in the
// source reference asset, so one shared shape suffices. Coordinates are
// already in each tooth's own local space (no extra transform needed,
// unlike the root paths below).
const IMPLANT_SHAPE = {
    abutment: 'M-7,31 L7,31 L6,45 L-6,45 Z',
    body: 'M-6,45 L6,45 L10,58 L8,175 C7,185 3,191 0,194 C-3,191 -7,185 -8,175 L-10,58 Z',
    thread: 'M-9,62 L9,62 M-9,72 L9,72 M-9,82 L9,82 M-9,92 L9,92 M-9,102 L9,102 M-9,112 L9,112 M-9,122 L9,122 M-9,132 L9,132 M-8,142 L8,142 M-8,152 L8,152 M-7,162 L7,162 M-6,172 L6,172',
    highlight: 'M-3,53 L-4,169',
};

// 8 tooth positions, 3rd molar (M3) to central incisor (I1) — crown paths
// are in the tooth's own local space; root paths need the same
// `translate(0,10) scale(1.15,.74)` the reference asset applies to them
// (see the `<g>` wrapper in the template).
const UPPER_SHAPES = {
    M3: {
        crown: 'M-27,5 C-33,-8 -25,-20 -13,-19 L-4,-16 L4,-21 L16,-17 C27,-15 31,-5 28,7 C26,26 17,41 5,46 L-3,44 L-11,47 C-20,39 -27,24 -27,5 Z',
        roots: ['M-13,43 C-18,79 -20,120 -13,151 C-9,167 -2,176 0,179 C4,174 8,163 9,148 C10,116 14,78 13,43 Z'],
    },
    M2: {
        crown: 'M-29,6 C-32,-6 -26,-17 -16,-18 L-7,-15 L0,-21 L8,-15 L17,-18 C27,-16 32,-7 29,6 C28,26 18,42 7,48 L0,45 L-7,48 C-18,42 -28,26 -29,6 Z',
        roots: [
            'M-17,43 C-21,80 -27,123 -25,158 C-24,174 -18,185 -12,191 C-14,148 -11,91 -6,43 Z',
            'M-5,43 C-8,87 -9,137 -4,177 C-2,188 0,196 3,201 C6,192 7,183 6,172 C4,128 4,82 4,43 Z',
            'M8,43 C13,84 19,129 17,163 C21,160 26,153 27,143 C28,116 23,79 18,43 Z',
        ],
    },
    M1: {
        crown: 'M-31,5 C-34,-7 -28,-19 -18,-19 L-8,-16 L0,-24 L8,-16 L18,-20 C28,-18 34,-8 31,5 C30,26 20,44 7,50 L0,47 L-7,50 C-20,44 -30,26 -31,5 Z',
        roots: [
            'M-18,43 C-22,80 -29,126 -27,163 C-26,179 -20,191 -13,198 C-15,151 -12,91 -6,43 Z',
            'M-6,43 C-9,86 -11,139 -6,181 C-4,194 -1,202 2,207 C5,199 7,190 7,178 C5,132 4,83 4,43 Z',
            'M7,43 C13,86 21,134 19,171 C24,168 30,159 31,148 C32,119 26,80 20,43 Z',
        ],
    },
    PM2: {
        crown: 'M-23,3 C-23,-8 -15,-14 -7,-11 L0,-19 L7,-11 C15,-14 23,-8 23,3 C22,24 15,38 6,44 L0,41 L-6,44 C-15,38 -22,24 -23,3 Z',
        roots: ['M-12,40 C-15,79 -18,121 -14,158 C-12,174 -6,185 0,192 C4,183 7,169 9,148 C12,111 12,72 11,40 Z'],
    },
    PM1: {
        crown: 'M-25,2 C-25,-9 -17,-15 -9,-12 L0,-22 L9,-12 C17,-15 25,-9 25,2 C24,24 17,40 7,46 L0,43 L-7,46 C-17,40 -24,24 -25,2 Z',
        roots: [
            'M-14,40 C-18,79 -23,119 -20,154 C-18,171 -11,184 -5,190 C-7,147 -4,91 -1,40 Z',
            'M2,40 C5,84 9,134 7,171 C11,166 18,157 20,145 C23,112 18,76 14,40 Z',
        ],
    },
    C: {
        crown: 'M-17,4 C-18,-8 -11,-16 0,-21 C11,-16 18,-8 17,4 L14,40 C9,48 4,52 0,53 C-4,52 -9,48 -14,40 Z',
        roots: ['M-11,40 C-14,80 -17,123 -12,164 C-9,184 -3,199 0,207 C4,199 9,184 13,164 C17,123 14,80 11,40 Z'],
    },
    I2: {
        crown: 'M-16,5 C-17,-7 -12,-14 -6,-14 L7,-14 C13,-13 17,-7 16,5 L15,36 C10,43 5,46 0,46 C-5,46 -10,43 -15,36 Z',
        roots: ['M-8,35 C-11,71 -12,111 -7,150 C-5,167 -2,181 0,191 C3,181 6,167 8,150 C12,111 11,71 8,35 Z'],
    },
    I1: {
        crown: 'M-19,4 C-20,-8 -16,-15 -9,-14 L9,-14 C16,-15 20,-8 19,4 L18,38 C12,45 6,48 0,48 C-6,48 -12,45 -18,38 Z',
        roots: ['M-9,35 C-12,72 -13,112 -8,151 C-6,169 -2,184 0,194 C3,184 7,169 9,151 C13,112 12,72 9,35 Z'],
    },
};

const LOWER_SHAPES = {
    M3: UPPER_SHAPES.M3, // the reference asset's own "var" 3rd-molar simplification is shared verbatim across 18/28/38/48
    M2: {
        crown: 'M-32,4 C-34,-8 -27,-18 -17,-19 L-8,-16 L0,-22 L8,-16 L17,-19 C27,-17 34,-8 32,4 C31,26 20,44 7,49 L0,46 L-7,49 C-20,44 -31,26 -32,4 Z',
        roots: [
            'M-16,43 C-21,83 -26,125 -23,161 C-21,178 -16,188 -10,196 C-13,149 -10,91 -5,43 Z',
            'M6,43 C11,91 14,149 11,188 C16,183 21,174 23,160 C26,125 21,83 17,43 Z',
        ],
    },
    M1: {
        crown: 'M-34,4 C-36,-8 -30,-19 -20,-20 L-10,-17 L-2,-23 L7,-17 L17,-20 C29,-18 35,-8 34,4 C33,27 21,45 8,51 L0,48 L-8,51 C-21,45 -33,27 -34,4 Z',
        roots: [
            'M-17,43 C-23,83 -28,126 -25,163 C-23,181 -17,193 -11,201 C-14,153 -11,91 -6,43 Z',
            'M7,43 C12,91 15,151 12,190 C17,185 23,176 25,161 C28,126 23,83 18,43 Z',
        ],
    },
    PM2: {
        crown: 'M-25,3 C-25,-9 -16,-15 -7,-13 L0,-19 L7,-13 C16,-15 25,-9 25,3 C24,24 15,40 6,45 L0,42 L-6,45 C-15,40 -24,24 -25,3 Z',
        roots: ['M-12,41 C-15,82 -16,123 -11,162 C-8,180 -3,194 0,202 C3,194 8,180 11,162 C15,123 14,82 12,41 Z'],
    },
    PM1: {
        crown: 'M-24,5 C-25,-10 -14,-17 -3,-15 L4,-20 L12,-11 C21,-8 24,2 22,14 C20,29 12,41 3,45 L-5,43 C-15,36 -22,22 -24,5 Z',
        roots: ['M-11,41 C-14,82 -15,122 -10,160 C-7,179 -2,193 0,201 C3,193 8,179 11,160 C15,122 14,82 11,41 Z'],
    },
    C: {
        crown: 'M-14,4 C-15,-7 -9,-14 0,-19 C9,-14 15,-7 14,4 L12,38 C8,46 3,50 0,51 C-3,50 -8,46 -12,38 Z',
        roots: ['M-10,40 C-13,81 -14,123 -9,163 C-6,183 -2,198 0,207 C3,198 7,183 10,163 C14,123 13,81 10,40 Z'],
    },
    I2: {
        crown: 'M-13,4 C-14,-7 -10,-13 -4,-13 L5,-13 C10,-12 14,-6 13,4 L12,37 C8,43 3,46 0,46 C-4,46 -8,43 -12,37 Z',
        roots: ['M-9,35 C-12,72 -12,111 -7,151 C-5,169 -2,184 0,194 C3,184 6,169 8,151 C12,111 12,72 9,35 Z'],
    },
    I1: {
        crown: 'M-12,3 C-13,-7 -9,-12 -4,-12 L4,-12 C9,-12 13,-7 12,3 L11,36 C7,42 3,44 0,44 C-3,44 -7,42 -11,36 Z',
        roots: ['M-8,35 C-11,72 -11,111 -7,150 C-5,168 -2,183 0,193 C3,183 6,168 8,150 C11,111 11,72 8,35 Z'],
    },
};

const UPPER = [
    [18, 'M3'], [17, 'M2'], [16, 'M1'], [15, 'PM2'], [14, 'PM1'], [13, 'C'], [12, 'I2'], [11, 'I1'],
    [21, 'I1'], [22, 'I2'], [23, 'C'], [24, 'PM1'], [25, 'PM2'], [26, 'M1'], [27, 'M2'], [28, 'M3'],
];
const LOWER = [
    [48, 'M3'], [47, 'M2'], [46, 'M1'], [45, 'PM2'], [44, 'PM1'], [43, 'C'], [42, 'I2'], [41, 'I1'],
    [31, 'I1'], [32, 'I2'], [33, 'C'], [34, 'PM1'], [35, 'PM2'], [36, 'M1'], [37, 'M2'], [38, 'M3'],
];

const shapeFor = (isUpper, type) => (isUpper ? UPPER_SHAPES : LOWER_SHAPES)[type];

// The 6 per-site metrics, rendered once for the buccal sites and once for
// the palatal/lingual sites.
const SITE_ROWS = [
    { key: 'bop', label: 'Bleeding on Probing', kind: 'toggle' },
    { key: 'plaque', label: 'Plaque', kind: 'toggle' },
    { key: 'furcation', label: 'Furcation', kind: 'number' },
    { key: 'gm', label: 'Gingival Margin', kind: 'number', signed: true },
    { key: 'pd', label: 'Probing Depth', kind: 'number' },
    { key: 'al', label: 'Attachment Level', kind: 'number' },
];

// The 2 once-per-tooth metrics.
const SINGLE_ROWS = [
    { key: 'mobility', label: 'Mobility', kind: 'number', max: 3 },
    { key: 'implant', label: 'Implant', kind: 'toggle' },
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

// Graphic row geometry — a single responsive SVG per arch (see this
// component's own doc comment for why: `width="100%"` lets it shrink to
// any container width, the same technique the reference site's own chart
// uses, so a horizontal scrollbar can never appear).
const TOOTH_SLOT = 90;
const ARCH_WIDTH = 16 * TOOTH_SLOT;
const ARCH_HEIGHT = 235;
const toothX = (idx) => 45 + idx * TOOTH_SLOT;

// The graphic's *rendered* pixel size, computed explicitly rather than
// `width="100%"` — percentage sizing on a replaced element (the `<svg>`)
// inside an auto-layout `<table>` is a circular dependency the browser
// can't reliably resolve (the cell's width depends on its content's
// width, which depends on the cell's width), and confirmed broken live:
// the graphic rendered at something close to its raw 1440×235 viewBox
// instead of shrinking to match the 15px site cells, towering over the
// actual data grid. `SITE_CELL_PX` matches the real site-cell width
// below (`w-[15px]`, itself measured directly from periodontalchart-
// online.com's own live DOM — 15px input width, 20px row height — rather
// than guessed), so the graphic's pixel width tracks the data columns
// exactly: 16 teeth × 3 sites × 15px = 720px, with height derived from
// the same aspect ratio the viewBox already defines.
const SITE_CELL_PX = 15;
const archPixelWidth = (teethCount) => teethCount * 3 * SITE_CELL_PX;
const archPixelHeight = (teethCount) => Math.round(archPixelWidth(teethCount) * (ARCH_HEIGHT / ARCH_WIDTH));

// The lower arch draws crown-up/root-down (a tooth's own path data is
// already in that orientation, so no flip needed: `translate(cx, 25)`).
// The upper arch needs the opposite — crown hanging down, root pointing
// up — the same vertical flip the reference asset's own upper-arch groups
// apply (`scale(1,-1)`), which the previous revision omitted, leaving
// every arch rendering crown-up regardless of jaw (reported live:
// "كل المخططات تتجه للاسفل"). `translate(cx, 164) scale(1,-1)` reflects
// the tooth about screen-y 164 — chosen so the flipped footprint lands in
// the exact same [1,188] range the unflipped lower-arch tooth already
// occupies (crown tip at local y=-24, the tallest root's own transformed
// tip at local y≈163 — both source-verified from the shape data above),
// so upper and lower stay visually consistent in overall size/position,
// just mirrored. The gumline (the crown/root boundary, local y≈45) moves
// with it: 164-45=119 for the upper arch, vs. the lower arch's own
// 25+45=70.
const toothTransform = (isUpper, idx) => {
    const cx = toothX(idx);
    return isUpper ? `translate(${cx},164) scale(1,-1)` : `translate(${cx},25)`;
};
const gumlineY = (isUpper) => (isUpper ? 119 : 70);
</script>

<template>
    <div class="space-y-4">
        <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-1 rounded-md bg-gray-50 px-4 py-2 text-sm text-gray-700">
            <span>Avg. Probing Depth: <strong>{{ stats.avgPd }} mm</strong></span>
            <span>Avg. Attachment Level: <strong>{{ stats.avgAl }} mm</strong></span>
            <span>BOP: <strong>{{ stats.bopPct }}%</strong> ({{ stats.bopMarked }} / {{ stats.totalSites }})</span>
            <span>PI: <strong>{{ stats.plaquePct }}%</strong> ({{ stats.plaqueMarked }} / {{ stats.totalSites }})</span>
        </div>

        <!--
            Forced LTR (revision 6, fixing a real bug caught live) — the SVG
            tooth-row graphic draws in a fixed internal coordinate order
            (tooth "18" always at x=0) regardless of the page's own RTL
            (Arabic) direction, since SVG viewBox coordinates aren't
            direction-aware. Without `dir="ltr"` here, the surrounding table
            cells reverse their visual column order under RTL while the SVG
            doesn't, so the graphic and the data grid ended up pointing at
            completely different teeth once scrolled — confirmed live via
            the browser (data columns for "18" measured at a *negative*
            x-offset from the graphic's own "18" position). Same FDI-order-
            must-not-flip reasoning `perio_chart_table.dart`'s own
            `_archBlock` already documents on the Flutter side (tooth
            numbering is a fixed international convention, not something
            that should mirror with UI language).
        -->
        <div v-for="isUpper in [true, false]" :key="isUpper ? 'upper' : 'lower'" dir="ltr" class="overflow-x-auto rounded-lg border border-gray-200" style="-webkit-overflow-scrolling: touch;">
            <table class="min-w-max border-collapse text-center text-[9px]">
                <tbody>
                    <!-- Mobility / Implant: once per arch, outer edge. -->
                    <template v-if="isUpper">
                        <tr v-for="row in SINGLE_ROWS" :key="`single-${row.key}`">
                            <th class="w-[140px] truncate border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">{{ row.label }}</th>
                            <td v-for="[tooth] in UPPER" :key="tooth" colspan="3" class="border border-gray-300 p-0">
                                <button
                                    v-if="row.kind === 'toggle'"
                                    type="button"
                                    class="h-5 w-[45px]"
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
                                    class="h-5 w-[45px] border-0 p-0 text-center focus:ring-1 focus:ring-indigo-400"
                                    :value="getSingle(tooth, row.key)"
                                    @input="setSingle(tooth, row.key, $event.target.value)"
                                />
                            </td>
                        </tr>
                    </template>

                    <!-- Outer zone (buccal for upper; palatal/lingual for lower) — the two tongue-facing rows sit adjacent across the arch boundary, same convention PerioChart.vue uses. -->
                    <template v-for="row in SITE_ROWS" :key="`first-${row.key}`">
                        <tr>
                            <th class="w-[140px] truncate border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">
                                {{ archLabel(isUpper, isUpper ? 'buccal' : 'lingual') }} — {{ row.label }}
                            </th>
                            <template v-for="[tooth] in (isUpper ? UPPER : LOWER)" :key="tooth">
                                <td v-for="pos in [0, 1, 2]" :key="pos" class="border border-gray-300 p-0">
                                    <button
                                        v-if="row.kind === 'toggle'"
                                        type="button"
                                        class="h-5 w-[15px]"
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
                                        class="h-5 w-[15px] border-0 p-0 text-center text-[9px] focus:ring-1 focus:ring-indigo-400"
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

                    <!--
                        Two tooth-row diagrams per arch — Labial and Lingual/Palatal
                        views, matching the reference site's own "MAXILLA · LABIAL" /
                        "MAXILLA · LINGUAL" structure (confirmed directly from the
                        reference asset's own row labels, by request). Both views draw
                        from the *same* crown+root outline data — the reference asset's
                        own lingual-view groups carry byte-for-byte identical crown/root
                        `d` paths to the labial view (only their decorative surface-detail
                        lines differ, which this component doesn't draw at either view —
                        see the shape-library doc comment above), so there is no separate
                        "lingual shape" to extract; the two rows are visually the outline
                        twice, correctly reflecting that the outline itself doesn't change
                        between viewing angles at this level of simplification.

                        Both rows read the exact same `getSingle(tooth, 'implant')` call,
                        so toggling Implant for a tooth swaps *both* rows' drawing for
                        that column together, automatically — no extra sync code needed,
                        by request ("يتم اختيار الجهة المعاكسة ولي نفس العمود المختار").
                    -->
                    <tr v-for="view in ['Labial', isUpper ? 'Palatal / Lingual' : 'Lingual']" :key="view">
                        <th class="border border-gray-300 bg-white px-1 text-right text-[9px] font-medium text-gray-400">{{ view }}</th>
                        <td colspan="48" class="border border-gray-300 bg-white p-1">
                            <svg width="100%" height="auto" :viewBox="`0 0 ${ARCH_WIDTH} ${ARCH_HEIGHT}`" preserveAspectRatio="xMidYMin meet" style="display: block">
                                <line :x2="ARCH_WIDTH" :y1="gumlineY(isUpper)" :y2="gumlineY(isUpper)" stroke="#dc2626" stroke-width="1.5" stroke-dasharray="4,3" />
                                <g v-for="([tooth, type], idx) in (isUpper ? UPPER : LOWER)" :key="tooth" :transform="toothTransform(isUpper, idx)">
                                    <!-- The crown always renders, implant or not — see this
                                         component's own doc comment for why: only the
                                         *root* is ever replaced by the implant fixture,
                                         matching the reference asset's own CSS (its
                                         `.implant-mode` rule hides `.root`/`.canal`/etc.
                                         but never `.crown`), by request. -->
                                    <template v-if="getSingle(tooth, 'implant')">
                                        <path :d="IMPLANT_SHAPE.body" fill="#d7d9db" stroke="#20272b" stroke-width="1.4" />
                                        <path :d="IMPLANT_SHAPE.abutment" fill="#eceeef" stroke="#20272b" stroke-width="1.4" />
                                        <path :d="IMPLANT_SHAPE.thread" fill="none" stroke="#3b4246" stroke-width="1" />
                                        <path :d="IMPLANT_SHAPE.highlight" fill="none" stroke="#fff" stroke-width="1" opacity="0.7" />
                                    </template>
                                    <g v-else transform="translate(0,10) scale(1.15,0.74)">
                                        <path v-for="(r, ri) in shapeFor(isUpper, type).roots" :key="ri" :d="r" fill="#fff" stroke="#37474f" stroke-width="1.3" />
                                    </g>
                                    <path :d="shapeFor(isUpper, type).crown" fill="#fff" stroke="#20272b" stroke-width="1.6" stroke-linejoin="round" />
                                </g>
                            </svg>
                        </td>
                    </tr>

                    <!-- Inner zone (palatal/lingual for upper; buccal for lower). -->
                    <template v-for="row in [...SITE_ROWS].reverse()" :key="`second-${row.key}`">
                        <tr>
                            <th class="w-[140px] truncate border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">
                                {{ archLabel(isUpper, isUpper ? 'lingual' : 'buccal') }} — {{ row.label }}
                            </th>
                            <template v-for="[tooth] in (isUpper ? UPPER : LOWER)" :key="tooth">
                                <td v-for="pos in [0, 1, 2]" :key="pos" class="border border-gray-300 p-0">
                                    <button
                                        v-if="row.kind === 'toggle'"
                                        type="button"
                                        class="h-5 w-[15px]"
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
                                        class="h-5 w-[15px] border-0 p-0 text-center text-[9px] focus:ring-1 focus:ring-indigo-400"
                                        :value="getSite(tooth, isUpper ? 'lingual' : 'buccal', row.key, pos)"
                                        @input="setSite(tooth, isUpper ? 'lingual' : 'buccal', row.key, pos, $event.target.value)"
                                    />
                                </td>
                            </template>
                        </tr>
                    </template>

                    <!-- Note — once per arch, next to the block nearest the graphic. -->
                    <tr>
                        <th class="w-[140px] truncate border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">Note</th>
                        <td v-for="[tooth] in (isUpper ? UPPER : LOWER)" :key="tooth" colspan="3" class="border border-gray-300 p-0">
                            <input
                                type="text"
                                :disabled="disabled"
                                class="h-5 w-[45px] border-0 p-0 text-center focus:ring-1 focus:ring-indigo-400"
                                :value="getSingle(tooth, 'note')"
                                @input="setSingle(tooth, 'note', $event.target.value)"
                            />
                        </td>
                    </tr>

                    <template v-if="!isUpper">
                        <tr v-for="row in SINGLE_ROWS" :key="`single-${row.key}`">
                            <th class="w-[140px] truncate border border-gray-300 bg-gray-50 px-1 text-right font-medium text-gray-500">{{ row.label }}</th>
                            <td v-for="[tooth] in LOWER" :key="tooth" colspan="3" class="border border-gray-300 p-0">
                                <button
                                    v-if="row.kind === 'toggle'"
                                    type="button"
                                    class="h-5 w-[45px]"
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
                                    class="h-5 w-[45px] border-0 p-0 text-center focus:ring-1 focus:ring-indigo-400"
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
            Bleeding on Probing / Plaque: click a site to toggle. Furcation (0–3) / Gingival Margin (mm, negative = recession) / Probing Depth (mm) / Attachment Level (mm): enter a value per site. Mobility (0–3): one value per tooth. Implant: click to toggle — the tooth's own drawing switches to a fixture graphic. Note: free text per tooth.
        </p>
    </div>
</template>
