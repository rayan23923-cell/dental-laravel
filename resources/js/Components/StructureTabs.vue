<script setup>
import { Link } from '@inertiajs/vue3';

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
            Education Types
        </Link>
        <Link
            :href="route('stages.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'stages' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            Stages
        </Link>
        <Link
            :href="route('departments.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'departments' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            Departments
        </Link>
        <Link
            :href="route('academic-sessions.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'academic-sessions' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            Academic Sessions
        </Link>
        <Link
            :href="route('groups.index')"
            class="border-b-2 px-4 py-2 text-sm font-medium"
            :class="active === 'groups' ? 'border-indigo-500 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'"
        >
            Groups
        </Link>
    </div>
</template>
