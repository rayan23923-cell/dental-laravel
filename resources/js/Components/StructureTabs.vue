<script setup>
import { Link } from '@inertiajs/vue3';
import { useStructureLinks } from '@/Composables/useStructureLinks';

// The same items, in the same order, as the "البيانات الأساسية" menu group.
// `active` is kept for the pages that still pass it; the current route
// decides which tab is highlighted.
defineProps({
    active: String,
});

const links = useStructureLinks();
</script>

<template>
    <!-- Scrolls sideways on narrow (phone) screens instead of wrapping or
         pushing the page wider than the viewport. -->
    <div v-if="links.length" class="-mx-4 flex gap-1 overflow-x-auto overscroll-x-contain border-b border-gray-200 px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
        <Link
            v-for="link in links"
            :key="link.key"
            :href="link.href"
            class="shrink-0 whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium"
            :class="link.active ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ link.label }}
        </Link>
    </div>
</template>
