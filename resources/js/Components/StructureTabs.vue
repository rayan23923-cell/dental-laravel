<script setup>
import { Link } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
defineProps({
    active: String,
});
</script>

<template>
    <!-- Scrolls sideways on narrow (phone) screens instead of wrapping or
         pushing the page wider than the viewport. -->
    <div class="-mx-4 flex gap-1 overflow-x-auto overscroll-x-contain border-b border-gray-200 px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
        <Link
            :href="route('education-types.index')"
            class="shrink-0 whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'education-types' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.educationTypes') }}
        </Link>
        <Link
            :href="route('stages.index')"
            class="shrink-0 whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'stages' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.stages') }}
        </Link>
        <Link
            :href="route('departments.index')"
            class="shrink-0 whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'departments' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.departments') }}
        </Link>
        <Link
            :href="route('academic-sessions.index')"
            class="shrink-0 whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'academic-sessions' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.academicSessions') }}
        </Link>
        <Link
            v-if="$page.props.groupsEnabled !== false"
            :href="route('groups.index')"
            class="shrink-0 whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'groups' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.groups') }}
        </Link>
        <!-- The clinic chair map tab is hidden (2026-10-12, by request). -->
    </div>
</template>
