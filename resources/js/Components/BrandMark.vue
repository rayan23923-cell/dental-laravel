<script setup>
/**
 * Brand mark — a molar drawn as flat vector geometry, matching the line-art
 * instrument icons on the dental-unit panel this UI is modelled on.
 *
 * Real SVG rather than an icon-font glyph because this is the one mark that
 * must scale to any size and take the theme's accent gradient; Icon.vue
 * (Material Symbols) stays the right tool for the hundreds of small UI
 * glyphs, which only ever need a single colour.
 *
 * The gradient id is made unique per instance — two of these on one page
 * (navbar + login card) with a shared id would let the first definition win
 * and silently recolour the second.
 */
import { computed, useId } from 'vue';

const props = defineProps({
    // Rendered box; the artwork scales with it.
    size: { type: [Number, String], default: 40 },
    // `gradient` paints with the theme accent; `mono` inherits currentColor.
    variant: { type: String, default: 'gradient' },
});

const uid = useId();
const gradientId = computed(() => `brand-grad-${uid}`);
const fill = computed(() => (props.variant === 'mono' ? 'currentColor' : `url(#${gradientId.value})`));
</script>

<template>
    <svg
        :width="size"
        :height="size"
        viewBox="0 0 48 48"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        role="img"
        aria-label="شعار العيادة"
    >
        <defs>
            <linearGradient :id="gradientId" x1="8" y1="4" x2="40" y2="44" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stop-color="rgb(var(--c-accent))" />
                <stop offset="100%" stop-color="rgb(var(--c-accent-2))" />
            </linearGradient>
        </defs>

        <!-- Rounded slab behind the tooth, echoing the panel's card corners. -->
        <rect
            v-if="variant === 'gradient'"
            x="2"
            y="2"
            width="44"
            height="44"
            rx="13"
            :fill="`url(#${gradientId})`"
            opacity="0.14"
        />

        <!-- Molar: two crown lobes meeting at a central fissure, tapering
             into two roots. Drawn as one path so the gradient runs unbroken. -->
        <path
            d="M24 10.4c-2.5-2.6-5.6-3.9-8.7-3.4-4.3.7-6.9 4.4-6.9 9.6 0 3.3.7 6.3 1.6 9.6.7 2.5 1.2 5 1.5 7.6l.6 5.2c.2 1.6 1.5 2.8 3.1 2.8 1.5 0 2.8-1.1 3.1-2.6l1.6-8.6c.3-1.7 1.8-2.9 3.5-2.9h1.6c1.7 0 3.2 1.2 3.5 2.9l1.6 8.6c.3 1.5 1.6 2.6 3.1 2.6 1.6 0 2.9-1.2 3.1-2.8l.6-5.2c.3-2.6.8-5.1 1.5-7.6.9-3.3 1.6-6.3 1.6-9.6 0-5.2-2.6-8.9-6.9-9.6-3.1-.5-6.2.8-8.7 3.4Z"
            :fill="fill"
        />

        <!-- Central fissure, cut in the page colour so it reads as a groove
             at every size rather than a hairline that disappears. -->
        <path
            d="M24 12.2v12"
            stroke="rgb(var(--c-bg))"
            stroke-width="2.4"
            stroke-linecap="round"
            opacity="0.85"
        />
    </svg>
</template>
