<script setup>
/** The round gradient "+" in a page header, as on the permissions page. */
import Icon from '@/Components/Icon.vue';
import { Link } from '@inertiajs/vue3';

defineProps({
    label: { type: String, required: true },
    href: { type: String, default: null },
    icon: { type: String, default: 'add' },
    secondary: { type: Boolean, default: false },
});
defineEmits(['click']);
</script>

<template>
    <component
        :is="href ? Link : 'button'"
        :href="href ?? undefined"
        :type="href ? undefined : 'button'"
        :title="label"
        class="inline-flex h-10 w-10 items-center justify-center rounded-full"
        :class="secondary ? 'bg-gray-100 text-gray-700 hover:bg-gray-200' : 'bg-gradient-to-br from-indigo-500 to-pink-500 text-white shadow hover:opacity-90'"
        @click="$emit('click', $event)"
    >
        <Icon :name="icon" :label="label" />
    </component>
</template>
