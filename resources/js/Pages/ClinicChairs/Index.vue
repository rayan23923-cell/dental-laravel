<script setup>
/**
 * Clinic seating map (2026-09-03, by request) — chairs laid out in
 * straight rows. A chair can be assigned at the group level (a block of
 * seats for a whole group, dragged on) or, since 2026-09-04, at the
 * individual-doctor level: clicking "Distribute" on a group in the
 * sidebar spreads its doctors across chairs one-per-doctor (existing
 * empty chairs first, new ones after — see
 * `ClinicChairController::assignGroup()`), each then showing that
 * doctor's own name and photo. The same button, clicked again after a
 * new doctor joins the group, only seats the newcomer — "امكانية تحديث
 * الكراسي اذا تم اضافة طبيب جديد للنظام" needed no separate action.
 *
 * Two drag gestures share one native HTML5 DnD implementation (no new
 * dependency — nothing in package.json does this already, and the
 * interaction here is simple enough not to need one):
 *   - dragging a group chip from the sidebar onto a chair assigns it
 *     (plain group-level mode)
 *   - dragging a chair onto another chair swaps their positions —
 *     including doctor-assigned chairs, so a group's random initial
 *     layout can be rearranged and the arrangement saved (it's already
 *     persisted per-drag, no separate "save" step)
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
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    chairs: Array,
    groups: Array,
    stages: Array,
    currentSession: Object,
    assignedDoctorIds: { type: Array, default: () => [] },
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

// How many of a group's doctors don't have a chair yet — drives the
// sidebar's "Distribute" (first time) / "Update (N new)" (a doctor
// joined since) button label and disabled state together, see
// assignGroup() below.
const assignedDoctorIdSet = computed(() => new Set(props.assignedDoctorIds));
const unseatedCount = (group) => group.doctors.filter((d) => !assignedDoctorIdSet.value.has(d.id)).length;

const assigningGroupId = ref(null);
const assignGroup = (group) => {
    assigningGroupId.value = group.id;
    router.post(
        route('clinic-chairs.assign-group'),
        { group_id: group.id },
        { preserveScroll: true, onFinish: () => (assigningGroupId.value = null) },
    );
};

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
    if (confirm(t('clinicChairsAdmin.removeChairConfirm'))) {
        router.delete(route('clinic-chairs.destroy', chair.id), { preserveScroll: true });
    }
};

// --- Doctor roster popover -------------------------------------------
const viewing = ref(null);
</script>

<template>
    <Head :title="t('clinicChairsAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('clinicChairsAdmin.title') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-7xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs active="clinic-chairs" />

                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div v-if="currentSession" class="rounded-md bg-indigo-50 p-3 text-sm text-indigo-700">
                    {{ t('clinicChairsAdmin.sessionLabel') }} <strong>{{ currentSession.name }}</strong>
                </div>

                <p class="text-sm text-gray-600">
                    {{ t('clinicChairsAdmin.instructions') }}
                </p>

                <div class="flex flex-col gap-4 lg:flex-row">
                    <!-- Sidebar: assignable groups -->
                    <div class="w-full shrink-0 rounded-lg bg-white p-4 shadow-sm lg:w-64">
                        <div class="mb-3 flex items-center justify-between">
                            <h3 class="text-sm font-semibold text-gray-700">{{ t('clinicChairsAdmin.groupsHeading') }}</h3>
                            <select
                                v-model="filterStageId"
                                class="rounded-md border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            >
                                <option value="">{{ t('taxonomyAdmin.allStages') }}</option>
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
                                <div class="text-xs text-gray-500">{{ group.stage?.name ?? '—' }} · {{ group.doctors.length }} {{ t('clinicChairsAdmin.doctorsSuffix') }}</div>
                                <button
                                    v-if="unseatedCount(group) > 0"
                                    type="button"
                                    :disabled="assigningGroupId === group.id"
                                    @click.stop="assignGroup(group)"
                                    class="mt-1.5 rounded bg-indigo-600 px-2 py-1 text-xs font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
                                >
                                    {{ assigningGroupId === group.id ? '…' : (unseatedCount(group) === group.doctors.length ? t('clinicChairsAdmin.distribute') : t('clinicChairsAdmin.updateWithCount', { n: unseatedCount(group) })) }}
                                </button>
                            </div>
                            <p v-if="filteredGroups.length === 0" class="py-4 text-center text-xs text-gray-400">{{ t('clinicChairsAdmin.noGroups') }}</p>
                        </div>
                    </div>

                    <!-- Chair grid — visual design supplied by the user directly
                         (station card: avatar + side-view dental chair drawing),
                         swapped in for the plain boxes this used to render.
                         Row-by-row grouping/drag-drop/click wiring is unchanged. -->
                    <div class="flex-1 space-y-6 rounded-lg bg-white p-4 shadow-sm">
                        <div v-for="row in rows" :key="row.rowNumber" class="border-b border-gray-100 pb-6 last:border-0">
                            <span class="mb-2 block text-xs font-medium text-gray-400">{{ t('clinicChairsAdmin.rowLabel', { n: row.rowNumber }) }}</span>
                            <div class="chairs-row">
                                <div
                                    v-for="chair in row.chairs"
                                    :key="chair.id"
                                    draggable="true"
                                    @dragstart="onDragChairStart(chair)"
                                    @dragend="onDragEnd"
                                    @dragover.prevent="dragOverChairId = chair.id"
                                    @dragleave="dragOverChairId === chair.id && (dragOverChairId = null)"
                                    @drop.prevent="onDrop(chair)"
                                    class="station"
                                    :class="{ 'station--dragover': dragOverChairId === chair.id }"
                                    @click="chair.group && (viewing = chair)"
                                >
                                    <button type="button" @click.stop="removeChair(chair)" class="station-remove" :title="t('clinicChairsAdmin.removeChairTitle')">&times;</button>

                                    <div class="avatar-wrapper">
                                        <div class="avatar" :class="{ 'avatar--empty': !chair.group }">
                                            <img v-if="chair.doctor?.profile_image" :src="`/storage/${chair.doctor.profile_image}`" alt="" />
                                            <svg v-else viewBox="0 0 40 40">
                                                <circle cx="20" cy="13" r="7" fill="white" />
                                                <path d="M8 35 C9 26 14 22 20 22 C26 22 31 26 32 35 Z" fill="white" />
                                            </svg>
                                        </div>
                                        <div class="name">
                                            <template v-if="chair.doctor">
                                                {{ chair.doctor.name }}
                                                <button type="button" @click.stop="unassign(chair)" class="unassign-x" :title="t('clinicChairsAdmin.unassignTitle')">&times;</button>
                                            </template>
                                            <template v-else-if="chair.group">
                                                {{ chair.group.name }}
                                                <button type="button" @click.stop="unassign(chair)" class="unassign-x" :title="t('clinicChairsAdmin.unassignTitle')">&times;</button>
                                            </template>
                                            <template v-else>{{ t('clinicChairsAdmin.emptyChairName') }}</template>
                                        </div>
                                        <div v-if="chair.doctor && chair.group" class="group-badge">{{ chair.group.name }}</div>
                                    </div>

                                    <div class="dental-chair">
                                        <div class="head"></div>
                                        <div class="back"></div>
                                        <div class="seat"></div>
                                        <div class="foot"></div>
                                        <div class="arm"></div>
                                        <div class="column"></div>
                                        <div class="base"></div>
                                        <div class="base-center"></div>
                                        <div class="status" :class="{ 'status--empty': !chair.group }"></div>
                                        <div class="number">{{ chair.label ?? `${chair.row_number}-${chair.column_number}` }}</div>
                                    </div>
                                </div>

                                <button type="button" @click="addChair(row.rowNumber)" class="add-chair-btn" :title="t('clinicChairsAdmin.addChairToRowTitle')">+</button>
                            </div>
                        </div>

                        <div v-if="rows.length === 0" class="py-8 text-center text-sm text-gray-400">{{ t('clinicChairsAdmin.emptyChairs') }}</div>

                        <SecondaryButton @click="addChair()">{{ t('clinicChairsAdmin.addRow') }}</SecondaryButton>
                    </div>
                </div>
            </div>
        </div>

        <Modal :show="viewing !== null" @close="viewing = null">
            <div class="p-6" v-if="viewing">
                <h2 class="text-lg font-medium text-gray-900">{{ viewing.doctor ? viewing.doctor.name : viewing.group.name }}</h2>
                <p class="mt-1 text-xs text-gray-500">
                    {{ t('clinicChairsAdmin.chairLabel', { label: viewing.label ?? `${viewing.row_number}-${viewing.column_number}` }) }}
                    <span v-if="viewing.doctor"> · {{ viewing.group.name }}</span>
                </p>
                <p v-if="viewing.doctor" class="mt-3 text-xs font-medium uppercase tracking-wide text-gray-400">{{ t('clinicChairsAdmin.restOfGroup') }}</p>
                <ul class="mt-4 space-y-1.5 text-sm text-gray-700">
                    <li v-for="doctor in viewing.group.doctors" :key="doctor.id" class="flex items-center gap-2" :class="{ 'font-semibold text-indigo-700': doctor.id === viewing.doctor?.id }">
                        <span class="material-symbols-outlined text-[16px] text-gray-400" aria-hidden="true">person</span>
                        {{ doctor.name }}
                    </li>
                    <li v-if="viewing.group.doctors.length === 0" class="text-gray-400">{{ t('clinicChairsAdmin.noDoctorsInGroupYet') }}</li>
                </ul>
                <div class="mt-6 flex justify-end">
                    <PrimaryButton @click="viewing = null">{{ t('common.close') }}</PrimaryButton>
                </div>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>

<style scoped>
/* Station card visual — supplied by the user directly (avatar + a
   side-view dental chair drawn in plain CSS shapes) to replace the
   plain rectangular chair boxes this page used to render. Row-by-row
   grouping and every drag/drop/click handler stayed in the template
   above unchanged; only this per-chair appearance is new. */

