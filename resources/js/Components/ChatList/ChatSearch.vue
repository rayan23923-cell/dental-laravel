<script setup>
/** The rounded search pill from the permissions page. */
import Icon from '@/Components/Icon.vue';

const model = defineModel({ type: String, default: '' });
defineProps({ placeholder: { type: String, default: '' } });
defineEmits(['submit']);
</script>

<template>
    <div class="relative">
        <Icon name="search" class="pointer-events-none absolute inset-y-0 start-3 my-auto h-6 text-gray-400" />
        <input
            v-model="model"
            type="search"
            :placeholder="placeholder"
            class="block w-full rounded-full border-0 bg-white py-2.5 pe-4 ps-11 text-sm text-gray-900 shadow-sm ring-1 ring-gray-200 placeholder:text-gray-500 focus:ring-2 focus:ring-indigo-500"
            @keyup.enter="$emit('submit')"
        />
    </div>
</template>
