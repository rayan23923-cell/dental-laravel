<script setup>
/**
 * The per-canal working-length/size table used twice in the original's
 * Endodontics section (First Visit's W.L. Estimation table, Second Visit's
 * Instrumentation table) — same 10 canals, different columns. Canal ids and
 * labels copied verbatim from operative.php's `$canals` array.
 */
const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    // Each column: { key, label }. `key` is the per-canal data field name
    // (e.g. 'wl_xray', 'wl') — matches the original's own per-visit naming.
    columns: { type: Array, required: true },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const CANALS = [
    { id: 'B', label: 'B.' }, { id: 'P', label: 'P.' }, { id: 'OR', label: 'OR' },
    { id: 'L', label: 'L.' }, { id: 'M', label: 'M.' }, { id: 'D', label: 'D.' },
    { id: 'DB', label: 'D.B.' }, { id: 'DL', label: 'D.L.' },
    { id: 'MB', label: 'M.B.' }, { id: 'ML', label: 'M.L.' },
];

const rowOf = (canalId) => props.modelValue?.[canalId] ?? {};

const setField = (canalId, field, value) => {
    emit('update:modelValue', {
        ...props.modelValue,
        [canalId]: { ...rowOf(canalId), [field]: value },
    });
};
</script>

<template>
    <div class="overflow-x-auto">
        <table class="min-w-full border-collapse text-xs">
            <thead>
                <tr class="bg-gray-50">
                    <th class="border border-gray-200 px-2 py-1 text-right font-medium text-gray-600">Canal</th>
                    <th v-for="col in columns" :key="col.key" class="border border-gray-200 px-2 py-1 text-right font-medium text-gray-600">
                        {{ col.label }}
                    </th>
                </tr>
            </thead>
            <tbody>
                <tr v-for="canal in CANALS" :key="canal.id">
                    <td class="border border-gray-200 px-2 py-1">
                        <label class="flex items-center gap-1.5 whitespace-nowrap">
                            <input
                                type="checkbox"
                                :disabled="disabled"
                                :checked="!!rowOf(canal.id).checked"
                                class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                @change="setField(canal.id, 'checked', $event.target.checked)"
                            />
                            {{ canal.label }}
                        </label>
                    </td>
                    <td v-for="col in columns" :key="col.key" class="border border-gray-200 p-0.5">
                        <input
                            type="text"
                            :disabled="disabled"
                            :value="rowOf(canal.id)[col.key] ?? ''"
                            class="w-16 rounded border-0 px-1 py-0.5 text-xs focus:ring-1 focus:ring-indigo-500"
                            @input="setField(canal.id, col.key, $event.target.value)"
                        />
                    </td>
                </tr>
            </tbody>
        </table>
    </div>
</template>