.chairs-row {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    gap: 32px;
}

.station {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    cursor: grab;
    transition: 0.25s;
    padding-top: 8px;
}
.station:active {
    cursor: grabbing;
}
.station:hover {
    transform: translateY(-4px);
}
.station--dragover {
    outline: 2px solid #6366f1;
    outline-offset: 4px;
    border-radius: 12px;
}

.station-remove {
    position: absolute;
    right: -4px;
    top: 0;
    display: none;
    align-items: center;
    justify-content: center;
    width: 16px;
    height: 16px;
    border-radius: 9999px;
    background: #9ca3af;
    color: white;
    font-size: 10px;
    line-height: 1;
    z-index: 6;
}
.station:hover .station-remove {
    display: flex;
}
.station-remove:hover {
    background: #ef4444;
}

.avatar-wrapper {
    display: flex;
    flex-direction: column;
    align-items: center;
    margin-bottom: 10px;
    position: relative;
    z-index: 5;
}

.avatar {
    width: 46px;
    height: 46px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #833ab4, #e1306c);
    border: 3px solid white;
    box-shadow: 0 5px 15px rgba(40, 20, 50, 0.18);
}
.avatar--empty {
    background: linear-gradient(135deg, #b9b9c2, #d8d5df);
}
.avatar svg {
    width: 26px;
    height: 26px;
}
.avatar img {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    object-fit: cover;
}

.group-badge {
    margin-top: 3px;
    font-size: 9px;
    color: #91899e;
    max-width: 130px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.name {
    margin-top: 5px;
    padding: 3px 9px;
    background: white;
    border: 1px solid #e8e2ed;
    border-radius: 20px;
    font-size: 10px;
    box-shadow: 0 3px 8px rgba(30, 20, 40, 0.07);
    display: flex;
    align-items: center;
    gap: 4px;
    max-width: 130px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.unassign-x {
    color: #91899e;
    font-size: 11px;
    line-height: 1;
}
.unassign-x:hover {
    color: #e1306c;
}

.dental-chair {
    position: relative;
    width: 130px;
    height: 165px;
    transform: scale(0.87);
    transform-origin: top center;
}

.head {
    position: absolute;
    left: 35px;
    top: 5px;
    width: 28px;
    height: 23px;
    border-radius: 12px 12px 7px 7px;
    background: linear-gradient(135deg, #075da5, #147dcc);
}

.back {
    position: absolute;
    left: 45px;
    top: 25px;
    width: 35px;
    height: 82px;
    border-radius: 18px 18px 8px 8px;
    background: linear-gradient(90deg, #075da5, #1c8ddd);
    transform: rotate(-8deg);
    transform-origin: bottom center;
}

.seat {
    position: absolute;
    left: 50px;
    top: 91px;
    width: 72px;
    height: 40px;
    border-radius: 14px 14px 10px 10px;
    background: linear-gradient(135deg, #0878d1, #38a2e4);
}

.foot {
    position: absolute;
    left: 102px;
    top: 112px;
    width: 42px;
    height: 24px;
    border-radius: 8px 12px 10px 8px;
    background: linear-gradient(135deg, #0869b3, #2295df);
    transform: rotate(8deg);
}

.arm {
    position: absolute;
    left: 69px;
    top: 83px;
    width: 55px;
    height: 7px;
    border-radius: 10px;
    background: #808b99;
}

.column {
    position: absolute;
    left: 80px;
    top: 127px;
    width: 15px;
    height: 35px;
    background: linear-gradient(90deg, #707b8a, #f4f6f8, #7b8694);
}

.base {
    position: absolute;
    left: 34px;
    top: 157px;
    width: 105px;
    height: 24px;
    background: linear-gradient(180deg, #eef1f4, #8a95a3);
    clip-path: polygon(0 55%, 20% 30%, 48% 48%, 70% 25%, 100% 55%, 78% 80%, 55% 65%, 35% 90%, 12% 75%);
}

.base-center {
    position: absolute;
    left: 75px;
    top: 153px;
    width: 25px;
    height: 16px;
    border-radius: 50%;
    background: #687382;
}

.status {
    position: absolute;
    left: 108px;
    top: -2px;
    width: 11px;
    height: 11px;
    border-radius: 50%;
    background: #18a558;
    border: 2px solid white;
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
    z-index: 3;
}
.status--empty {
    background: #b0b6c0;
}

.number {
    position: absolute;
    left: 66px;
    top: 103px;
    color: white;
    font-size: 10px;
    font-weight: bold;
    z-index: 3;
    pointer-events: none;
}

.add-chair-btn {
    align-self: center;
    display: flex;
    height: 130px;
    width: 44px;
    align-items: center;
    justify-content: center;
    border-radius: 12px;
    border: 2px dashed #e5e7eb;
    color: #9ca3af;
    font-size: 20px;
}
.add-chair-btn:hover {
    border-color: #a5b4fc;
    color: #6366f1;
}
</style>
