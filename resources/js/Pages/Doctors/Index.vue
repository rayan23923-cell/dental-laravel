<script setup>
/**
 * إدارة الأطباء — rebuilt to match dental_clinics2/admin/manage_doctors.php:
 * the same header actions (رفع ملف Excel / إضافة طبيب), the same filter row
 * (education type → cascading stage → search), the same selectable table
 * with a bulk bar ("تم تحديد N صف" + طباعة المحدد / حذف المحدد), and the
 * same columns.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
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
            <div class="flex flex-wrap items-center justify-between gap-2">
                <h2 class="text-xl font-semibold leading-tight text-gray-800"><Icon name="stethoscope" class="ml-1" />{{ t('doctorsAdmin.title') }}</h2>
                <div class="flex gap-2">
                    <Link :href="route('doctors.import.show')">
                        <SecondaryButton class="!bg-green-600 !text-white hover:!bg-green-700"><Icon name="table_view" class="ml-1" />{{ t('doctorsAdmin.importExcel') }}</SecondaryButton>
                    </Link>
                    <Link :href="route('doctors.create')">
                        <PrimaryButton><Icon name="add" class="ml-1" />{{ t('doctorsAdmin.addDoctor') }}</PrimaryButton>
                    </Link>
                </div>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-7xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs />

                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- Which academic year this list belongs to -->
                <div v-if="currentSession" class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-indigo-200 bg-indigo-50 p-3">
                    <span class="text-sm text-indigo-900">
                        <Icon name="calendar_month" class="ml-1" />
                        <template v-if="allSessions">{{ t('doctorsAdmin.viewingAllSessionsPrefix') }} <strong>{{ t('doctorsAdmin.allAcademicSessions') }}</strong></template>
                        <template v-else>{{ t('doctorsAdmin.sessionDoctorsPrefix') }} <strong>{{ currentSession.name }}</strong></template>
                    </span>
                    <label class="flex cursor-pointer items-center gap-2 text-sm text-indigo-900">
                        <input type="checkbox" v-model="allSessions" @change="applyFilters" class="rounded border-gray-300 text-indigo-600" />
                        {{ t('doctorsAdmin.showAllSessions') }}
                    </label>
                </div>

                <!-- Filters -->
                <div class="grid grid-cols-1 gap-3 rounded-lg bg-white p-4 shadow-sm md:grid-cols-4">
                    <select v-model="educationType" @change="onEducationTypeChange" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                        <option value="">{{ t('doctorsAdmin.filterByEducationType') }}</option>
                        <option v-for="et in educationTypes" :key="et.id" :value="et.id">{{ et.name }}</option>
                    </select>

                    <select v-model="stage" @change="applyFilters" :disabled="!educationType" class="rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100">
                        <option value="">{{ t('doctorsAdmin.filterByStage') }}</option>
                        <option v-for="s in filteredStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>

                    <div class="flex gap-2">
                        <TextInput v-model="search" type="text" :placeholder="t('doctorsAdmin.searchPlaceholder')" class="w-full" />
                        <SecondaryButton v-if="hasFilters" @click="clearFilters">✕</SecondaryButton>
                    </div>

                    <div class="flex gap-2">
                        <a :href="printFilteredUrl" target="_blank" class="flex flex-1 items-center justify-center rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-700">
                            <Icon name="print" class="ml-1" />{{ t('doctorsAdmin.printFiltered') }}
                        </a>
                        <a :href="exportUrl" class="flex items-center justify-center rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700" :title="t('doctorsAdmin.exportExcelTitle')">
                            <Icon name="table_view" />
                        </a>
                    </div>
                </div>

                <!-- Bulk bar -->
                <div v-if="selected.length" class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-amber-300 bg-amber-50 p-3">
                    <span class="text-sm text-gray-700"><Icon name="warning" class="ml-1" />{{ t('doctorsAdmin.selectedCount', { n: selected.length }) }}</span>
                    <div class="flex gap-2">
                        <a :href="printSelectedUrl" target="_blank" class="rounded-md bg-amber-500 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-600">
                            <Icon name="print" class="ml-1" />{{ t('doctorsAdmin.printSelected') }}
                        </a>
                        <button type="button" @click="destroySelected" class="rounded-md bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700">
                            <Icon name="delete" class="ml-1" />{{ t('doctorsAdmin.deleteSelected') }}
                        </button>
                    </div>
                </div>

                <!-- Table -->
                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <div class="overflow-x-auto">
                        <table class="min-w-full divide-y divide-gray-200">
                            <thead class="bg-gray-50">
                                <tr>
                                    <th class="px-4 py-3">
                                        <input type="checkbox" :checked="allOnPageSelected" @change="toggleAll" class="rounded border-gray-300" />
                                    </th>
                                    <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('profile.name') }}</th>
                                    <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('profile.email') }}</th>
                                    <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.educationTypeCol') }}</th>
                                    <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.stageCol') }}</th>
                                    <!-- Only meaningful when the session filter is lifted; otherwise
                                         every row carries the session named in the banner above. -->
                                    <th v-if="allSessions" class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.academicSessionCol') }}</th>
                                    <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">{{ t('doctorsAdmin.actionsCol') }}</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-200 bg-white">
                                <tr v-for="doctor in doctors.data" :key="doctor.id" :class="selected.includes(doctor.id) ? 'bg-indigo-50' : ''">
                                    <td class="px-4 py-4">
                                        <input type="checkbox" :value="doctor.id" v-model="selected" class="rounded border-gray-300" />
                                    </td>
                                    <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ doctor.name }}</td>
                                    <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ doctor.email }}</td>
                                    <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ doctor.education_type?.name ?? '—' }}</td>
                                    <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ doctor.stage?.name ?? '—' }}</td>
                                    <td v-if="allSessions" class="whitespace-nowrap px-6 py-4 text-sm">
                                        <span v-if="doctor.academic_session" class="rounded-full bg-indigo-100 px-2 py-0.5 text-xs font-medium text-indigo-800">
                                            {{ doctor.academic_session.name }}
                                        </span>
                                        <span v-else class="text-xs text-gray-400" :title="t('doctorsAdmin.showsInAllSessions')">{{ t('doctorsAdmin.unlinked') }}</span>
                                    </td>
                                    <td class="whitespace-nowrap px-6 py-4 text-sm">
                                        <Link
                                            v-if="['super_admin', 'admin'].includes(page.props.auth.user.role)"
                                            :href="route('doctors.progress', doctor.id)"
                                            class="text-gray-600 hover:text-gray-900"
                                        >
                                            {{ t('doctorsAdmin.progressLink') }}
                                        </Link>
                                        <a :href="route('doctors.card', doctor.id)" target="_blank" class="mr-3 text-gray-600 hover:text-gray-900" :title="t('doctorsAdmin.printCardTitle')">
                                            <Icon name="badge" />
                                        </a>
                                        <Link :href="route('doctors.edit', doctor.id)" class="mr-3 text-indigo-600 hover:text-indigo-900">{{ t('common.edit') }}</Link>
                                        <button @click="destroy(doctor)" class="mr-3 text-red-600 hover:text-red-900">{{ t('common.delete') }}</button>
                                    </td>
                                </tr>
                                <tr v-if="doctors.data.length === 0">
                                    <td :colspan="allSessions ? 7 : 6" class="px-6 py-8 text-center text-sm text-gray-500">{{ t('doctorsAdmin.emptyList') }}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>

                    <div class="flex flex-wrap justify-between gap-1 border-t border-gray-200 p-4">
                        <Link
                            v-for="link in doctors.links"
                            :key="link.label"
                            :href="link.url ?? ''"
                            v-html="link.label"
                            class="mx-1 rounded px-3 py-1 text-sm"
                            :class="{
                                'bg-indigo-600 text-white': link.active,
                                'text-gray-400 pointer-events-none': !link.url,
                                'text-gray-700 hover:bg-gray-100': link.url && !link.active,
                            }"
                        />
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
