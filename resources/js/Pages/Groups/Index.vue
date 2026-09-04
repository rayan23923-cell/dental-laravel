<script setup>
/**
 * إدارة المجموعات — rebuilt to match dental_clinics2/admin/manage_groups.php
 * and its load_groups.php card renderer: the same filter row
 * (نوع الدراسة → المرحلة → عرض المجموعات), the same inline add-group form
 * with repeatable day/time slot rows, and the same group card — slots list,
 * per-group doctor search, "تحديد الكل", bulk "حذف المحدد (N)", per-doctor
 * remove, doctor total, and the "إضافة أطباء للمجموعة" modal.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import StructureTabs from '@/Components/StructureTabs.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, router, useForm, usePage } from '@inertiajs/vue3';
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

// --- Add group (inline form, as in the original) ---
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
            <h2 class="text-xl font-semibold leading-tight text-gray-800"><Icon name="groups" class="ml-1" />{{ t('groupsAdmin.title') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-6xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs active="groups" />

                <!-- Groups belong to an academic year; new groups are created
                     in the session shown here (switch it from the navbar). -->
                <div v-if="currentSession" class="rounded-lg border border-indigo-200 bg-indigo-50 p-3 text-sm text-indigo-900">
                    <Icon name="calendar_month" class="ml-1" />
                    {{ t('groupsAdmin.sessionBannerPrefix') }} <strong>{{ currentSession.name }}</strong>
                </div>

                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-md bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <!-- فلاتر -->
                <div class="grid grid-cols-1 gap-3 rounded-lg bg-white p-4 shadow-sm md:grid-cols-3">
                    <div>
                        <InputLabel :value="t('groupsAdmin.educationTypeLabel')" />
                        <select v-model="educationType" @change="stage = ''" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                            <option value="">{{ t('groupsAdmin.chooseEducationType') }}</option>
                            <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                        </select>
                    </div>
                    <div>
                        <InputLabel :value="t('groupsAdmin.stageLabel')" />
                        <select v-model="stage" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                            <option value="">{{ t('groupsAdmin.showAllGroups') }}</option>
                            <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                        </select>
                    </div>
                    <div class="flex items-end">
                        <PrimaryButton class="w-full justify-center" @click="loadGroups">{{ t('groupsAdmin.showGroups') }}</PrimaryButton>
                    </div>
                </div>

                <!-- نموذج إضافة مجموعة -->
                <form @submit.prevent="submitAdd" class="space-y-3 rounded-lg bg-white p-4 shadow-sm">
                    <h3 class="text-sm font-semibold text-gray-700">{{ t('groupsAdmin.addGroupHeading') }}</h3>
                    <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
                        <div>
                            <TextInput v-model="addForm.name" type="text" :placeholder="t('groupsAdmin.groupNamePlaceholder')" class="block w-full" required />
                            <InputError class="mt-1" :message="addForm.errors.name" />
                        </div>
                        <div>
                            <select v-model="addEducationType" @change="addForm.stage_id = ''" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                <option value="">{{ t('groupsAdmin.chooseEducationTypeFirst') }}</option>
                                <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                            </select>
                        </div>
                        <div>
                            <select v-model="addForm.stage_id" :disabled="!addEducationType" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100" required>
                                <option value="">{{ t('groupsAdmin.chooseStage') }}</option>
                                <option v-for="s in filteredAddStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                            </select>
                            <InputError class="mt-1" :message="addForm.errors.stage_id" />
                        </div>
                    </div>

                    <div>
                        <InputLabel :value="t('groupsAdmin.slotsLabel')" />
                        <div v-for="(slot, i) in addForm.slots" :key="i" class="mt-2 flex flex-wrap items-center gap-2">
                            <select v-model="slot.day" class="w-32 rounded-md border-gray-300 text-sm shadow-sm">
                                <option v-for="d in DAYS" :key="d" :value="d">{{ d }}</option>
                            </select>
                            <input v-model="slot.start_time" type="time" class="rounded-md border-gray-300 text-sm shadow-sm" required />
                            <input v-model="slot.end_time" type="time" class="rounded-md border-gray-300 text-sm shadow-sm" required />
                            <button type="button" @click="addForm.slots.splice(i, 1)" class="rounded bg-red-500 px-2 py-1 text-white hover:bg-red-600">×</button>
                        </div>
                        <button type="button" @click="addForm.slots.push(emptySlot())" class="mt-2 rounded bg-gray-500 px-3 py-1 text-xs text-white hover:bg-gray-600">
                            {{ t('groupsAdmin.addSlot') }}
                        </button>
                    </div>

                    <button type="submit" :disabled="addForm.processing" class="rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700">
                        {{ t('groupsAdmin.addGroupButton') }}
                    </button>
                </form>

                <!-- Groups -->
                <div v-if="!loaded" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                    {{ t('groupsAdmin.chooseFiltersPrompt') }}
                </div>
                <div v-else-if="groups.length === 0" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                    {{ t('groupsAdmin.noMatchingGroups') }}
                </div>

                <div v-for="group in groups" :key="group.id" class="overflow-hidden rounded-lg bg-white shadow-sm">
                    <div class="flex flex-wrap items-center justify-between gap-2 border-b border-gray-200 bg-gray-50 px-4 py-3">
                        <strong class="text-gray-900">{{ group.name }} ({{ group.stage?.name ?? '—' }})</strong>
                        <div class="flex gap-2">
                            <button @click="openEdit(group)" class="rounded bg-indigo-600 px-3 py-1 text-xs text-white hover:bg-indigo-700">{{ t('common.edit') }}</button>
                            <button @click="destroyGroup(group)" class="rounded bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-700">{{ t('common.delete') }}</button>
                        </div>
                    </div>

                    <div class="p-4">
                        <h4 class="text-sm font-semibold text-gray-700">{{ t('groupsAdmin.daysAndTimesHeading') }}</h4>
                        <ul class="mt-1 list-inside list-disc text-sm text-gray-600">
                            <li v-for="slot in group.slots" :key="slot.id">
                                {{ t('groupsAdmin.slotLine', { day: slot.day, start: slot.start_time.slice(0, 5), end: slot.end_time.slice(0, 5) }) }}
                            </li>
                            <li v-if="group.slots.length === 0" class="list-none text-gray-400">{{ t('groupsAdmin.noSlots') }}</li>
                        </ul>

                        <h4 class="mt-4 text-sm font-semibold text-gray-700">{{ t('groupsAdmin.doctorsHeading') }}</h4>

                        <template v-if="group.doctors.length">
                            <div class="mt-2 flex flex-wrap gap-2">
                                <TextInput
                                    :model-value="doctorSearch[group.id] ?? ''"
                                    @update:model-value="doctorSearch = { ...doctorSearch, [group.id]: $event }"
                                    type="text"
                                    :placeholder="t('groupsAdmin.searchDoctorInGroupPlaceholder')"
                                    class="min-w-0 flex-grow text-sm"
                                />
                                <button
                                    type="button"
                                    :disabled="selectionOf(group.id).length === 0"
                                    @click="removeSelectedDoctors(group)"
                                    class="whitespace-nowrap rounded bg-red-600 px-3 py-1.5 text-xs text-white hover:bg-red-700 disabled:opacity-40"
                                >
                                    <Icon name="delete" class="ml-1" />{{ t('groupsAdmin.deleteSelectedWithCount', { n: selectionOf(group.id).length }) }}
                                </button>
                            </div>

                            <label class="mt-2 flex items-center gap-2 rounded border border-gray-200 bg-gray-50 p-2 text-sm font-bold text-gray-700">
                                <input type="checkbox" :checked="allDoctorsSelected(group)" @change="toggleAllDoctors(group)" class="rounded border-gray-300" />
                                {{ t('groupsAdmin.selectAll') }}
                            </label>

                            <ul class="mt-2 max-h-72 divide-y divide-gray-200 overflow-y-auto rounded border border-gray-200">
                                <li v-for="doctor in visibleDoctors(group)" :key="doctor.id" class="flex items-center justify-between gap-3 p-2">
                                    <label class="flex flex-grow items-center gap-3">
                                        <input
                                            type="checkbox"
                                            :checked="selectionOf(group.id).includes(doctor.id)"
                                            @change="toggleDoctor(group.id, doctor.id)"
                                            class="rounded border-gray-300"
                                        />
                                        <span>
                                            <span class="block text-sm font-bold text-gray-900">{{ doctor.name }}</span>
                                            <span class="block text-xs text-gray-500">{{ doctor.email }}</span>
                                        </span>
                                    </label>
                                    <span class="flex shrink-0 gap-2 text-xs">
                                        <Link :href="route('doctors.progress', doctor.id)" class="text-gray-500 hover:text-gray-800">{{ t('groupsAdmin.progressLink') }}</Link>
                                        <button @click="removeDoctor(group, doctor)" class="text-red-600 hover:text-red-800">{{ t('groupsAdmin.removeDoctor') }}</button>
                                    </span>
                                </li>
                                <li v-if="visibleDoctors(group).length === 0" class="p-3 text-center text-sm text-gray-500">
                                    {{ t('groupsAdmin.noMatchingDoctorsSearch') }}
                                </li>
                            </ul>

                            <p class="mt-1 text-xs text-gray-500">{{ t('groupsAdmin.totalDoctors', { n: group.doctors.length }) }}</p>
                        </template>

                        <div v-else class="mt-2 rounded-md bg-blue-50 p-3 text-sm text-blue-700">
                            {{ t('groupsAdmin.noDoctorsInGroup') }}
                        </div>

                        <button type="button" @click="openAddDoctors(group)" class="mt-3 rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700">
                            <Icon name="person" class="ml-1" /><Icon name="add" class="ml-1" />{{ t('groupsAdmin.addDoctorsToGroup') }}
                        </button>
                    </div>
                </div>
            </div>
        </div>

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
                        <button type="button" @click="editForm.slots.splice(i, 1)" class="rounded bg-red-500 px-2 py-1 text-white hover:bg-red-600">×</button>
                    </div>
                    <button type="button" @click="editForm.slots.push(emptySlot())" class="mt-2 rounded bg-gray-500 px-3 py-1 text-xs text-white hover:bg-gray-600">
                        {{ t('groupsAdmin.addSlot') }}
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

                <TextInput v-model="availableSearch" type="text" :placeholder="t('groupsAdmin.searchPlaceholder')" class="mt-3 block w-full text-sm" />

                <div class="mt-3 max-h-72 space-y-1 overflow-y-auto">
                    <div v-if="loadingAvailable" class="text-sm text-gray-500">{{ t('common.loading') }}</div>
                    <label v-for="doctor in visibleAvailable" :key="doctor.id" class="flex items-center gap-2 rounded px-2 py-1 text-sm hover:bg-gray-50">
                        <input type="checkbox" :value="doctor.id" v-model="toAdd" class="rounded border-gray-300" />
                        {{ doctor.name }}
                    </label>
                    <div v-if="!loadingAvailable && visibleAvailable.length === 0" class="text-sm text-gray-400">
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
