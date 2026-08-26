<script setup>
/**
 * Material Symbols icon.
 *
 * Replaces the emoji that were standing in for icons across the app.
 * Emoji rendered inconsistently between platforms (different glyphs on
 * Windows/Android/iOS, some missing entirely and showing as tofu), and
 * couldn't be recoloured or sized with the surrounding text.
 *
 * The font is self-hosted (see resources/css/app.css) so it works with no
 * internet connection.
 *
 * Icons are decorative by default and hidden from assistive technology —
 * pass a `label` when the icon is the only thing conveying meaning (an
 * icon-only button), which turns it into a labelled image instead.
 */
defineProps({
    // Material Symbols ligature name, e.g. "delete", "print", "search".
    name: { type: String, required: true },
    // Tailwind text-size class controls the glyph size.
    size: { type: String, default: 'text-[20px]' },
    label: { type: String, default: null },
    filled: { type: Boolean, default: false },
});
</script>

<template>
    <span
        class="material-symbols-outlined align-middle"
        :class="[size, filled ? 'is-filled' : '']"
        :aria-hidden="label ? undefined : 'true'"
        :role="label ? 'img' : undefined"
        :aria-label="label || undefined"
    >{{ name }}</span>
</template>

<style scoped>
.is-filled {
    font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
}
</style>
