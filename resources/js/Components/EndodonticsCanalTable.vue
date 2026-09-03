<script setup>
/**
 * The per-canal working-length/size table used twice in the original's
 * Endodontics section (First Visit's W.L. Estimation table, Second Visit's
 * Instrumentation table) — same 10 canals, different columns. Canal ids and
 * labels copied verbatim from operative.php's `$canals` array.
 *
 * One column can be `type: 'image'` (First Visit's `wl_xray`, 2026-09-03 —
 * "صورة الطول تكون عبر رفع صور للاشعة وليس حقل ادخال نصي") instead of the
 * default plain text: a real uploaded X-ray rather than free text. The
 * stored value doesn't change shape either way — still a plain string in
 * this canal's cell — only what that string *is* changes, from whatever a
 * doctor typed to the path `Api\EndodonticsXrayController`/
 * `EndodonticsXrayController` (web) hands back after the upload, resolved
 * to a URL the same `/storage/{path}` way every other uploaded image in
 * this app already is (see DoctorLayout.vue/Profile.vue's own profile
 * photo previews).
 */
import { ref } from 'vue';
import axios from 'axios';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    // Each column: { key, label, type? }. `key` is the per-canal data field
    // name (e.g. 'wl_xray', 'wl') — matches the original's own per-visit
    // naming. `type: 'image'` switches that column's cell to an upload
    // button + thumbnail instead of a text input.
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

// Keyed by `${canalId}:${columnKey}` — only ever one upload in flight per
// cell, so a plain reactive set of busy keys is enough (no need to track
// per-cell error text separately; a failed upload just clears busy and
// leaves the cell exactly as it was, same as never having touched it).
const uploading = ref(new Set());
const cellKey = (canalId, colKey) => `${canalId}:${colKey}`;

const uploadImage = async (canalId, colKey, file) => {
    const key = cellKey(canalId, colKey);
    uploading.value.add(key);
    try {
        const form = new FormData();
        form.append('image', file);
        const { data } = await axios.post(route('endodontics-xrays.store'), form);
        setField(canalId, colKey, data.path);
    } catch {
        // A failed upload leaves the cell unchanged — the doctor sees no
        // new thumbnail and can just try again, no separate error UI to
        // build for what's a rare network hiccup.
    } finally {
        uploading.value.delete(key);
    }
};

const onFileChange = (canalId, colKey, event) => {
    const file = event.target.files?.[0];
    event.target.value = ''; // allow re-selecting the same file later
    if (file) uploadImage(canalId, colKey, file);
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
                        <template v-if="col.type === 'image'">
                            <div class="flex items-center gap-1">
                                <a
                                    v-if="rowOf(canal.id)[col.key]"
                                    :href="`/storage/${rowOf(canal.id)[col.key]}`"
                                    target="_blank"
                                    rel="noopener"
                                >
                                    <img :src="`/storage/${rowOf(canal.id)[col.key]}`" class="h-8 w-8 rounded border border-gray-300 object-cover" />
                                </a>
                                <label
                                    class="flex h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded border border-dashed border-gray-300 text-gray-400 hover:border-indigo-400 hover:text-indigo-500"
                                    :class="{ 'pointer-events-none opacity-50': disabled || uploading.has(cellKey(canal.id, col.key)) }"
                                >
                                    <svg v-if="!uploading.has(cellKey(canal.id, col.key))" xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                                        <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V7.414a1 1 0 00-.293-.707L13.293 2.293A1 1 0 0012.586 2H4zm4 9a1 1 0 011-1h.01a1 1 0 110 2H9a1 1 0 01-1-1zm3-1a1 1 0 100 2h.01a1 1 0 100-2H11z" clip-rule="evenodd" />
                                    </svg>
                                    <svg v-else class="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24" fill="none">
                                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                                    </svg>
                                    <input
                                        type="file"
                                        accept="image/*"
                                        class="hidden"
                                        :disabled="disabled"
                                        @change="onFileChange(canal.id, col.key, $event)"
                                    />
                                </label>
                            </div>
                        </template>
                        <input
                            v-else
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
