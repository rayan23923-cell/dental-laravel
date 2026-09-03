<script setup>
/**
 * Endodontics Treatment Record — port of the section in
 * dental_clinics2/doctor/operative.php (`#endodonticsSection`), gated by
 * the iOS-style toggle (`.ios-toggle`) the original uses to show/hide it.
 * Every field name below matches the original's own `endodontics_data` JSON
 * keys exactly (tooth_no, canal_count, diagnosis[], first_visit[],
 * first_visit_data{canal:{...}}, second_visit_data{canal:{...}},
 * technique[], third_visit_data{...}) — read from the source, not guessed.
 *
 * **Deliberately not ported**: the per-visit image upload galleries
 * (`endodontics_images`, three separate multi-file widgets) and the
 * canvas-based signature pad (`data-sign-btn`). Both are substantial
 * features of their own — a real file-upload/gallery flow and a
 * signature-capture widget — out of scope for this pass; the signature is
 * a plain text field here instead of a drawn signature, and there is
 * nowhere to attach an image yet. Everything else in the section (the
 * toggle itself, tooth selection, canal count, diagnosis, all three
 * visits' checkboxes/tables/notes) is fully wired.
 */
import { computed } from 'vue';
import EndodonticsCanalTable from '@/Components/EndodonticsCanalTable.vue';
import Icon from '@/Components/Icon.vue';
import IosToggle from '@/Components/IosToggle.vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

// The section only exists once enabled — matches the original exactly
// (`if (!empty($existing_chart['endodontics_data']))`: an empty/absent
// value means the toggle starts off).
const enabled = computed({
    get: () => Object.keys(props.modelValue ?? {}).length > 0,
    set: (value) => emit('update:modelValue', value ? { ...(props.modelValue ?? {}) } : {}),
});

const set = (key, value) => emit('update:modelValue', { ...(props.modelValue ?? {}), [key]: value });

const toggleListItem = (key, value) => {
    const list = props.modelValue?.[key] ?? [];
    set(key, list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);
};

const isChecked = (key, value) => (props.modelValue?.[key] ?? []).includes(value);

const DIAGNOSES = [
    { value: 'pulpitis', label: 'Pulpitis' },
    { value: 'acute', label: 'Acute' },
    { value: 'chronic', label: 'Chronic' },
    { value: 'traumatic', label: 'Traumatic' },
    { value: 'peri-apical periodontitis', label: 'Peri-apical Periodontitis' },
];

const FIRST_VISIT_STEPS = [
    { value: 'access_opening', label: 'Access Opening' },
    { value: 'pulp_extirpation', label: 'Pulp Extirpation' },
    { value: 'working_length_estimation', label: 'Working Length Estimation' },
];

const TECHNIQUES = [
    { value: 'conventional', label: 'Conventional' },
    { value: 'step_back', label: 'Step Back' },
    { value: 'crown_down', label: 'Crown Down' },
    { value: 'combination', label: 'Combination' },
    { value: 'hand', label: 'Hand' },
    { value: 'rotary', label: 'Rotary' },
];

const thirdVisit = computed(() => props.modelValue?.third_visit_data ?? {});
const setThirdVisit = (key, value) => set('third_visit_data', { ...thirdVisit.value, [key]: value });
</script>

