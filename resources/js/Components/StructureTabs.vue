<script setup>
import { Link } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
defineProps({
    active: String,
});
</script>

<template>
    <div class="flex gap-1 border-b border-gray-200">
        <Link
            :href="route('education-types.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'education-types' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.educationTypes') }}
        </Link>
        <Link
            :href="route('stages.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'stages' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.stages') }}
        </Link>
        <Link
            :href="route('departments.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'departments' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.departments') }}
        </Link>
        <Link
            :href="route('academic-sessions.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'academic-sessions' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.academicSessions') }}
        </Link>
        <Link
            :href="route('groups.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'groups' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.groups') }}
        </Link>
        <Link
            :href="route('clinic-chairs.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'clinic-chairs' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            {{ t('structureTabs.chairMap') }}
        </Link>
    </div>
</template>
