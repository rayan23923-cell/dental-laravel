<script setup>
/**
 * Profile header (Instagram/Telegram-style, 2026-10-14): a large round
 * photo with a camera button to change it, then the name, username and
 * chips (role, stage...). Emits `pick` with the chosen image file.
 */
import Icon from '@/Components/Icon.vue';

defineProps({
    photo: { type: String, default: null },
    name: { type: String, default: '' },
    subtitle: { type: String, default: '' },
    chips: { type: Array, default: () => [] },
    error: { type: String, default: '' },
});
const emit = defineEmits(['pick']);

const onFile = (event) => {
    const file = event.target.files[0];
    if (file) emit('pick', file);
    event.target.value = '';
};
</script>

<template>
    <div class="flex flex-col items-center rounded-2xl bg-white px-4 py-6 text-center shadow-sm ring-1 ring-gray-100">
        <label class="group relative cursor-pointer">
            <img v-if="photo" :src="photo" class="h-28 w-28 rounded-full object-cover ring-4 ring-indigo-100" />
            <span v-else class="flex h-28 w-28 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-fuchsia-500 text-white ring-4 ring-indigo-100">
                <Icon name="person" size="text-5xl" />
            </span>
            <span class="absolute bottom-1 end-1 flex h-9 w-9 items-center justify-center rounded-full bg-indigo-600 text-white shadow ring-2 ring-white transition group-hover:bg-indigo-700">
                <Icon name="photo_camera" size="text-[18px]" />
            </span>
            <input type="file" accept="image/*" class="sr-only" @change="onFile" />
        </label>
        <div class="mt-3 text-lg font-semibold text-gray-900">{{ name }}</div>
        <div v-if="subtitle" class="text-sm text-gray-500" dir="ltr">@{{ subtitle }}</div>
        <div v-if="chips.length" class="mt-2 flex flex-wrap justify-center gap-1.5">
            <span v-for="chip in chips" :key="chip" class="rounded-full bg-indigo-50 px-2.5 py-0.5 text-xs font-medium text-indigo-700">{{ chip }}</span>
        </div>
        <p v-if="error" class="mt-2 text-sm text-red-600">{{ error }}</p>
    </div>
</template>
