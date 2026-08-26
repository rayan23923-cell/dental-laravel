<script setup>
/**
 * Family History — port of oral_medicine.php's `$family_history_items`:
 * eight plain free-text fields, one per hereditary condition (confirmed
 * against the original and real imported data — no value/details toggle
 * here, unlike Past Medical History).
 */
const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const ITEMS = [
    ['obesity', 'Obesity'], ['sleep_apnea', 'Sleep apnea'], ['snoring', 'Snoring'],
    ['depression', 'Depression'], ['cancer', 'Cancer'], ['cardiovascular', 'Cardiovascular Diseases'],
    ['diabetes_hormonal', 'Diabetes and Hormonal Diseases'],
    ['other_hereditary', 'Other Hereditary or family related Diseases'],
];
</script>

<template>
    <div>
        <p class="mb-2 text-xs text-gray-500">Has any member of your family had disorders such as:</p>
        <div class="space-y-2">
            <div v-for="[key, label] in ITEMS" :key="key">
                <label class="mb-1 block text-xs font-medium text-gray-600">{{ label }}</label>
                <input
                    type="text"
                    :disabled="disabled"
                    :value="modelValue[key] ?? ''"
                    class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    @input="$emit('update:modelValue', { ...modelValue, [key]: $event.target.value })"
                />
            </div>
        </div>
    </div>
</template>
