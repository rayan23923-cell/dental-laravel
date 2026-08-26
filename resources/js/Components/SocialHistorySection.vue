<script setup>
/**
 * Social History — port of oral_medicine.php: marital status (radio),
 * occupation (text), tobacco use (radio) + other tobacco forms
 * (checkboxes), packs/day, quit-when, years, alcohol (radio), caffeine
 * (checkboxes), exercise (radio). Option values and the two checkbox lists
 * (`tobacco_other[]`, `caffeine[]`) confirmed against the original's own
 * markup and real imported data — the earlier port had neither checkbox
 * list at all and used different radio values than the real ones.
 */
const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const set = (key, value) => emit('update:modelValue', { ...props.modelValue, [key]: value });

const toggleListItem = (key, value) => {
    const list = props.modelValue?.[key] ?? [];
    set(key, list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);
};

const isChecked = (key, value) => (props.modelValue?.[key] ?? []).includes(value);
</script>

<template>
    <div class="space-y-4">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
                <label class="mb-1 block text-xs font-medium text-gray-600">Marital Status</label>
                <div class="flex flex-wrap gap-3 text-sm">
                    <label v-for="opt in ['single', 'married', 'divorced']" :key="opt" class="flex items-center gap-1.5 capitalize">
                        <input type="radio" :disabled="disabled" :checked="modelValue.marital_status === opt" class="border-gray-300 text-indigo-600" @change="set('marital_status', opt)" />{{ opt }}
                    </label>
                </div>
            </div>
            <div>
                <label class="mb-1 block text-xs font-medium text-gray-600">Patient's Occupation &amp; Employer</label>
                <input type="text" :disabled="disabled" :value="modelValue.occupation ?? ''" class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="set('occupation', $event.target.value)" />
            </div>
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
                <label class="mb-1 block text-xs font-medium text-gray-600">Tobacco Use (Cigarettes)</label>
                <div class="flex flex-wrap gap-3 text-sm">
                    <label v-for="[val, lbl] in [['never', 'Never Smoked'], ['current', 'Current Smoker'], ['quit', 'Quit']]" :key="val" class="flex items-center gap-1.5">
                        <input type="radio" :disabled="disabled" :checked="modelValue.tobacco_cigarettes === val" class="border-gray-300 text-indigo-600" @change="set('tobacco_cigarettes', val)" />{{ lbl }}
                    </label>
                </div>
            </div>
            <div>
                <label class="mb-1 block text-xs font-medium text-gray-600">Other tobacco</label>
                <div class="flex flex-wrap gap-3 text-sm">
                    <label v-for="val in ['pipe', 'cigar', 'snuff', 'chew']" :key="val" class="flex items-center gap-1.5 capitalize">
                        <input type="checkbox" :disabled="disabled" :checked="isChecked('tobacco_other', val)" class="rounded border-gray-300 text-indigo-600" @change="toggleListItem('tobacco_other', val)" />{{ val }}
                    </label>
                </div>
            </div>
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div v-for="[key, label] in [['packs_per_day', 'No. of packs per day'], ['quit_when', 'When did you quit?'], ['years', 'No. of years']]" :key="key">
                <label class="mb-1 block text-xs font-medium text-gray-600">{{ label }}</label>
                <input type="text" :disabled="disabled" :value="modelValue[key] ?? ''" class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500" @input="set(key, $event.target.value)" />
            </div>
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
                <label class="mb-1 block text-xs font-medium text-gray-600">Alcohol Use</label>
                <div class="flex gap-4 text-sm">
                    <label class="flex items-center gap-1.5"><input type="radio" :disabled="disabled" :checked="(modelValue.alcohol ?? 'no') === 'no'" class="border-gray-300 text-indigo-600" @change="set('alcohol', 'no')" />No</label>
                    <label class="flex items-center gap-1.5"><input type="radio" :disabled="disabled" :checked="modelValue.alcohol === 'yes'" class="border-gray-300 text-indigo-600" @change="set('alcohol', 'yes')" />Yes</label>
                </div>
            </div>
            <div>
                <label class="mb-1 block text-xs font-medium text-gray-600">Caffeine Intake</label>
                <div class="flex flex-wrap gap-3 text-sm">
                    <label v-for="val in ['none', 'coffee', 'tea', 'soda']" :key="val" class="flex items-center gap-1.5 capitalize">
                        <input type="checkbox" :disabled="disabled" :checked="isChecked('caffeine', val)" class="rounded border-gray-300 text-indigo-600" @change="toggleListItem('caffeine', val)" />{{ val }}
                    </label>
                </div>
            </div>
        </div>

        <div>
            <label class="mb-1 block text-xs font-medium text-gray-600">Regular workout exercise</label>
            <div class="flex gap-4 text-sm">
                <label class="flex items-center gap-1.5"><input type="radio" :disabled="disabled" :checked="modelValue.exercise === 'yes'" class="border-gray-300 text-indigo-600" @change="set('exercise', 'yes')" />Yes</label>
                <label class="flex items-center gap-1.5"><input type="radio" :disabled="disabled" :checked="modelValue.exercise === 'no'" class="border-gray-300 text-indigo-600" @change="set('exercise', 'no')" />No</label>
            </div>
        </div>
    </div>
</template>
