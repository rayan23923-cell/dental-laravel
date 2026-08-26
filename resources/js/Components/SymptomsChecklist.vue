<script setup>
/**
 * The 28-item "history of the complaint" symptom checklist — port of
 * oral_medicine.php's `$symptoms` array (`history_of_complaint[symptoms][]`
 * + `history_of_complaint[symptom_details][key][right/left/other]`).
 * `hasSides` items reveal a right/left detail pair when checked; the
 * special `other` item reveals a free-text field instead — both match the
 * original's exact show/hide behaviour (`toggleSymptomDetails()`).
 */
const props = defineProps({
    // { symptoms: string[], symptom_details: { key: {right,left,other} } }
    modelValue: { type: Object, default: () => ({ symptoms: [], symptom_details: {} }) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const SYMPTOMS = [
    ['headache', 'Headache', false], ['migraines', 'Migraines', true],
    ['facial_pain', 'Facial pain', true], ['neck_pain', 'Neck pain', false],
    ['jaw_pain', 'Jaw pain', true], ['jaw_clicking', 'Jaw clicking', true],
    ['nocturnal_teeth_grinding', 'Nocturnal teeth grinding', false],
    ['frequent_biting_cheek', 'Frequent biting of cheek', true],
    ['pain_when_chewing', 'Pain when chewing', true],
    ['fatigue_facial_muscles', 'Fatigue of facial muscles', true],
    ['limited_mouth_opening', 'Limited mouth opening', false],
    ['jaw_locking', 'Jaw locking', false], ['dislocation_jaw', 'Dislocation of jaw', false],
    ['ringing_ears', 'Ringing in the ears', true], ['dizziness', 'Dizziness', false],
    ['morning_head_pain', 'Morning head pain', false], ['frequent_snoring', 'Frequent Snoring', false],
    ['dry_mouth', 'Dry mouth', false], ['burning_tongue', 'Burning tongue', false],
    ['pain_swallowing', 'Pain on swallowing', false], ['sinusitis', 'Sinusitis', false],
    ['tooth_pain', 'Tooth Pain', false], ['past_broken_teeth', 'Past history of broken teeth', false],
    ['facial_asymmetry_swelling', 'Facial asymmetry or swelling', false], ['numbness', 'Numbness', false],
    ['eye_pain', 'Eye pain', false], ['throat_pain', 'Throat pain', false], ['other', 'Other', false],
].map(([key, label, hasSides]) => ({ key, label, hasSides }));

const symptoms = () => props.modelValue?.symptoms ?? [];
const details = (key) => props.modelValue?.symptom_details?.[key] ?? { right: '', left: '', other: '' };
const isChecked = (key) => symptoms().includes(key);

const toggle = (key) => {
    const list = isChecked(key) ? symptoms().filter((s) => s !== key) : [...symptoms(), key];
    emit('update:modelValue', { ...props.modelValue, symptoms: list });
};

const setDetail = (key, field, value) => {
    emit('update:modelValue', {
        ...props.modelValue,
        symptom_details: { ...(props.modelValue?.symptom_details ?? {}), [key]: { ...details(key), [field]: value } },
    });
};
</script>

<template>
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <div v-for="s in SYMPTOMS" :key="s.key" class="rounded-md border border-gray-200 p-2">
            <label class="flex items-center gap-2 text-sm text-gray-700">
                <input
                    type="checkbox"
                    :disabled="disabled"
                    :checked="isChecked(s.key)"
                    class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                    @change="toggle(s.key)"
                />
                {{ s.label }}
            </label>

            <div v-if="isChecked(s.key) && s.hasSides" class="mt-1.5 flex gap-1.5">
                <input
                    type="text" :disabled="disabled" :value="details(s.key).right" placeholder="R"
                    class="w-16 rounded border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    @input="setDetail(s.key, 'right', $event.target.value)"
                />
                <input
                    type="text" :disabled="disabled" :value="details(s.key).left" placeholder="L"
                    class="w-16 rounded border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    @input="setDetail(s.key, 'left', $event.target.value)"
                />
            </div>

            <input
                v-if="isChecked(s.key) && s.key === 'other'"
                type="text" :disabled="disabled" :value="details(s.key).other" placeholder="Please specify..."
                class="mt-1.5 block w-full rounded-md border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                @input="setDetail(s.key, 'other', $event.target.value)"
            />
        </div>
    </div>
</template>
