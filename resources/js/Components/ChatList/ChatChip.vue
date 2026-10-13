<script setup>
import Icon from '@/Components/Icon.vue';
import { tone as toneOf } from './tones';

defineProps({
    icon: { type: String, default: null },
    tone: { type: String, default: 'gray' },
});
</script>

<template>
    <span class="inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium" :class="toneOf(tone).chip">
        <Icon v-if="icon" :name="icon" size="text-[14px]" />
        <slot />
    </span>
</template>
