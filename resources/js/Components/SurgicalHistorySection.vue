<script setup>
/**
 * "History of Surgical Operations or Treatments" — port of oral_medicine.php.
 * `extra_oral`/`intra_oral` are plain "yes"/"no" strings (not the
 * value+details pattern PMH uses — confirmed against real imported data),
 * radio-selected; the rest are free text.
 */
const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const set = (key, value) => emit('update:modelValue', { ...props.modelValue, [key]: value });
</script>

<template>
    <div class="space-y-4">
        <div v-for="[key, label] in [['extra_oral', 'Do you have history of Extra-oral operations'], ['intra_oral', 'Do you have history of Intra-oral operations']]" :key="key">
            <label class="mb-1 block text-xs font-medium text-gray-600">{{ label }}</label>
            <div class="flex gap-4 text-sm">
                <label class="flex items-center gap-1.5">
                    <input type="radio" :disabled="disabled" :checked="(modelValue[key] ?? 'no') === 'no'" class="border-gray-300 text-indigo-600" @change="set(key, 'no')" />No
                </label>
                <label class="flex items-center gap-1.5">
                    <input type="radio" :disabled="disabled" :checked="modelValue[key] === 'yes'" class="border-gray-300 text-indigo-600" @change="set(key, 'yes')" />Yes
                </label>
            </div>
        </div>

        <div v-for="[key, label] in [['treatment_relevant', 'Do you have treatment relevant to the chief complaint?'], ['operations', 'What are the operations?'], ['when', 'When were they?']]" :key="key">
            <label class="mb-1 block text-xs font-medium text-gray-600">{{ label }}</label>
            <textarea
                :disabled="disabled"
                :value="modelValue[key] ?? ''"
                rows="2"
                class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                @input="set(key, $event.target.value)"
            ></textarea>
        </div>
    </div>
</template>