<template>
    <div class="overflow-hidden rounded-lg border border-gray-200 bg-white">
        <div class="flex items-center justify-between border-b border-gray-100 bg-gray-50 px-4 py-3">
            <h3 class="flex items-center gap-2 font-medium text-gray-900">
                <Icon name="dentistry" />Endodontic Treatment Record
            </h3>
            <label class="flex items-center gap-2 text-sm text-gray-600">
                <span>Enable</span>
                <IosToggle v-model="enabled" :disabled="disabled" />
            </label>
        </div>

        <div v-if="enabled" class="space-y-5 p-4">
            <!-- Tooth no. / canal count / diagnosis -->
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <div>
                    <label class="mb-1 block text-xs font-medium text-gray-600">Tooth Number</label>
                    <input
                        type="text"
                        :disabled="disabled"
                        :value="modelValue.tooth_no ?? ''"
                        placeholder="e.g. 46"
                        class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        @input="set('tooth_no', $event.target.value)"
                    />
                </div>

                <div>
                    <label class="mb-1 block text-xs font-medium text-gray-600">Number of Canals</label>
                    <div class="flex flex-wrap gap-2">
                        <label v-for="opt in [['one','One'],['two','Two'],['three','Three'],['four','Four']]" :key="opt[0]" class="flex items-center gap-1 text-xs text-gray-700">
                            <input
                                type="radio"
                                :disabled="disabled"
                                :checked="modelValue.canal_count === opt[0]"
                                class="border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                @change="set('canal_count', opt[0])"
                            />
                            {{ opt[1] }}
                        </label>
                    </div>
                </div>

                <div>
                    <label class="mb-1 block text-xs font-medium text-gray-600">Diagnosis</label>
                    <div class="flex flex-col gap-1">
                        <label v-for="opt in DIAGNOSES" :key="opt.value" class="flex items-center gap-1.5 text-xs text-gray-700">
                            <input
                                type="checkbox"
                                :disabled="disabled"
                                :checked="isChecked('diagnosis', opt.value)"
                                class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                @change="toggleListItem('diagnosis', opt.value)"
                            />
                            {{ opt.label }}
                        </label>
                    </div>
                </div>
            </div>

            <!-- First visit -->
            <div class="border-t border-gray-100 pt-4">
                <h4 class="mb-2 flex items-center gap-1.5 text-sm font-semibold text-gray-800">
                    <Icon name="event_available" size="text-[16px]" />First Visit
                </h4>
                <div class="mb-3 flex flex-wrap gap-3">
                    <label v-for="opt in FIRST_VISIT_STEPS" :key="opt.value" class="flex items-center gap-1.5 text-xs text-gray-700">
                        <input
                            type="checkbox"
                            :disabled="disabled"
                            :checked="isChecked('first_visit', opt.value)"
                            class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                            @change="toggleListItem('first_visit', opt.value)"
                        />
                        {{ opt.label }}
                    </label>
                </div>
                <EndodonticsCanalTable
                    :model-value="modelValue.first_visit_data ?? {}"
                    :disabled="disabled"
                    :columns="[
                        { key: 'wl_xray', label: 'Working Length X-ray' },
                        { key: 'initial_length', label: 'Initial Length' },
                        { key: 'initial_size', label: 'Initial Size' },
                        { key: 'final_wl', label: 'Final Working Length' },
                    ]"
                    @update:model-value="set('first_visit_data', $event)"
                />
            </div>

            <!-- Second visit -->
            <div class="border-t border-gray-100 pt-4">
                <h4 class="mb-2 flex items-center gap-1.5 text-sm font-semibold text-gray-800">
                    <Icon name="event_available" size="text-[16px]" />Second Visit — Instrumentation
                </h4>
                <EndodonticsCanalTable
                    :model-value="modelValue.second_visit_data ?? {}"
                    :disabled="disabled"
                    :columns="[
                        { key: 'wl', label: 'Working Length' },
                        { key: 'size', label: 'Size' },
                        { key: 'rp', label: 'R.P.' },
                    ]"
                    @update:model-value="set('second_visit_data', $event)"
                />
                <div class="mt-3">
                    <label class="mb-1 block text-xs font-medium text-gray-600">Instrumentation Technique</label>
                    <div class="flex flex-wrap gap-3">
                        <label v-for="opt in TECHNIQUES" :key="opt.value" class="flex items-center gap-1.5 text-xs text-gray-700">
                            <input
                                type="checkbox"
                                :disabled="disabled"
                                :checked="isChecked('technique', opt.value)"
                                class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                @change="toggleListItem('technique', opt.value)"
                            />
                            {{ opt.label }}
                        </label>
                    </div>
                </div>
            </div>

            <!-- Third visit -->
            <div class="border-t border-gray-100 pt-4">
                <h4 class="mb-2 flex items-center gap-1.5 text-sm font-semibold text-gray-800">
                    <Icon name="event_available" size="text-[16px]" />Third Visit — Obturation
                </h4>
                <div class="space-y-2">
                    <div class="flex flex-wrap items-center gap-3">
                        <span class="text-xs font-medium text-gray-600">Master Cone Check:</span>
                        <label class="flex items-center gap-1 text-xs text-gray-700">
                            <input type="checkbox" :disabled="disabled" :checked="!!thirdVisit.master_cone_clinical" class="rounded border-gray-300 text-indigo-600" @change="setThirdVisit('master_cone_clinical', $event.target.checked)" />Clinical
                        </label>
                        <label class="flex items-center gap-1 text-xs text-gray-700">
                            <input type="checkbox" :disabled="disabled" :checked="!!thirdVisit.master_cone_radiographical" class="rounded border-gray-300 text-indigo-600" @change="setThirdVisit('master_cone_radiographical', $event.target.checked)" />Radiographic
                        </label>
                        <input
                            type="text" :disabled="disabled" :value="thirdVisit.master_cone_notes ?? ''" placeholder="Notes..."
                            class="min-w-[10rem] flex-1 rounded-md border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            @input="setThirdVisit('master_cone_notes', $event.target.value)"
                        />
                    </div>
                    <div class="flex flex-wrap items-center gap-3">
                        <span class="text-xs font-medium text-gray-600">Obturation Check:</span>
                        <label class="flex items-center gap-1 text-xs text-gray-700">
                            <input type="checkbox" :disabled="disabled" :checked="!!thirdVisit.obturation_clinical" class="rounded border-gray-300 text-indigo-600" @change="setThirdVisit('obturation_clinical', $event.target.checked)" />Clinical
                        </label>
                        <label class="flex items-center gap-1 text-xs text-gray-700">
                            <input type="checkbox" :disabled="disabled" :checked="!!thirdVisit.obturation_radiographical" class="rounded border-gray-300 text-indigo-600" @change="setThirdVisit('obturation_radiographical', $event.target.checked)" />Radiographic
                        </label>
                        <input
                            type="text" :disabled="disabled" :value="thirdVisit.obturation_notes ?? ''" placeholder="Notes..."
                            class="min-w-[10rem] flex-1 rounded-md border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            @input="setThirdVisit('obturation_notes', $event.target.value)"
                        />
                    </div>
                </div>
            </div>

            <!-- Signature — plain text, not a drawn signature; see the
                 file-level docblock for why. -->
            <div class="border-t border-gray-100 pt-4">
                <label class="mb-1 block text-xs font-medium text-gray-600">Supervisor Signature</label>
                <input
                    type="text"
                    :disabled="disabled"
                    :value="modelValue.signature ?? ''"
                    class="block w-full max-w-xs rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    @input="set('signature', $event.target.value)"
                />
            </div>
        </div>
    </div>
</template>
