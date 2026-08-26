<script setup>
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import TextInput from '@/Components/TextInput.vue';

const props = defineProps({
    field: Object, // { key, label, type, required }
    modelValue: [String, Number, Boolean, null],
    error: String,
});

const emit = defineEmits(['update:modelValue']);
</script>

<template>
    <div>
        <InputLabel :for="field.key" :value="field.label + (field.required ? ' *' : '')" />

        <textarea
            v-if="field.type === 'textarea'"
            :id="field.key"
            :value="modelValue"
            rows="3"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            @input="emit('update:modelValue', $event.target.value)"
        ></textarea>

        <select
            v-else-if="field.type === 'boolean'"
            :id="field.key"
            :value="modelValue"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            @change="emit('update:modelValue', $event.target.value)"
        >
            <option value="">—</option>
            <option value="1">Yes</option>
            <option value="0">No</option>
        </select>

        <TextInput
            v-else
            :id="field.key"
            :type="field.type === 'date' ? 'date' : (field.type === 'number' ? 'number' : 'text')"
            :model-value="modelValue"
            class="mt-1 block w-full"
            @update:model-value="emit('update:modelValue', $event)"
        />

        <InputError class="mt-2" :message="error" />
    </div>
</template>
