<script setup>
/**
 * A rotating gradient ring — Instagram's own "story ring" look, reused as
 * a loading indicator (by request, 2026-09-01: "عدل loading animation عند
 * تسجيل الدخول واجعلها متوافقة مع instagram loading"). Replaces the plain
 * single-colour spinning Material icon on the login button.
 *
 * Same 5-stop gradient as `ig-gradient` (tailwind.config.js) and the
 * Flutter app's `InstagramColors.gradient`/`InstagramSpinner` — a loading
 * spinner is the same kind of small, recognisable accent moment
 * `BrandMark.vue`'s own gradient badge already is, not a full-UI repaint,
 * so it fits this app's established "gradient = accent only" rule rather
 * than breaking it. `conic-gradient` (rather than a copy of the
 * `linear-gradient` `ig-gradient` uses) is what lets the gradient wrap a
 * full circle instead of running corner-to-corner; the ring shape itself
 * comes from masking out the disc's centre, since CSS has no native
 * "gradient stroke" for a plain element.
 */
defineProps({
    size: { type: [Number, String], default: 20 },
});
</script>

<template>
    <span
        class="ig-spinner inline-block shrink-0 animate-spin rounded-full"
        :style="{ width: `${size}px`, height: `${size}px` }"
        role="status"
        aria-label="جارٍ التحميل"
    ></span>
</template>

<style scoped>
.ig-spinner {
    background: conic-gradient(from 0deg, #feda75, #fa7e1e, #d62976, #962fbf, #4f5bd5, #feda75);
    -webkit-mask: radial-gradient(farthest-side, transparent calc(100% - 2.5px), #000 calc(100% - 2.5px));
    mask: radial-gradient(farthest-side, transparent calc(100% - 2.5px), #000 calc(100% - 2.5px));
}
</style>
