<script setup>
/**
 * One collapsible row in a settings list (Telegram-style, 2026-10-14):
 * coloured icon, title, a one-line summary of the current values and a
 * chevron; tapping opens the fields underneath. Sits inside a ChatListCard.
 */
import Icon from '@/Components/Icon.vue';

const open = defineModel('open', { type: Boolean, default: false });

defineProps({
    icon: { type: String, required: true },
    tone: { type: String, default: 'bg-indigo-500' },
    title: { type: String, required: true },
    summary: { type: String, default: '' },
    hasError: { type: Boolean, default: false },
});
</script>

<template>
    <div class="border-b border-gray-100 last:border-b-0">
        <button
            type="button"
            class="flex w-full items-center gap-3 px-4 py-3 text-start transition hover:bg-gray-50"
            :aria-expanded="open"
            @click="open = !open"
        >
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-white" :class="tone">
                <Icon :name="icon" size="text-[20px]" />
            </span>
            <span class="min-w-0 flex-1">
                <span class="block text-sm font-semibold text-gray-800">{{ title }}</span>
                <span v-if="summary" class="block truncate text-xs text-gray-500">{{ summary }}</span>
            </span>
            <Icon v-if="hasError" name="error" class="text-red-500" />
            <Icon name="expand_more" class="text-gray-400 transition-transform duration-200" :class="open ? 'rotate-180' : ''" />
        </button>
        <div v-show="open" class="border-t border-gray-50 bg-gray-50/40 px-4 pb-5 pt-4">
            <slot />
        </div>
    </div>
</template>
