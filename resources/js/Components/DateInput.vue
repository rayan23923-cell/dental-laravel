<script setup>
// A date field shown as 15/10/2026 (2026-10-15, by request). The browser's
// own date text garbled in Arabic on iPhone ("152026/10/"), so the native
// input sits invisibly on top and only opens the picker; the value stays
// yyyy-mm-dd.
const props = defineProps({
    modelValue: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
    required: { type: Boolean, default: false },
    id: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue', 'change']);

const display = (value) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value || '');
    return m ? `${m[3]}/${m[2]}/${m[1]}` : 'dd/mm/yyyy';
};

const onChange = (e) => {
    emit('update:modelValue', e.target.value);
    emit('change', e.target.value);
};
</script>

<template>
    <label
        class="relative block w-full min-w-0 rounded-md border border-gray-300 px-3 py-2 text-center text-sm shadow-sm focus-within:border-indigo-500 focus-within:ring-1 focus-within:ring-indigo-500"
        :class="props.disabled ? 'bg-gray-50 text-gray-500' : 'bg-white'"
    >
        <span dir="ltr" :class="props.modelValue ? '' : 'text-gray-400'">{{ display(props.modelValue) }}</span>
        <input
            :id="props.id"
            :value="props.modelValue"
            type="date"
            :disabled="props.disabled"
            :required="props.required"
            class="absolute inset-0 h-full w-full cursor-pointer opacity-0 disabled:cursor-default"
            @change="onChange"
        />
    </label>
</template>
