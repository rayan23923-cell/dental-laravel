<script setup>
/**
 * "Yes/No + details if yes" checklist — port of the Past Medical History
 * grid in dental_clinics2/doctor/oral_medicine.php (`$pmh_categories`,
 * `pmh[key][value]`/`pmh[key][details]`). Each item stores
 * `{ value: 'yes'|'no', details: string }`; the details field only shows
 * once "Yes" is picked, matching the original's own show/hide behaviour
 * exactly (`style="display: <?= $value == 'yes' ? 'block' : 'none' ?>"`).
 */
const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    // [{ key, label }]
    items: { type: Array, required: true },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const itemOf = (key) => props.modelValue?.[key] ?? { value: 'no', details: '' };

const setValue = (key, value) => {
    emit('update:modelValue', { ...props.modelValue, [key]: { ...itemOf(key), value } });
};

const setDetails = (key, details) => {
    emit('update:modelValue', { ...props.modelValue, [key]: { ...itemOf(key), details } });
};
</script>

<template>
    <div class="space-y-3">
        <div v-for="item in items" :key="item.key" class="rounded-md border border-gray-200 p-3">
            <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="text-sm text-gray-700">{{ item.label }}</span>
                <div class="flex gap-3 text-sm">
                    <label class="flex items-center gap-1.5">
                        <input
                            type="radio"
                            :disabled="disabled"
                            :checked="itemOf(item.key).value === 'no'"
                            class="border-gray-300 text-indigo-600 focus:ring-indigo-500"
                            @change="setValue(item.key, 'no')"
                        />
                        No
                    </label>
                    <label class="flex items-center gap-1.5">
                        <input
                            type="radio"
                            :disabled="disabled"
                            :checked="itemOf(item.key).value === 'yes'"
                            class="border-gray-300 text-indigo-600 focus:ring-indigo-500"
                            @change="setValue(item.key, 'yes')"
                        />
                        Yes
                    </label>
                </div>
            </div>
            <input
                v-if="itemOf(item.key).value === 'yes'"
                type="text"
                :disabled="disabled"
                :value="itemOf(item.key).details"
                placeholder="Please specify..."
                class="mt-2 block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                @input="setDetails(item.key, $event.target.value)"
            />
        </div>
    </div>
</template>
