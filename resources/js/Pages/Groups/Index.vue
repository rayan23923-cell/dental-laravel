<script setup>
/**
 * إدارة المجموعات — rebuilt to match dental_clinics2/admin/manage_groups.php
 * and its load_groups.php card renderer: the same filter row
 * (نوع الدراسة → المرحلة → عرض المجموعات), the same inline add-group form
 * with repeatable day/time slot rows, and the same group card — slots list,
 * per-group doctor search, "تحديد الكل", bulk "حذف المحدد (N)", per-doctor
 * remove, doctor total, and the "إضافة أطباء للمجموعة" modal.
 *
 * Chat-list style (2026-10-13, by request): each group is a chat row that
 * expands to its doctors (themselves chat rows with a checkbox), the add
 * form moved into a dialog opened by the header "+", and the filters are
 * a compact row of pills. Every action above is kept.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { toneFor } from '@/Components/ChatList/tones';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import StructureTabs from '@/Components/StructureTabs.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';
import Icon from '@/Components/Icon.vue';

// The original's day <select> offers Sunday–Thursday only (the work week).
const DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];

const { t } = useI18n();
const props = defineProps({
    groups: Array,
    loaded: Boolean,
    educationTypes: Array,
    stages: Array,
    filters: Object,
    currentSession: { type: Object, default: null },
});

const page = usePage();

// --- Filters ---
const educationType = ref(props.filters.education_type_id ?? '');
const stage = ref(props.filters.stage_id ?? '');

const filteredStages = computed(() =>
    educationType.value
        ? props.stages.filter((s) => s.education_type_id === Number(educationType.value))
        : props.stages
);

const loadGroups = () => {
    router.get(
        route('groups.index'),
        {
            loaded: 1,
            ...(educationType.value ? { education_type_id: educationType.value } : {}),
            ...(stage.value ? { stage_id: stage.value } : {}),
        },
        { preserveState: true }
    );
};

// --- Add group (now in a dialog opened by the header "+") ---
const creating = ref(false);
const openCreate = () => {
    addForm.clearErrors();
    creating.value = true;
};
// UI-only — `Group` has no `education_type_id` column, never sent in the
// payload. Only narrows the stage <select> below, same reasoning as the
// Flutter group form's own new education-type field.
const addEducationType = ref('');
const filteredAddStages = computed(() =>
    addEducationType.value
        ? props.stages.filter((s) => s.education_type_id === Number(addEducationType.value))
        : props.stages
);
const emptySlot = () => ({ day: DAYS[0], start_time: '', end_time: '' });
const addForm = useForm({ name: '', stage_id: '', slots: [emptySlot()] });
const submitAdd = () => {
    addForm.post(route('groups.store'), {
        preserveScroll: true,
        onSuccess: () => {
            addForm.reset();
            addForm.slots = [emptySlot()];
            addEducationType.value = '';
            creating.value = false;
        },
    });
};

// --- Edit group modal ---
const editing = ref(null);
const editEducationType = ref('');
const editForm = useForm({ name: '', stage_id: '', slots: [] });
const filteredEditGroupStages = computed(() =>
    editEducationType.value
        ? props.stages.filter((s) => s.education_type_id === Number(editEducationType.value))
        : props.stages
);
const openEdit = (group) => {
    editing.value = group;
    editForm.name = group.name;
    editForm.stage_id = group.stage?.id ?? '';
    // Derive the initial education type from the group's own stage — same
    // "derive from stored child" trick used by Tasks/Edit.vue and the
    // Flutter group form (Group itself doesn't store education_type_id).
    editEducationType.value = group.stage?.education_type_id ?? '';
    editForm.slots = group.slots.map((s) => ({
        day: s.day,
        start_time: s.start_time.slice(0, 5),
        end_time: s.end_time.slice(0, 5),
    }));
};
const submitEdit = () => {
    editForm.put(route('groups.update', editing.value.id), {
        preserveScroll: true,
        onSuccess: () => (editing.value = null),
    });
};

const destroyGroup = (group) => {
    if (confirm(t('groupsAdmin.deleteConfirm', { name: group.name }))) {
        router.delete(route('groups.destroy', group.id), { preserveScroll: true });
    }
};

// --- Expanded groups (a group row opens to show its doctors) ---
const expanded = ref({});
const toggleExpanded = (groupId) => {
    expanded.value = { ...expanded.value, [groupId]: !expanded.value[groupId] };
};

// --- Per-group doctor selection & search (the original's card controls) ---
const doctorSearch = ref({});
const selectedDoctors = ref({});

const visibleDoctors = (group) => {
    const term = (doctorSearch.value[group.id] ?? '').toLowerCase().trim();
    if (!term) return group.doctors;
    return group.doctors.filter(
        (d) => d.name.toLowerCase().includes(term) || (d.email ?? '').toLowerCase().includes(term)
    );
};

const selectionOf = (groupId) => selectedDoctors.value[groupId] ?? [];

const toggleDoctor = (groupId, doctorId) => {
    const current = selectionOf(groupId);
    selectedDoctors.value = {
        ...selectedDoctors.value,
        [groupId]: current.includes(doctorId) ? current.filter((id) => id !== doctorId) : [...current, doctorId],
    };
};

const toggleAllDoctors = (group) => {
    const visible = visibleDoctors(group).map((d) => d.id);
    const allSelected = visible.length > 0 && visible.every((id) => selectionOf(group.id).includes(id));
    selectedDoctors.value = { ...selectedDoctors.value, [group.id]: allSelected ? [] : visible };
};

const allDoctorsSelected = (group) => {
    const visible = visibleDoctors(group).map((d) => d.id);
    return visible.length > 0 && visible.every((id) => selectionOf(group.id).includes(id));
};

const removeSelectedDoctors = (group) => {
    const ids = selectionOf(group.id);
    if (!ids.length) return;
    if (confirm(t('groupsAdmin.removeSelectedConfirm', { n: ids.length, name: group.name }))) {
        router.delete(route('groups.doctors.remove', group.id), {
            data: { doctor_ids: ids },
            preserveScroll: true,
            onSuccess: () => (selectedDoctors.value = { ...selectedDoctors.value, [group.id]: [] }),
        });
    }
};

const removeDoctor = (group, doctor) => {
    router.delete(route('groups.doctors.remove', group.id), {
        data: { doctor_ids: [doctor.id] },
        preserveScroll: true,
    });
};

// --- Add doctors modal ---
const managing = ref(null);
const available = ref([]);
const toAdd = ref([]);
const loadingAvailable = ref(false);
const availableSearch = ref('');

const openAddDoctors = async (group) => {
    managing.value = group;
    toAdd.value = [];
    availableSearch.value = '';
    loadingAvailable.value = true;
    try {
        const { data } = await axios.get(route('groups.available-doctors'), {
            params: { stage_id: group.stage?.id },
        });
        available.value = data;
    } finally {
        loadingAvailable.value = false;
    }
};

const visibleAvailable = computed(() => {
    const term = availableSearch.value.toLowerCase().trim();
    if (!term) return available.value;
    return available.value.filter((d) => d.name.toLowerCase().includes(term));
});

const submitAddDoctors = () => {
    if (!toAdd.value.length) return;
    router.post(
        route('groups.doctors.add', managing.value.id),
        { doctor_ids: toAdd.value },
        { preserveScroll: true, onSuccess: () => (managing.value = null) }
    );
};
</script>

<template>
    <Head :title="t('groupsAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('groupsAdmin.title') }}</h2>
                <ChatAddButton :label="t('groupsAdmin.addGroupHeading')" @click="openCreate" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <StructureTabs active="groups" />

                <!-- Groups belong to an academic year; new groups are created
                     in the session shown here (switch it from the navbar). -->
                <div v-if="currentSession" class="flex">
                    <ChatChip icon="calendar_month" tone="indigo">{{ t('groupsAdmin.sessionBannerPrefix') }} <strong>{{ currentSession.name }}</strong></ChatChip>
                </div>

                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <!-- فلاتر -->
                <div class="flex flex-wrap items-center gap-2">
                    <select
                        v-model="educationType"
                        @change="stage = ''"
                        :title="t('groupsAdmin.educationTypeLabel')"
                        class="min-w-0 flex-1 rounded-full border-gray-200 bg-white text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">{{ t('groupsAdmin.chooseEducationType') }}</option>
                        <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                    </select>
                    <select
                        v-model="stage"
                        :title="t('groupsAdmin.stageLabel')"
                        class="min-w-0 flex-1 rounded-full border-gray-200 bg-white text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">{{ t('groupsAdmin.showAllGroups') }}</option>
                        <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>
                    <ChatAddButton icon="filter_list" :label="t('groupsAdmin.showGroups')" @click="loadGroups" />
                </div>

                <!-- Groups -->
                <ChatListCard
                    :empty="!loaded || groups.length === 0"
                    :empty-text="loaded ? t('groupsAdmin.noMatchingGroups') : t('groupsAdmin.chooseFiltersPrompt')"
                    :empty-icon="loaded ? 'groups' : 'filter_list'"
                >
                    <div v-for="group in groups" :key="group.id" class="border-b border-gray-100 last:border-b-0">
                        <ChatListRow
                            :title="group.name"
                            icon="groups"
                            :tone="toneFor(group.id)"
                            :selected="!!expanded[group.id]"
                            class="cursor-pointer"
                            @click="toggleExpanded(group.id)"
                        >
                            <template #meta>
                                <ChatChip icon="stairs" tone="indigo" :title="t('groupsAdmin.stageLabel')">{{ group.stage?.name ?? '—' }}</ChatChip>
                                <ChatChip icon="person" tone="emerald" :title="t('groupsAdmin.totalDoctors', { n: group.doctors.length })">{{ group.doctors.length }}</ChatChip>
                                <!-- Only the day count here; the days themselves show when the group is opened. -->
                                <ChatChip icon="schedule" :tone="group.slots.length ? 'amber' : 'gray'" :title="t('groupsAdmin.slotsLabel')">{{ group.slots.length }}</ChatChip>
                            </template>
                            <template #actions>
                                <div class="flex items-center" @click.stop>
                                    <ChatAction icon="person_add" :label="t('groupsAdmin.addDoctorsToGroup')" @click="openAddDoctors(group)" />
                                    <ChatAction icon="edit" :label="t('common.edit')" @click="openEdit(group)" />
                                    <ChatAction icon="delete" :label="t('common.delete')" danger @click="destroyGroup(group)" />
                                    <ChatAction
                                        :icon="expanded[group.id] ? 'expand_less' : 'expand_more'"
                                        :label="t('groupsAdmin.doctorsHeading')"
                                        @click="toggleExpanded(group.id)"
                                    />
                                </div>
                            </template>
                        </ChatListRow>

                        <!-- The group's doctors -->
                        <div v-if="expanded[group.id]" class="space-y-2 bg-gray-50/70 px-3 pb-3 pt-1 sm:px-4">
                            <div class="flex flex-wrap gap-1.5 pt-2">
                                <ChatChip v-for="slot in group.slots" :key="slot.id" icon="schedule" tone="amber">
                                    {{ slot.day }} <span dir="ltr">{{ slot.start_time.slice(0, 5) }}–{{ slot.end_time.slice(0, 5) }}</span>
                                </ChatChip>
                                <ChatChip v-if="group.slots.length === 0" icon="schedule" tone="gray">{{ t('groupsAdmin.noSlots') }}</ChatChip>
                            </div>
                            <template v-if="group.doctors.length">
                                <ChatSearch
                                    :model-value="doctorSearch[group.id] ?? ''"
                                    @update:model-value="doctorSearch = { ...doctorSearch, [group.id]: $event }"
                                    :placeholder="t('groupsAdmin.searchDoctorInGroupPlaceholder')"
                                />

                                <div class="flex items-center justify-between gap-2 px-1">
                                    <label class="flex items-center gap-2 text-sm font-medium text-gray-700">
                                        <input type="checkbox" :checked="allDoctorsSelected(group)" @change="toggleAllDoctors(group)" class="rounded border-gray-300 text-indigo-600" />
                                        {{ t('groupsAdmin.selectAll') }}
                                    </label>
                                    <button
                                        v-if="selectionOf(group.id).length > 0"
                                        type="button"
                                        @click="removeSelectedDoctors(group)"
                                        class="inline-flex items-center gap-1 rounded-full bg-red-50 px-3 py-1.5 text-xs font-medium text-red-700 hover:bg-red-100"
                                    >
                                        <Icon name="delete" size="text-[16px]" />{{ t('groupsAdmin.deleteSelectedWithCount', { n: selectionOf(group.id).length }) }}
                                    </button>
                                </div>

                                <ChatListCard
                                    :empty="visibleDoctors(group).length === 0"
                                    :empty-text="t('groupsAdmin.noMatchingDoctorsSearch')"
                                    empty-icon="person_search"
                                >
                                    <div class="max-h-96 overflow-y-auto">
                                    <ChatListRow
                                        v-for="doctor in visibleDoctors(group)"
                                        :key="doctor.id"
                                        :title="doctor.name"
                                        :subtitle="doctor.email"
                                        :tone="toneFor(doctor.id)"
                                        :selected="selectionOf(group.id).includes(doctor.id)"
                                    >
                                        <template #leading>
                                            <input
                                                type="checkbox"
                                                :checked="selectionOf(group.id).includes(doctor.id)"
                                                @change="toggleDoctor(group.id, doctor.id)"
                                                class="rounded border-gray-300 text-indigo-600"
                                            />
                                        </template>
                                        <template #actions>
                                            <ChatAction icon="insights" :label="t('groupsAdmin.progressLink')" :href="route('doctors.progress', doctor.id)" />
                                            <ChatAction icon="person_remove" :label="t('groupsAdmin.removeDoctor')" danger @click="removeDoctor(group, doctor)" />
                                        </template>
                                    </ChatListRow>
                                    </div>
                                </ChatListCard>
                            </template>

                            <div v-else class="flex flex-col items-center gap-2 py-6 text-center text-sm text-gray-500">
                                <Icon name="person_off" size="text-3xl" class="text-gray-300" />
                                {{ t('groupsAdmin.noDoctorsInGroup') }}
                            </div>
                        </div>
                    </div>
                </ChatListCard>
            </div>
        </div>

        <!-- إضافة مجموعة -->
        <Modal :show="creating" @close="creating = false" max-width="2xl">
            <form @submit.prevent="submitAdd" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('groupsAdmin.addGroupHeading') }}</h2>
                <div class="mt-4">
                    <InputLabel for="create-group-name" :value="t('groupsAdmin.groupNameLabel')" />
                    <TextInput id="create-group-name" v-model="addForm.name" type="text" :placeholder="t('groupsAdmin.groupNamePlaceholder')" class="mt-1 block w-full" required />
                    <InputError class="mt-1" :message="addForm.errors.name" />
                </div>
                <div class="mt-4">
                    <InputLabel :value="t('groupsAdmin.educationTypeLabel')" />
                    <select v-model="addEducationType" @change="addForm.stage_id = ''" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('groupsAdmin.chooseEducationTypeFirst') }}</option>
                        <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                    </select>
                </div>
                <div class="mt-4">
                    <InputLabel :value="t('groupsAdmin.stageLabel')" />
                    <select v-model="addForm.stage_id" :disabled="!addEducationType" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100" required>
                        <option value="">{{ t('groupsAdmin.chooseStage') }}</option>
                        <option v-for="s in filteredAddStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>
                    <InputError class="mt-1" :message="addForm.errors.stage_id" />
                </div>
                <div class="mt-4">
                    <InputLabel :value="t('groupsAdmin.slotsLabel')" />
                    <div v-for="(slot, i) in addForm.slots" :key="i" class="mt-2 flex flex-wrap items-center gap-2">
                        <select v-model="slot.day" class="w-32 rounded-md border-gray-300 text-sm shadow-sm">
                            <option v-for="d in DAYS" :key="d" :value="d">{{ d }}</option>
                        </select>
                        <input v-model="slot.start_time" type="time" class="rounded-md border-gray-300 text-sm shadow-sm" required />
                        <input v-model="slot.end_time" type="time" class="rounded-md border-gray-300 text-sm shadow-sm" required />
                        <ChatAction icon="close" :label="t('common.delete')" danger @click="addForm.slots.splice(i, 1)" />
                    </div>
                    <button type="button" @click="addForm.slots.push(emptySlot())" class="mt-2 inline-flex items-center gap-1 rounded-full bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200">
                        <Icon name="more_time" size="text-[16px]" />{{ t('groupsAdmin.addSlot') }}
                    </button>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="creating = false">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="addForm.processing">{{ t('groupsAdmin.addGroupButton') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

        <!-- تعديل المجموعة -->
        <Modal :show="editing !== null" @close="editing = null" max-width="2xl">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('groupsAdmin.editGroupTitle') }}</h2>
                <div class="mt-4">
                    <InputLabel :value="t('groupsAdmin.groupNameLabel')" />
                    <TextInput v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-1" :message="editForm.errors.name" />
                </div>
                <div class="mt-4">
                    <InputLabel :value="t('groupsAdmin.educationTypeLabel')" />
                    <select v-model="editEducationType" @change="editForm.stage_id = ''" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
                        <option value="">{{ t('groupsAdmin.chooseEducationType') }}</option>
                        <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                    </select>
                </div>
                <div class="mt-4">
                    <InputLabel :value="t('groupsAdmin.stageLabel')" />
                    <select v-model="editForm.stage_id" :disabled="!editEducationType" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm disabled:bg-gray-100" required>
                        <option v-for="s in filteredEditGroupStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>
                </div>
                <div class="mt-4">
                    <InputLabel :value="t('groupsAdmin.slotsLabel')" />
                    <div v-for="(slot, i) in editForm.slots" :key="i" class="mt-2 flex flex-wrap items-center gap-2">
                        <select v-model="slot.day" class="w-32 rounded-md border-gray-300 text-sm shadow-sm">
                            <option v-for="d in DAYS" :key="d" :value="d">{{ d }}</option>
                        </select>
                        <input v-model="slot.start_time" type="time" class="rounded-md border-gray-300 text-sm shadow-sm" required />
                        <input v-model="slot.end_time" type="time" class="rounded-md border-gray-300 text-sm shadow-sm" required />
                        <ChatAction icon="close" :label="t('common.delete')" danger @click="editForm.slots.splice(i, 1)" />
                    </div>
                    <button type="button" @click="editForm.slots.push(emptySlot())" class="mt-2 inline-flex items-center gap-1 rounded-full bg-gray-100 px-3 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-200">
                        <Icon name="more_time" size="text-[16px]" />{{ t('groupsAdmin.addSlot') }}
                    </button>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">{{ t('profile.save') }}</PrimaryButton>
                </div>
            </form>
        </Modal>

        <!-- إضافة أطباء للمجموعة -->
        <Modal :show="managing !== null" @close="managing = null">
            <div class="p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('groupsAdmin.addDoctorsModalTitle', { name: managing?.name }) }}</h2>
                <p class="mt-1 text-sm text-gray-500">
                    {{ t('groupsAdmin.addDoctorsModalDesc') }}
                </p>

                <ChatSearch v-model="availableSearch" :placeholder="t('groupsAdmin.searchPlaceholder')" class="mt-3" />

                <div class="mt-3 max-h-80 overflow-y-auto rounded-2xl ring-1 ring-gray-100">
                    <div v-if="loadingAvailable" class="p-4 text-center text-sm text-gray-500">{{ t('common.loading') }}</div>
                    <label v-for="doctor in visibleAvailable" :key="doctor.id" class="block cursor-pointer">
                        <ChatListRow :title="doctor.name" :tone="toneFor(doctor.id)" :selected="toAdd.includes(doctor.id)">
                            <template #leading>
                                <input type="checkbox" :value="doctor.id" v-model="toAdd" class="rounded border-gray-300 text-indigo-600" />
                            </template>
                        </ChatListRow>
                    </label>
                    <div v-if="!loadingAvailable && visibleAvailable.length === 0" class="flex flex-col items-center gap-2 p-6 text-center text-sm text-gray-400">
                        <Icon name="person_search" size="text-3xl" class="text-gray-300" />
                        {{ t('groupsAdmin.noAvailableDoctors') }}
                    </div>
                </div>

                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="managing = null">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="toAdd.length === 0" @click="submitAddDoctors">{{ t('groupsAdmin.addSelected') }}</PrimaryButton>
                </div>
            </div>
        </Modal>
    </AuthenticatedLayout>
</template>
