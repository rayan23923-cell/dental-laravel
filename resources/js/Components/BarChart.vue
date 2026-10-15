<script setup>
/**
 * Single-series bar chart in plain SVG (2026-10-12) — no chart library,
 * so it works in the offline package. One hue (the value is magnitude),
 * thin bars with a rounded top on a zero baseline, a recessive grid with
 * three labelled ticks, and a hover tooltip per bar. Only every n-th
 * category label is drawn when there are many bars so they never collide.
 */
import { computed, ref } from 'vue';

const props = defineProps({
    // [{ key, label, total }]
    data: { type: Array, required: true },
    format: { type: Function, default: (v) => Number(v).toLocaleString() },
    // Axis ticks use a compact form (250K, 2M) so they fit the gutter.
    tickFormat: { type: Function, default: (v) => new Intl.NumberFormat('en', { notation: 'compact' }).format(v) },
    height: { type: Number, default: 180 },
    ariaLabel: { type: String, default: '' },
});

const W = 600;
const pad = { top: 12, right: 8, bottom: 24, left: 44 };
const plotW = W - pad.left - pad.right;
const plotH = computed(() => props.height - pad.top - pad.bottom);

const niceMax = (v) => {
    if (v <= 0) return 1;
    const mag = 10 ** Math.floor(Math.log10(v));
    const n = v / mag;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * mag;
};
const max = computed(() => niceMax(Math.max(0, ...props.data.map((d) => d.total))));
const ticks = computed(() => [0, max.value / 2, max.value]);
const y = (v) => pad.top + plotH.value - (v / max.value) * plotH.value;

const step = computed(() => plotW / Math.max(1, props.data.length));
const barW = computed(() => Math.max(2, Math.min(28, step.value * 0.6)));
const labelEvery = computed(() => Math.ceil(props.data.length / 12));

const bars = computed(() =>
    props.data.map((d, i) => {
        const x = pad.left + i * step.value + (step.value - barW.value) / 2;
        const top = y(d.total);
        const h = Math.max(0, pad.top + plotH.value - top);
        return { ...d, i, x, top, h };
    }),
);

// Bars with a rounded top (4px) anchored square to the baseline.
const barPath = (b) => {
    if (b.h <= 0) return '';
    const r = Math.min(4, barW.value / 2, b.h);
    const x0 = b.x, x1 = b.x + barW.value, base = b.top + b.h;
    return `M${x0},${base} V${b.top + r} Q${x0},${b.top} ${x0 + r},${b.top} H${x1 - r} Q${x1},${b.top} ${x1},${b.top + r} V${base} Z`;
};

const hover = ref(null);
</script>

<template>
    <div class="relative" @mouseleave="hover = null">
        <svg :viewBox="`0 0 ${W} ${height}`" class="block h-auto w-full" role="img" :aria-label="ariaLabel">
            <g>
                <line
                    v-for="tk in ticks"
                    :key="tk"
                    :x1="pad.left"
                    :x2="W - pad.right"
                    :y1="y(tk)"
                    :y2="y(tk)"
                    class="stroke-gray-200"
                    stroke-width="1"
                />
                <text
                    v-for="tk in ticks"
                    :key="'t' + tk"
                    :x="pad.left - 6"
                    :y="y(tk) + 4"
                    text-anchor="end"
                    class="fill-gray-500"
                    font-size="11"
                    direction="ltr"
                >{{ tickFormat(tk) }}</text>
            </g>
            <g>
                <path v-for="b in bars" :key="b.key" :d="barPath(b)" :class="hover?.key === b.key ? 'fill-indigo-700' : 'fill-indigo-500'" />
                <!-- Hit targets span the full slot height, bigger than the bar. -->
                <rect
                    v-for="b in bars"
                    :key="'h' + b.key"
                    :x="pad.left + b.i * step"
                    :y="pad.top"
                    :width="step"
                    :height="plotH"
                    fill="transparent"
                    @mouseenter="hover = b"
                    @focus="hover = b"
                    tabindex="0"
                />
            </g>
            <g>
                <text
                    v-for="b in bars.filter((b) => b.i % labelEvery === 0)"
                    :key="'l' + b.key"
                    :x="b.x + barW / 2"
                    :y="height - 6"
                    text-anchor="middle"
                    class="fill-gray-500"
                    font-size="11"
                    direction="ltr"
                >{{ b.label }}</text>
            </g>
        </svg>
        <div
            v-if="hover"
            class="pointer-events-none absolute -translate-x-1/2 whitespace-nowrap rounded-md bg-gray-900 px-2 py-1 text-xs text-white shadow"
            :style="{ left: `${((hover.x + barW / 2) / W) * 100}%`, top: '0' }"
        >
            <span dir="ltr">{{ hover.key }}</span> · <span>{{ format(hover.total) }}</span>
        </div>
    </div>
</template>
