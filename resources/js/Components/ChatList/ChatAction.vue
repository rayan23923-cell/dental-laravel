<script setup>
/**
 * A round icon-only action on a chat-list row (edit, delete, view…). Renders
 * an Inertia Link with `href`, a plain anchor with `external`, else a button.
 */
import Icon from '@/Components/Icon.vue';
import { Link } from '@inertiajs/vue3';

defineProps({
    icon: { type: String, required: true },
    label: { type: String, required: true },
    href: { type: String, default: null },
    external: { type: Boolean, default: false },
    danger: { type: Boolean, default: false },
});
defineEmits(['click']);
</script>

<template>
    <component
        :is="href ? (external ? 'a' : Link) : 'button'"
        :href="href ?? undefined"
        :target="external ? '_blank' : undefined"
        :type="href ? undefined : 'button'"
        :title="label"
        class="inline-flex h-9 w-9 items-center justify-center rounded-full transition"
        :class="danger ? 'text-gray-400 hover:bg-red-50 hover:text-red-600' : 'text-gray-500 hover:bg-gray-100 hover:text-indigo-600'"
        @click="$emit('click', $event)"
    >
        <Icon :name="icon" size="text-[20px]" :label="label" />
    </component>
</template>
