<script setup>
/** A label with an on/off switch, for settings lists. */
const model = defineModel({ type: Boolean, default: false });

defineProps({
    label: { type: String, required: true },
    hint: { type: String, default: '' },
});
</script>

<template>
    <label class="flex cursor-pointer items-center gap-3 py-2">
        <span class="min-w-0 flex-1">
            <span class="block text-sm text-gray-800">{{ label }}</span>
            <span v-if="hint" class="line-clamp-2 block text-xs text-gray-500" :title="hint">{{ hint }}</span>
        </span>
        <input v-model="model" type="checkbox" class="peer sr-only" />
        <span
            class="relative h-6 w-11 shrink-0 rounded-full transition"
            :class="model ? 'bg-indigo-600' : 'bg-gray-300'"
        >
            <span
                class="absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all"
                :class="model ? 'start-[1.375rem]' : 'start-0.5'"
            ></span>
        </span>
    </label>
</template>
