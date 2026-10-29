<script setup>
/**
 * Telegram's loading spinner (by request, 2026-10-29: "اعمل لودنك انميشن
 * مشابه لتليجرام"), matching the app's `TgSpinner`: the ring turns once
 * per 2s while its arc stretches from a dot to 280° and back every
 * second, the tail chasing the head. `pathLength="360"` lets the dash
 * keyframes speak in degrees; four rise/fall cycles carry the arc a whole
 * number of turns forward, so the loop has no seam. Takes the text colour.
 */
defineProps({
    size: { type: [Number, String], default: 20 },
    stroke: { type: [Number, String], default: 2.5 },
});
</script>

<template>
    <svg
        class="tg-spinner inline-block shrink-0"
        :width="size"
        :height="size"
        viewBox="0 0 24 24"
        fill="none"
        role="status"
        aria-label="جارٍ التحميل"
    >
        <circle
            class="tg-spinner-arc"
            cx="12"
            cy="12"
            :r="12 - (stroke * 12) / size"
            pathLength="360"
            stroke="currentColor"
            :stroke-width="stroke * 24 / size"
            stroke-linecap="round"
        />
    </svg>
</template>

<style scoped>
.tg-spinner {
    animation: tg-spin 2s linear infinite;
}
.tg-spinner-arc {
    transform: rotate(-90deg);
    transform-origin: center;
    animation: tg-arc 4s ease-in-out infinite;
}
@keyframes tg-spin {
    to { transform: rotate(360deg); }
}
@keyframes tg-arc {
    0% { stroke-dasharray: 10 350; stroke-dashoffset: 0; }
    12.5% { stroke-dasharray: 280 80; stroke-dashoffset: 0; }
    25% { stroke-dasharray: 10 350; stroke-dashoffset: -270; }
    37.5% { stroke-dasharray: 280 80; stroke-dashoffset: -270; }
    50% { stroke-dasharray: 10 350; stroke-dashoffset: -540; }
    62.5% { stroke-dasharray: 280 80; stroke-dashoffset: -540; }
    75% { stroke-dasharray: 10 350; stroke-dashoffset: -810; }
    87.5% { stroke-dasharray: 280 80; stroke-dashoffset: -810; }
    100% { stroke-dasharray: 10 350; stroke-dashoffset: -1080; }
}
</style>
