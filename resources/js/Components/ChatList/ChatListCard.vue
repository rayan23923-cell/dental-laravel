<script setup>
/**
 * The rounded white card a chat-list sits in — rows are divided by thin
 * lines, and `empty` shows a centred icon + text when there are none.
 */
import Icon from '@/Components/Icon.vue';

defineProps({
    empty: { type: Boolean, default: false },
    emptyText: { type: String, default: '' },
    emptyIcon: { type: String, default: 'inbox' },
});
</script>

<template>
    <div class="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-gray-100">
        <slot />
        <div v-if="empty" class="flex flex-col items-center gap-2 px-4 py-12 text-center text-sm text-gray-500">
            <Icon :name="emptyIcon" size="text-4xl" class="text-gray-300" />
            {{ emptyText }}
        </div>
        <slot name="footer" />
    </div>
</template>
