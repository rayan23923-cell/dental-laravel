<script setup>
/**
 * The full "History of the Complaint" block from oral_medicine.php: the
 * 28-item symptom checklist (SymptomsChecklist.vue) plus the seven
 * open-ended questions that follow it in the original, all posted under
 * the same `history_of_complaint[...]` column. Kept as one component bound
 * to the whole column (a plain text column, no Eloquent cast — see
 * App\Models\OralMedicineChart::casts()) rather than split across the
 * generic grouped-subkey mechanism the simpler JSON columns use, since a
 * couple of its keys (`symptoms`, `symptom_details`) aren't scalars.
 */
import SymptomsChecklist from '@/Components/SymptomsChecklist.vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const set = (key, value) => emit('update:modelValue', { ...props.modelValue, [key]: value });

const QUESTIONS = [
    ['when_first_occurred', 'When did the pain or condition first occur?', 'text'],
    ['believed_cause', 'What do you believe is the cause of the pain or condition?', 'textarea'],
    ['accident', 'Did you have any accident?', 'textarea'],
    ['makes_worse', 'Is there anything that makes your pain or discomfort worse?', 'textarea'],
    ['relieves', 'Is there anything that relieves your pain or discomfort?', 'textarea'],
    ['other_info', 'What other information is important regarding the pain or condition?', 'textarea'],
];
</script>

<template>
    <div class="space-y-4">
        <p class="text-xs text-gray-500">
            Do you have history of the followings associated with your CC.; please mark the applied ones:
        </p>
        <SymptomsChecklist
            :model-value="{ symptoms: modelValue.symptoms ?? [], symptom_details: modelValue.symptom_details ?? {} }"
            :disabled="disabled"
            @update:model-value="(v) => { set('symptoms', v.symptoms); set('symptom_details', v.symptom_details); }"
        />

        <div class="space-y-3 border-t border-gray-100 pt-4">
            <div v-for="[key, label, kind] in QUESTIONS" :key="key">
                <label class="mb-1 block text-xs font-medium text-gray-600">{{ label }}</label>
                <textarea
                    v-if="kind === 'textarea'"
                    :disabled="disabled"
                    :value="modelValue[key] ?? ''"
                    rows="2"
                    class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    @input="set(key, $event.target.value)"
                ></textarea>
                <input
                    v-else
                    type="text"
                    :disabled="disabled"
                    :value="modelValue[key] ?? ''"
                    class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    @input="set(key, $event.target.value)"
                />
            </div>

            <div>
                <label class="mb-1 block text-xs font-medium text-gray-600">
                    Pain scale (0–10, 0=No pain, 10=Worst pain imaginable)
                </label>
                <input
                    type="number" min="0" max="10" step="0.5"
                    :disabled="disabled"
                    :value="modelValue.pain_scale ?? ''"
                    class="block w-40 rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    @input="set('pain_scale', $event.target.value)"
                />
            </div>
        </div>
    </div>
</template>
