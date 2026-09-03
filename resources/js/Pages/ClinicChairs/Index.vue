<script setup>
/**
 * Clinic seating map (2026-09-03, by request) — chairs laid out in
 * straight rows, each optionally assigned to a whole Group (see
 * `ClinicChair`'s own doc comment for why group-level, not per-doctor).
 * Two drag gestures share one native HTML5 DnD implementation (no new
 * dependency — nothing in package.json does this already, and the
 * interaction here is simple enough not to need one):
 *   - dragging a group chip from the sidebar onto a chair assigns it
 *   - dragging a chair onto another chair swaps their positions
 * `dataTransfer` carries a small `{type, id}` JSON payload so `onDrop`
 * can tell which gesture produced a given drop without separate handler
 * wiring per drop target.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import StructureTabs from '@/Components/StructureTabs.vue';
import { Head, router, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';

const props = defineProps({
    chairs: Array,
    groups: Array,
    stages: Array,
    currentSession: Object,
});

const page = usePage();

const rows = computed(() => {
    const byRow = new Map();
    for (const chair of props.chairs) {
        if (!byRow.has(chair.row_number)) byRow.set(chair.row_number, []);
        byRow.get(chair.row_number).push(chair);
    }
    return [...byRow.entries()]
        .sort((a, b) => a[0] - b[0])
        .map(([rowNumber, chairs]) => ({ rowNumber, chairs: chairs.sort((a, b) => a.column_number - b.column_number) }));
});

const filterStageId = ref('');
const filteredGroups = computed(() =>
    filterStageId.value ? props.groups.filter((g) => g.stage_id === Number(filterStageId.value)) : props.groups
);

const assignedGroupIds = computed(() => new Set(props.chairs.filter((c) => c.group_id).map((c) => c.group_id)));

// --- Drag and drop --------------------------------------------------
const dragging = ref(null); // { type: 'group' | 'chair', id }
const dragOverChairId = ref(null);

const onDragGroupStart = (group) => {
    dragging.value = { type: 'group', id: group.id };
};
const onDragChairStart = (chair) => {
    dragging.value = { type: 'chair', id: chair.id };
};
const onDragEnd = () => {
    dragging.value = null;
    dragOverChairId.value = null;
};

const onDrop = (targetChair) => {
    if (!dragging.value) return;

    if (dragging.value.type === 'group') {
        router.put(route('clinic-chairs.update', targetChair.id), { group_id: dragging.value.id }, { preserveScroll: true });
    } else if (dragging.value.type === 'chair' && dragging.value.id !== targetChair.id) {
        router.put(
            route('clinic-chairs.move', dragging.value.id),
            { row_number: targetChair.row_number, column_number: targetChair.column_number },
            { preserveScroll: true },
        );
    }
    onDragEnd();
};

const unassign = (chair) => {
    router.put(route('clinic-chairs.update', chair.id), { group_id: null }, { preserveScroll: true });
};

const addChair = (rowNumber = null) => {
    router.post(route('clinic-chairs.store'), { row_number: rowNumber }, { preserveScroll: true });
};

const removeChair = (chair) => {
    if (confirm('Remove this chair?')) {
        router.delete(route('clinic-chairs.destroy', chair.id), { preserveScroll: true });
    }
};

// --- Doctor roster popover -------------------------------------------
const viewing = ref(null);
</script>

<template>
    <Head title="Clinic Chair Map" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">Clinic Chair Map</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-7xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs active="clinic-chairs" />

                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div v-if="currentSession" class="rounded-md bg-indigo-50 p-3 text-sm text-indigo-700">
                    Academic Session: <strong>{{ currentSession.name }}</strong>
                </div>

                <p class="text-sm text-gray-600">
                    Drag a group onto a chair to assign it there. Drag a chair onto another chair to swap their positions.
                </p>

                <div class="flex flex-col gap-4 lg:flex-row">
                    <!-- Sidebar: assignable groups -->
                    <div class="w-full shrink-0 rounded-lg bg-white p-4 shadow-sm lg:w-64">
                        <div class="mb-3 flex items-center justify-between">
                            <h3 class="text-sm font-semibold text-gray-700">Groups</h3>
                            <select
                                v-model="filterStageId"
                                class="rounded-md border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            >
                                <option value="">All stages</option>
                                <option v-for="stage in stages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
                            </select>
                        </div>
                        <div class="space-y-1.5">
                            <div
                                v-for="group in filteredGroups"
                                :key="group.id"
                                draggable="true"
                                @dragstart="onDragGroupStart(group)"
                                @dragend="onDragEnd"
                                class="cursor-grab rounded-md border px-3 py-2 text-sm active:cursor-grabbing"
                                :class="assignedGroupIds.has(group.id) ? 'border-indigo-200 bg-indigo-50 text-indigo-800' : 'border-gray-200 bg-gray-50 text-gray-700'"
                            >
                                <div class="font-medium">{{ group.name }}</div>
                                <div class="text-xs text-gray-500">{{ group.stage?.name ?? '—' }} · {{ group.doctors.length }} doctor(s)</div>
                            </div>
                            <p v-if="filteredGroups.length === 0" class="py-4 text-center text-xs text-gray-400">No groups.</p>
                        </div>
                    </div>

                    <!-- Chair grid -->
                    <div class="flex-1 space-y-4 rounded-lg bg-white p-4 shadow-sm">
                        <div v-for="row in rows" :key="row.rowNumber" class="flex flex-wrap items-center gap-2 border-b border-gray-100 pb-4 last:border-0">
                            <span class="w-6 shrink-0 text-xs font-medium text-gray-400">{{ row.rowNumber }}</span>
                            <div
                                v-for="chair in row.chairs"
                                :key="chair.id"
                                draggable="true"
                                @dragstart="onDragChairStart(chair)"
                                @dragend="onDragEnd"
                                @dragover.prevent="dragOverChairId = chair.id"
                                @dragleave="dragOverChairId === chair.id && (dragOverChairId = null)"
                                @drop.prevent="onDrop(chair)"
                                class="group relative w-36 cursor-grab rounded-lg border-2 p-2.5 text-xs transition active:cursor-grabbing"
                                :class="[
                                    dragOverChairId === chair.id ? 'border-indigo-500 bg-indigo-50' : 'border-gray-200',
                                    chair.group ? 'bg-emerald-50' : 'bg-gray-50',
                                ]"
                                @click="chair.group && (viewing = chair)"
                            >
                                <button
                                    type="button"
                                    @click.stop="removeChair(chair)"
                                    class="absolute -right-1.5 -top-1.5 hidden h-4 w-4 items-center justify-center rounded-full bg-gray-400 text-[10px] leading-none text-white hover:bg-red-500 group-hover:flex"
                                    title="Remove chair"
                                >
                                    &times;
                                </button>
                                <div class="mb-1 flex items-center gap-1 text-gray-400">
                                    <span class="material-symbols-outlined text-[16px]" aria-hidden="true">chair</span>
                                    <span>{{ chair.label ?? `${chair.row_number}-${chair.column_number}` }}</span>
                                </div>
                                <div v-if="chair.group" class="font-medium text-emerald-800">
                                    {{ chair.group.name }}
                                    <button type="button" @click.stop="unassign(chair)" class="ml-1 text-emerald-600 hover:text-emerald-900" title="Unassign">
                                        &times;
                                    </button>
                                </div>
                                <div v-else class="text-gray-400">Empty</div>
                            </div>
                            <button
                                type="button"
                                @click="addChair(row.rowNumber)"
                                class="flex h-[4.5rem] w-10 shrink-0 items-center justify-center rounded-lg border-2 border-dashed border-gray-200 text-gray-400 hover:border-indigo-300 hover:text-indigo-500"
                                title="Add chair to this row"
                            >
                                +
                            </button>
                        </div>

                        <div v-if="rows.length === 0" class="py-8 text-center text-sm text-gray-400">No chairs yet — start a row below.</div>

                        <SecondaryButton @click="addChair()">+ Add Row</SecondaryButton>
                    </div>
                </div>
            </div>
        </div>

        <Modal :show="viewing !== null" @close="viewing = null">
            <div class="p-6" v-if="viewing">
                <h2 class="text-lg font-medium text-gray-900">{{ viewing.group.name }}</h2>
                <p class="mt-1 text-xs text-gray-500">Chair {{ viewing.label ?? `${viewing.row_number}-${viewing.column_number}` }}</p>
                <ul class="mt-4 space-y-1.5 text-sm text-gray-700">
                    <li v-for="doctor in viewing.group.doctors" :key="doctor.id" class="flex items-center gap-2">
                        <span class="material-symbols-outlined text-[16px] text-gray-400" aria-hidden="true">person</span>
                        {{ doctor.name }}
                    </li>
                    <li v-if="viewing.group.doctors.length === 0" class="text-gray-400">No doctors in this group yet.</li>
                </ul>
                <div class="mt-6 flex justify-end">
                    <PrimaryButton @click="viewing = null">Close</PrimaryButton>
                </div>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
