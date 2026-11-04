<script setup>
/**
 * "الربط بالنماذج" filter (2026-11-04, by request): link status pills,
 * then the linked case's stage and department chips, each with a count.
 * Used by the patients list and the payments page; the page owns the
 * values and reloads on `change`.
 */
import Icon from '@/Components/Icon.vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    facets: { type: Object, default: () => ({ statuses: {}, stages: [], departments: [] }) },
    link: { type: String, default: '' },
    stageId: { type: Number, default: null },
    departmentId: { type: Number, default: null },
});
const emit = defineEmits(['change']);

const linkStatuses = [
    { key: '', label: 'linkFilterAll', icon: 'select_all', count: 'all' },
    { key: 'linked', label: 'linkFilterLinked', icon: 'link', count: 'linked' },
    { key: 'unlinked', label: 'linkFilterUnlinked', icon: 'link_off', count: 'unlinked' },
    { key: 'suspicious', label: 'linkFilterSuspicious', icon: 'gpp_maybe', count: 'suspicious', danger: true },
    { key: 'attempts', label: 'linkFilterAttempts', icon: 'block', count: 'attempts' },
];

const setLink = (value) =>
    emit('change', value === 'unlinked' ? { link: value, stageId: null, departmentId: null } : { link: value, stageId: props.stageId, departmentId: props.departmentId });
const setStage = (id) =>
    emit('change', { link: props.link === 'unlinked' ? '' : props.link, stageId: props.stageId === id ? null : id, departmentId: props.departmentId });
const setDepartment = (id) =>
    emit('change', { link: props.link === 'unlinked' ? '' : props.link, stageId: props.stageId, departmentId: props.departmentId === id ? null : id });
</script>

<template>
    <div class="space-y-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
        <p class="flex items-center gap-1.5 text-sm font-semibold text-gray-700">
            <Icon name="account_tree" size="text-[18px]" />{{ t('patientReg.linkFilter') }}
        </p>
        <div class="flex flex-wrap gap-2">
            <button
                v-for="st in linkStatuses"
                :key="st.key"
                type="button"
                @click="setLink(st.key)"
                class="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-medium transition"
                :class="link === st.key
                    ? (st.danger ? 'bg-rose-600 text-white shadow-sm' : 'bg-indigo-600 text-white shadow-sm')
                    : (st.danger && facets.statuses?.[st.count] ? 'bg-rose-50 text-rose-700 ring-1 ring-rose-200 hover:bg-rose-100' : 'bg-gray-50 text-gray-700 ring-1 ring-gray-200 hover:bg-gray-100')"
            >
                <Icon :name="st.icon" size="text-[16px]" />{{ t('patientReg.' + st.label) }}
                <span
                    class="min-w-[1.5rem] rounded-full px-1.5 text-center text-xs"
                    :class="link === st.key ? 'bg-white/25' : 'bg-white ring-1 ring-gray-200'"
                >{{ facets.statuses?.[st.count] ?? 0 }}</span>
            </button>
        </div>
        <template v-if="link !== 'unlinked' && (facets.stages?.length || facets.departments?.length)">
            <div v-if="facets.stages?.length" class="flex items-start gap-2">
                <span class="mt-1.5 w-14 shrink-0 text-xs font-semibold text-gray-500">{{ t('patientReg.linkStage') }}</span>
                <div class="flex flex-1 flex-wrap gap-2">
                    <button
                        v-for="st in facets.stages"
                        :key="st.id"
                        type="button"
                        @click="setStage(st.id)"
                        class="inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-sm transition"
                        :class="stageId === st.id ? 'bg-emerald-600 text-white shadow-sm' : 'bg-emerald-50 text-emerald-800 ring-1 ring-emerald-200 hover:bg-emerald-100'"
                    >
                        <Icon name="school" size="text-[16px]" />{{ st.name }}
                        <span class="text-xs opacity-80">({{ st.count }})</span>
                    </button>
                </div>
            </div>
            <div v-if="facets.departments?.length" class="flex items-start gap-2">
                <span class="mt-1.5 w-14 shrink-0 text-xs font-semibold text-gray-500">{{ t('patientReg.linkDepartment') }}</span>
                <div class="flex flex-1 flex-wrap gap-2">
                    <button
                        v-for="d in facets.departments"
                        :key="d.id"
                        type="button"
                        @click="setDepartment(d.id)"
                        class="inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-sm transition"
                        :class="departmentId === d.id ? 'bg-sky-600 text-white shadow-sm' : 'bg-sky-50 text-sky-800 ring-1 ring-sky-200 hover:bg-sky-100'"
                    >
                        <Icon name="apartment" size="text-[16px]" />{{ d.name }}
                        <span class="text-xs opacity-80">({{ d.count }})</span>
                    </button>
                </div>
            </div>
        </template>
    </div>
</template>
