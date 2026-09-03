<script setup>
/**
 * Multiple sessions/visits for the Advanced Periodontal Chart's 32-tooth
 * grid (2026-09-03, by request — "اعمله على شكل جلسات متعددة يتم اختيار
 * اكثر من جلسة"). `AdvancedPerioChart.vue` itself stays completely
 * untouched — it's a large, carefully tuned single-snapshot widget (see
 * its own doc comment's revision history), and every measurement/drawing
 * concern already lives there. This component only adds the thing that
 * didn't exist: a doctor-managed, addable-by-date list of sessions, shown
 * as tabs, one worked on at a time (confirmed with the user over the
 * fixed-3-sessions alternative `PeriodontalChartForm::chartGroups()` uses
 * for the *regular* Periodontal Chart — deliberately not reused here,
 * since that set is hardcoded PHP with no add-a-session mechanism at all).
 *
 * `modelValue` shape (the whole of `chart_data.advancedChart`):
 *   { sessions: [ { id, label, date, teeth: {...} }, ... ], activeSessionId }
 * Each session's own `teeth` is exactly the shape
 * `AdvancedPerioChart.vue`'s own `modelValue.teeth` already documents —
 * unchanged, just one copy per session instead of one total.
 *
 * Backward compatible with the pre-session shape (`{ teeth: {...} }`,
 * everything saved 2026-08-31–2026-09-03): `normalize()` wraps that into
 * a single "Session 1" on first load rather than losing it.
 */
import { computed, ref } from 'vue';
import AdvancedPerioChart from './AdvancedPerioChart.vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const genId = () => `sess_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const normalize = (value) => {
    if (Array.isArray(value?.sessions) && value.sessions.length > 0) {
        return value.sessions.map((s) => ({ id: s.id ?? genId(), label: s.label ?? '', date: s.date ?? '', teeth: s.teeth ?? {} }));
    }
    if (value?.teeth && Object.keys(value.teeth).length > 0) {
        return [{ id: genId(), label: 'Session 1', date: '', teeth: value.teeth }];
    }
    return [];
};

const sessions = ref(normalize(props.modelValue));
const activeId = ref(props.modelValue?.activeSessionId ?? sessions.value[0]?.id ?? null);

const activeSession = computed(() => sessions.value.find((s) => s.id === activeId.value) ?? null);

const emitUpdate = () => {
    emit('update:modelValue', { sessions: sessions.value, activeSessionId: activeId.value });
};

const showAddForm = ref(false);
const newLabel = ref('');
const newDate = ref('');

const openAddForm = () => {
    newLabel.value = `Session ${sessions.value.length + 1}`;
    newDate.value = new Date().toISOString().slice(0, 10);
    showAddForm.value = true;
};

const confirmAddSession = () => {
    const s = { id: genId(), label: newLabel.value.trim() || `Session ${sessions.value.length + 1}`, date: newDate.value, teeth: {} };
    sessions.value = [...sessions.value, s];
    activeId.value = s.id;
    showAddForm.value = false;
    emitUpdate();
};

const selectSession = (id) => {
    activeId.value = id;
    emitUpdate();
};

const removeSession = (id) => {
    if (props.disabled) return;
    if (!confirm('حذف هذه الجلسة نهائيًا؟ لا يمكن التراجع.')) return;
    sessions.value = sessions.value.filter((s) => s.id !== id);
    if (activeId.value === id) {
        activeId.value = sessions.value[0]?.id ?? null;
    }
    emitUpdate();
};

const updateActiveTeeth = (val) => {
    if (!activeSession.value) return;
    activeSession.value.teeth = val.teeth ?? {};
    emitUpdate();
};
</script>

<template>
    <div class="space-y-3">
        <div class="flex flex-wrap items-center gap-2 border-b border-gray-200 pb-2">
            <button
                v-for="s in sessions"
                :key="s.id"
                type="button"
                class="flex items-center gap-1.5 rounded-t-md border border-b-0 px-3 py-1.5 text-sm transition"
                :class="s.id === activeId ? 'border-gray-300 bg-white font-medium text-indigo-700' : 'border-transparent bg-gray-50 text-gray-500 hover:bg-gray-100'"
                @click="selectSession(s.id)"
            >
                <span>{{ s.label || 'Session' }}</span>
                <span v-if="s.date" class="text-xs text-gray-400">({{ s.date }})</span>
            </button>

            <template v-if="!disabled">
                <div v-if="showAddForm" class="flex items-center gap-2 rounded-md border border-indigo-200 bg-indigo-50 px-2 py-1">
                    <input v-model="newLabel" type="text" placeholder="Session name" class="w-32 rounded border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500" />
                    <input v-model="newDate" type="date" class="rounded border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500" />
                    <button type="button" class="text-sm font-medium text-indigo-700 hover:text-indigo-900" @click="confirmAddSession">Add</button>
                    <button type="button" class="text-sm text-gray-400 hover:text-gray-600" @click="showAddForm = false">Cancel</button>
                </div>
                <button
                    v-else
                    type="button"
                    class="rounded-md border border-dashed border-gray-300 px-3 py-1.5 text-sm text-gray-500 hover:border-indigo-400 hover:text-indigo-600"
                    @click="openAddForm"
                >
                    + New Session
                </button>
            </template>
        </div>

        <div v-if="activeSession" class="space-y-3">
            <div class="flex flex-wrap items-center gap-3 rounded-md bg-gray-50 px-3 py-2 text-sm">
                <label class="flex items-center gap-1.5">
                    <span class="text-gray-500">Session name:</span>
                    <input v-model="activeSession.label" type="text" :disabled="disabled" style="width: 10rem" class="rounded border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500" @change="emitUpdate" />
                </label>
                <label class="flex items-center gap-1.5">
                    <span class="text-gray-500">Date:</span>
                    <input v-model="activeSession.date" type="date" :disabled="disabled" class="rounded border-gray-300 text-sm focus:border-indigo-500 focus:ring-indigo-500" @change="emitUpdate" />
                </label>
                <button v-if="!disabled" type="button" class="text-sm text-red-600 hover:underline" @click="removeSession(activeSession.id)">
                    Delete this session
                </button>
            </div>

            <AdvancedPerioChart :model-value="{ teeth: activeSession.teeth }" :disabled="disabled" @update:model-value="updateActiveTeeth" />
        </div>
        <p v-else class="py-8 text-center text-sm text-gray-400">No sessions yet — click "+ New Session" to start.</p>
    </div>
</template>
