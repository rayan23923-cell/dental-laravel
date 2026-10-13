<script setup>
/**
 * إدارة الأطباء — rebuilt to match dental_clinics2/admin/manage_doctors.php:
 * the same header actions (رفع ملف Excel / إضافة طبيب), the same filter row
 * (education type → cascading stage → search), the same selectable table
 * with a bulk bar ("تم تحديد N صف" + طباعة المحدد / حذف المحدد), and the
 * same columns.
 *
 * Chat-list style (2026-10-13, by request): the table became chat-list
 * rows (checkbox, avatar initial, name + email, chips) with icon actions.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import ChatPager from '@/Components/ChatList/ChatPager.vue';
import { toneFor } from '@/Components/ChatList/tones';
import { Head, router, usePage } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';
import StructureTabs from '@/Components/StructureTabs.vue';

const { t } = useI18n();
const props = defineProps({
    doctors: Object,
    educationTypes: Array,
    stages: Array,
    filters: Object,
    currentSession: { type: Object, default: null },
    allSessions: { type: Boolean, default: false },
});

const page = usePage();

const search = ref(props.filters.search ?? '');
const educationType = ref(props.filters.education_type_id ?? '');
const stage = ref(props.filters.stage_id ?? '');

// Doctors are enrolled per academic session, so the list shows the session
// being worked in. This toggle lifts that filter to review past intakes
// without switching the whole app's session in the navbar.
const allSessions = ref(props.allSessions);

// Stage list cascades off the selected education type, as in the original
// (its #filter-stage is disabled until an education type is chosen).
const filteredStages = computed(() =>
    educationType.value
        ? props.stages.filter((s) => s.education_type_id === Number(educationType.value))
        : props.stages
);

const applyFilters = () => {
    router.get(
        route('doctors.index'),
        {
            ...(search.value ? { search: search.value } : {}),
            ...(educationType.value ? { education_type_id: educationType.value } : {}),
            ...(stage.value ? { stage_id: stage.value } : {}),
            ...(allSessions.value ? { all_sessions: 1 } : {}),
        },
        { preserveState: true, replace: true }
    );
};

let searchTimer;
watch(search, () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(applyFilters, 300);
});

const onEducationTypeChange = () => {
    stage.value = '';
    applyFilters();
};

const clearFilters = () => {
    search.value = '';
    educationType.value = '';
    stage.value = '';
    allSessions.value = false;
    router.get(route('doctors.index'));
};

const hasFilters = computed(() => !!(search.value || educationType.value || stage.value));

// --- Selection ---
const selected = ref([]);
const allOnPageSelected = computed(
    () => props.doctors.data.length > 0 && selected.value.length === props.doctors.data.length
);
const toggleAll = () => {
    selected.value = allOnPageSelected.value ? [] : props.doctors.data.map((d) => d.id);
};

const canSeeProgress = computed(() => ['super_admin', 'admin'].includes(page.props.auth.user.role));

const destroy = (doctor) => {
    if (confirm(t('doctorsAdmin.deleteConfirm', { name: doctor.name }))) {
        router.delete(route('doctors.destroy', doctor.id), { preserveScroll: true });
    }
};

const destroySelected = () => {
    if (!selected.value.length) return;
    if (confirm(t('doctorsAdmin.deleteSelectedConfirm', { n: selected.value.length }))) {
        router.delete(route('doctors.destroy-many'), {
            data: { ids: selected.value },
            preserveScroll: true,
            onSuccess: () => (selected.value = []),
        });
    }
};

// Current filters as query params — shared by the Excel export and the
// printable roster ("طباعة الفلتر" in the original).
const filterParams = computed(() => {
    const params = new URLSearchParams();
    if (search.value) params.set('search', search.value);
    if (educationType.value) params.set('education_type_id', educationType.value);
    if (stage.value) params.set('stage_id', stage.value);
    if (allSessions.value) params.set('all_sessions', '1');
    return params;
});

const exportUrl = computed(() => `${route('doctors.export')}?${filterParams.value.toString()}`);
const printFilteredUrl = computed(() => `${route('doctors.print')}?${filterParams.value.toString()}`);

// "طباعة المحدد" — the same roster endpoint, restricted to the ticked rows.
const printSelectedUrl = computed(() => `${route('doctors.print')}?ids=${selected.value.join(',')}`);
</script>

<template>
    <Head :title="t('doctorsAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('doctorsAdmin.title') }}</h2>
                <div class="flex items-center gap-2">
                    <ChatAddButton :label="t('doctorsAdmin.importExcel')" icon="upload_file" secondary :href="route('doctors.import.show')" />
                    <ChatAddButton :label="t('doctorsAdmin.addDoctor')" :href="route('doctors.create')" />
                </div>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <StructureTabs />

                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- Which academic year this list belongs to -->
                <div v-if="currentSession" class="flex flex-wrap items-center justify-between gap-2 rounded-2xl bg-indigo-50 px-4 py-2.5 text-sm text-indigo-900">
                    <span class="flex items-center gap-1.5">
                        <Icon name="calendar_month" size="text-[18px]" />
                        <template v-if="allSessions">{{ t('doctorsAdmin.viewingAllSessionsPrefix') }} <strong>{{ t('doctorsAdmin.allAcademicSessions') }}</strong></template>
                        <template v-else>{{ t('doctorsAdmin.sessionDoctorsPrefix') }} <strong>{{ currentSession.name }}</strong></template>
                    </span>
                    <label class="flex cursor-pointer items-center gap-2">
                        <input type="checkbox" v-model="allSessions" @change="applyFilters" class="rounded border-gray-300 text-indigo-600" />
                        {{ t('doctorsAdmin.showAllSessions') }}
                    </label>
                </div>

                <ChatSearch v-model="search" :placeholder="t('doctorsAdmin.searchPlaceholder')" @submit="applyFilters" />

                <!-- Filters (education type → cascading stage) + print/export -->
                <div class="flex flex-wrap items-center gap-2">
                    <select v-model="educationType" @change="onEducationTypeChange" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('doctorsAdmin.filterByEducationType') }}</option>
                        <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                    </select>
                    <select v-model="stage" @change="applyFilters" :disabled="!educationType" class="rounded-full border-gray-200 bg-white py-1.5 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100 disabled:text-gray-400">
                        <option value="">{{ t('doctorsAdmin.filterByStage') }}</option>
                        <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>
                    <ChatAction v-if="hasFilters" icon="filter_alt_off" :label="t('taskProgressAdmin.clearFilters')" @click="clearFilters" />
                    <div class="ms-auto flex items-center">
                        <ChatAction icon="print" :label="t('doctorsAdmin.printFiltered')" :href="printFilteredUrl" external />
                        <a :href="exportUrl" :title="t('doctorsAdmin.exportExcelTitle')" class="inline-flex h-9 w-9 items-center justify-center rounded-full text-emerald-600 transition hover:bg-emerald-50">
                            <Icon name="table_view" size="text-[20px]" :label="t('doctorsAdmin.exportExcelTitle')" />
                        </a>
                    </div>
                </div>

                <!-- Bulk bar -->
                <div v-if="selected.length" class="flex items-center justify-between gap-2 rounded-2xl bg-amber-50 px-4 py-2 ring-1 ring-amber-200">
                    <span class="text-sm font-medium text-amber-900">{{ t('doctorsAdmin.selectedCount', { n: selected.length }) }}</span>
                    <div class="flex items-center">
                        <ChatAction icon="print" :label="t('doctorsAdmin.printSelected')" :href="printSelectedUrl" external />
                        <ChatAction icon="delete" :label="t('doctorsAdmin.deleteSelected')" danger @click="destroySelected" />
                    </div>
                </div>

                <ChatListCard :empty="doctors.data.length === 0" :empty-text="t('doctorsAdmin.emptyList')" empty-icon="stethoscope">
                    <label v-if="doctors.data.length" class="flex cursor-pointer items-center gap-3 border-b border-gray-100 px-4 py-2 text-xs font-medium text-gray-500">
                        <input type="checkbox" :checked="allOnPageSelected" @change="toggleAll" class="rounded border-gray-300 text-indigo-600" />
                        {{ t('groupsAdmin.selectAll') }}
                    </label>
                    <ChatListRow
                        v-for="doctor in doctors.data"
                        :key="doctor.id"
                        :title="doctor.name"
                        :subtitle="doctor.email"
                        :tone="toneFor(doctor.id)"
                        :selected="selected.includes(doctor.id)"
                    >
                        <template #leading>
                            <input type="checkbox" :value="doctor.id" v-model="selected" class="rounded border-gray-300 text-indigo-600" />
                        </template>
                        <template #meta>
                            <ChatChip v-if="doctor.education_type" icon="school" tone="sky">{{ doctor.education_type.name }}</ChatChip>
                            <ChatChip v-if="doctor.stage" icon="stairs" tone="indigo">{{ doctor.stage.name }}</ChatChip>
                            <!-- Only meaningful when the session filter is lifted; otherwise
                                 every row carries the session named in the banner above. -->
                            <template v-if="allSessions">
                                <ChatChip v-if="doctor.academic_session" icon="calendar_month" tone="violet">{{ doctor.academic_session.name }}</ChatChip>
                                <ChatChip v-else icon="link_off" :title="t('doctorsAdmin.showsInAllSessions')">{{ t('doctorsAdmin.unlinked') }}</ChatChip>
                            </template>
                        </template>
                        <template #actions>
                            <ChatAction v-if="canSeeProgress" icon="trending_up" :label="t('doctorsAdmin.progressLink')" :href="route('doctors.progress', doctor.id)" />
                            <ChatAction icon="badge" :label="t('doctorsAdmin.printCardTitle')" :href="route('doctors.card', doctor.id)" external />
                            <ChatAction icon="edit" :label="t('common.edit')" :href="route('doctors.edit', doctor.id)" />
                            <ChatAction icon="delete" :label="t('common.delete')" danger @click="destroy(doctor)" />
                        </template>
                    </ChatListRow>
                    <template #footer>
                        <ChatPager :links="doctors.links" />
                    </template>
                </ChatListCard>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
