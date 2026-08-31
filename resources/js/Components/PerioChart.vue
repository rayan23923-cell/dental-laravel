<script setup>
/**
 * Periodontal chart grid — port of the tooth-column grid in
 * dental_clinics2/doctor/periodontal_chart.php.
 *
 * Six measurement sites per tooth (3 buccal + 3 palatal/lingual), matching
 * the original's collectPerioTableData(): each tooth serialises as
 * { buccal: [v, v, v], lingual: [v, v, v] }. The inner-surface *label*
 * differs by arch (palatal upper, lingual lower — generateToothColumn()),
 * but the stored key is always `lingual`, exactly as the original does.
 *
 * Tooth order is the original's quadrant layout, FDI notation:
 *   upper: 18→11 then 21→28   lower: 48→41 then 31→38
 */
import { computed } from 'vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    // 'bop' renders as toggling +/- cells (bleeding on probing, a boolean
    // per site in the original); 'ppd'/'cal' are numeric millimetre inputs.
    type: { type: String, default: 'ppd' },
    label: String,
    disabled: Boolean,
    // FDI tooth numbers marked extracted in the Plaque Index chart
    // (PlaqueChart.vue, same chart_data.dentalCharts column) — greys out
    // that tooth's whole column here, port of the original's own
    // syncDentalToPerio()/syncPerioFromDental() (`.tooth-col.missing`).
    // Visual only, same as the original: doesn't clear or disable the
    // tooth's existing site values, just flags "don't bother measuring
    // this one".
    extractedTeeth: { type: Array, default: () => [] },
});

const isExtracted = (tooth) => props.extractedTeeth.includes(tooth);

const emit = defineEmits(['update:modelValue']);

const UPPER = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const LOWER = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];

const siteValue = (tooth, zone, pos) => props.modelValue?.[tooth]?.[zone]?.[pos] ?? '';

const setSite = (tooth, zone, pos, value) => {
    const next = { ...props.modelValue };
    const current = next[tooth] ?? { buccal: ['', '', ''], lingual: ['', '', ''] };
    const zoneArr = [...(current[zone] ?? ['', '', ''])];
    zoneArr[pos] = value;
    next[tooth] = { ...current, [zone]: zoneArr };
    emit('update:modelValue', next);
};

// BOP is recorded as a present/absent mark per site; the original toggles a
// filled cell rather than typing a value, so '+' is stored for a bleeding
// site and '' for a clean one.
const toggleBop = (tooth, zone, pos) => {
    if (props.disabled) return;
    setSite(tooth, zone, pos, siteValue(tooth, zone, pos) === '+' ? '' : '+');
};

const innerLabel = (isUpper) => (isUpper ? 'Palatal' : 'Lingual');

const stats = computed(() => {
    let sites = 0;
    let marked = 0;
    for (const tooth of [...UPPER, ...LOWER]) {
        for (const zone of ['buccal', 'lingual']) {
            for (let i = 0; i < 3; i++) {
                const v = siteValue(tooth, zone, i);
                sites++;
                if (v !== '' && v !== null) marked++;
            }
        }
    }
    return { sites, marked, pct: sites ? Math.round((marked / sites) * 100) : 0 };
});
</script>

