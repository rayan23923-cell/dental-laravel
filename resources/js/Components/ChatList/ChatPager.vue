<script setup>
/** Laravel paginator links under a chat-list, shown only past one page. */
import { Link } from '@inertiajs/vue3';

defineProps({ links: { type: Array, default: () => [] } });
</script>

<template>
    <div v-if="links.length > 3" class="flex flex-wrap justify-center gap-1 border-t border-gray-100 p-3">
        <Link
            v-for="link in links"
            :key="link.label"
            :href="link.url ?? ''"
            v-html="link.label"
            class="rounded-full px-3 py-1 text-sm"
            :class="{
                'bg-indigo-600 text-white': link.active,
                'pointer-events-none text-gray-300': !link.url,
                'text-gray-700 hover:bg-gray-100': link.url && !link.active,
            }"
        />
    </div>
</template>