<template>
    <div class="rounded-lg border border-gray-200 bg-white p-3">
        <div class="mb-2 flex items-center justify-between">
            <h4 class="text-sm font-semibold text-gray-800">{{ label }}</h4>
            <span class="text-xs text-gray-500">
                {{ stats.marked }} / {{ stats.sites }} sites ({{ stats.pct }}%)
            </span>
        </div>

        <div class="overflow-x-auto">
            <div class="min-w-max space-y-3">
                <div v-for="arch in [{ teeth: UPPER, upper: true }, { teeth: LOWER, upper: false }]" :key="arch.upper">
                    <table class="border-collapse text-center text-[10px]">
                        <tbody>
                            <!-- Upper arch: buccal on top, then tooth number, then palatal -->
                            <template v-if="arch.upper">
                                <tr>
                                    <th class="whitespace-nowrap px-1 text-right text-[10px] font-medium text-gray-500">Buccal</th>
                                    <template v-for="tooth in arch.teeth" :key="`ub-${tooth}`">
                                        <td v-for="pos in [0, 1, 2]" :key="`ub-${tooth}-${pos}`" class="border border-gray-300 p-0" :class="{ 'bg-gray-200 opacity-50': isExtracted(tooth) }">
                                            <button
                                                v-if="type === 'bop'"
                                                type="button"
                                                class="h-6 w-6"
                                                :class="siteValue(tooth, 'buccal', pos) === '+' ? 'bg-red-500 text-white' : 'bg-white hover:bg-gray-100'"
                                                @click="toggleBop(tooth, 'buccal', pos)"
                                            >
                                                {{ siteValue(tooth, 'buccal', pos) }}
                                            </button>
                                            <input
                                                v-else
                                                type="text"
                                                inputmode="numeric"
                                                maxlength="2"
                                                :disabled="disabled"
                                                class="h-6 w-6 border-0 p-0 text-center text-[10px] focus:ring-1 focus:ring-indigo-400"
                                                :value="siteValue(tooth, 'buccal', pos)"
                                                @input="setSite(tooth, 'buccal', pos, $event.target.value)"
                                            />
                                        </td>
                                    </template>
                                </tr>
                                <tr>
                                    <th class="px-1"></th>
                                    <td
                                        v-for="tooth in arch.teeth"
                                        :key="`un-${tooth}`"
                                        colspan="3"
                                        class="border border-gray-400 px-1 py-0.5 font-semibold"
                                        :class="isExtracted(tooth) ? 'bg-red-100 text-red-700' : 'bg-gray-100'"
                                    >
                                        {{ tooth }}<span v-if="isExtracted(tooth)"> ✕</span>
                                    </td>
                                </tr>
                            </template>

                            <tr>
                                <th class="whitespace-nowrap px-1 text-right text-[10px] font-medium text-gray-500">{{ innerLabel(arch.upper) }}</th>
                                <template v-for="tooth in arch.teeth" :key="`l-${tooth}`">
                                    <td v-for="pos in [0, 1, 2]" :key="`l-${tooth}-${pos}`" class="border border-gray-300 p-0" :class="{ 'bg-gray-200 opacity-50': isExtracted(tooth) }">
                                        <button
                                            v-if="type === 'bop'"
                                            type="button"
                                            class="h-6 w-6"
                                            :class="siteValue(tooth, 'lingual', pos) === '+' ? 'bg-red-500 text-white' : 'bg-white hover:bg-gray-100'"
                                            @click="toggleBop(tooth, 'lingual', pos)"
                                        >
                                            {{ siteValue(tooth, 'lingual', pos) }}
                                        </button>
                                        <input
                                            v-else
                                            type="text"
                                            inputmode="numeric"
                                            maxlength="2"
                                            :disabled="disabled"
                                            class="h-6 w-6 border-0 p-0 text-center text-[10px] focus:ring-1 focus:ring-indigo-400"
                                            :value="siteValue(tooth, 'lingual', pos)"
                                            @input="setSite(tooth, 'lingual', pos, $event.target.value)"
                                        />
                                    </td>
                                </template>
                            </tr>

                            <!-- Lower arch: tooth number below the buccal row -->
                            <template v-if="!arch.upper">
                                <tr>
                                    <th class="px-1"></th>
                                    <td
                                        v-for="tooth in arch.teeth"
                                        :key="`ln-${tooth}`"
                                        colspan="3"
                                        class="border border-gray-400 px-1 py-0.5 font-semibold"
                                        :class="isExtracted(tooth) ? 'bg-red-100 text-red-700' : 'bg-gray-100'"
                                    >
                                        {{ tooth }}<span v-if="isExtracted(tooth)"> ✕</span>
                                    </td>
                                </tr>
                                <tr>
                                    <th class="whitespace-nowrap px-1 text-right text-[10px] font-medium text-gray-500">Buccal</th>
                                    <template v-for="tooth in arch.teeth" :key="`lb-${tooth}`">
                                        <td v-for="pos in [0, 1, 2]" :key="`lb-${tooth}-${pos}`" class="border border-gray-300 p-0" :class="{ 'bg-gray-200 opacity-50': isExtracted(tooth) }">
                                            <button
                                                v-if="type === 'bop'"
                                                type="button"
                                                class="h-6 w-6"
                                                :class="siteValue(tooth, 'buccal', pos) === '+' ? 'bg-red-500 text-white' : 'bg-white hover:bg-gray-100'"
                                                @click="toggleBop(tooth, 'buccal', pos)"
                                            >
                                                {{ siteValue(tooth, 'buccal', pos) }}
                                            </button>
                                            <input
                                                v-else
                                                type="text"
                                                inputmode="numeric"
                                                maxlength="2"
                                                :disabled="disabled"
                                                class="h-6 w-6 border-0 p-0 text-center text-[10px] focus:ring-1 focus:ring-indigo-400"
                                                :value="siteValue(tooth, 'buccal', pos)"
                                                @input="setSite(tooth, 'buccal', pos, $event.target.value)"
                                            />
                                        </td>
                                    </template>
                                </tr>
                            </template>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <p v-if="type === 'bop'" class="mt-2 text-xs text-gray-400">Click a site to toggle bleeding on probing.</p>
        <p v-else class="mt-2 text-xs text-gray-400">Enter measurements in millimetres (3 sites buccal, 3 sites {{ 'palatal/lingual' }}).</p>
    </div>
</template>
