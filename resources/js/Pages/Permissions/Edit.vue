<script setup>
/**
 * One account's permissions, as a settings list like clinic settings and
 * the profile (2026-10-14, by request): an account card on top, then
 * "نطاق الوصول" and "الصلاحيات" as collapsible rows with a coloured icon
 * and a one-line summary, switches instead of checkboxes, and a save bar
 * that stays on screen.
 *
 * Each module still offers only the actions it defines (see
 * App\Support\PermissionMatrix). An empty scope selection means the
 * account sees everything on that dimension (ScopeHelper's "zero rows =
 * unrestricted" rule), so "الكل" simply clears the selection. The scope
 * cascades: education type, then its stages, then their departments.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import SettingsSection from '@/Components/ChatList/SettingsSection.vue';
import SettingsToggle from '@/Components/ChatList/SettingsToggle.vue';
import { Head, Link, useForm, usePage } from '@inertiajs/vue3';
import { computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';

const { t, te } = useI18n();
const page = usePage();
const props = defineProps({
    targetUser: Object,
    modules: Array,
    granted: Array,
    // Option lists + the account's current selection for each of the four
    // scope dimensions (App\Services\ScopeHelper). `null` on any dimension
    // in `scope` means unrestricted.
    scopeOptions: Object,
    scope: Object,
});

const form = useForm({
    grants: [...props.granted],
    scope: {
        departments: props.scope.departments ? [...props.scope.departments] : [],
        stages: props.scope.stages ? [...props.scope.stages] : [],
        education_types: props.scope.educationTypes ? [...props.scope.educationTypes] : [],
        academic_sessions: props.scope.academicSessions ? [...props.scope.academicSessions] : [],
    },
});

// One row open at a time, like the settings page.
const open = reactive({});
const toggleOpen = (key, value) => {
    for (const k of Object.keys(open)) open[k] = false;
    open[key] = value;
};

// ── Access scope ──────────────────────────────────────────────────────
// A cascade (2026-10-14, by request): education types first, then only
// the stages of the chosen types, then only the departments of the chosen
// stages. Nothing picked on a level means "all of it" within the level
// above, and the server keeps the same rule (App\Services\ScopeHelper).
const opts = props.scopeOptions;
const typeName = (id) => opts.educationTypes.find((x) => x.id === id)?.name ?? t('permissionsAdmin.noType');
const stageName = (id) => opts.stages.find((x) => x.id === id)?.name ?? t('permissionsAdmin.noStage');
const stageType = (id) => opts.stages.find((x) => x.id === id)?.education_type_id;

const visibleStages = computed(() => {
    const types = form.scope.education_types;
    return types.length ? opts.stages.filter((s) => types.includes(s.education_type_id)) : opts.stages;
});
const visibleDepartments = computed(() => {
    const stages = form.scope.stages.length ? form.scope.stages : form.scope.education_types.length ? visibleStages.value.map((s) => s.id) : null;
    return stages ? opts.departments.filter((d) => stages.includes(d.stage_id)) : opts.departments;
});

const groupBy = (items, keyOf, nameOf) => {
    const groups = new Map();
    for (const item of items) {
        const k = keyOf(item) ?? 0;
        if (!groups.has(k)) groups.set(k, { title: nameOf(k), options: [] });
        groups.get(k).options.push(item);
    }
    return [...groups.values()];
};

const dimensions = computed(() => [
    { key: 'education_types', icon: 'school', tone: 'bg-amber-500', label: t('permissionsAdmin.educationTypesLabel'), options: opts.educationTypes, all: opts.educationTypes },
    {
        key: 'stages', icon: 'stairs', tone: 'bg-violet-500', label: t('permissionsAdmin.stagesLabel'), all: opts.stages,
        options: visibleStages.value,
        groups: groupBy(visibleStages.value, (s) => s.education_type_id, typeName),
        filteredBy: form.scope.education_types.length ? t('permissionsAdmin.filteredByTypes') : '',
    },
    {
        key: 'departments', icon: 'domain', tone: 'bg-sky-500', label: t('permissionsAdmin.departmentsLabel'), all: opts.departments,
        options: visibleDepartments.value,
        groups: groupBy(visibleDepartments.value, (d) => d.stage_id, (id) => {
            const type = stageType(id);
            return type ? `${stageName(id)} · ${typeName(type)}` : stageName(id);
        }),
        filteredBy: form.scope.stages.length ? t('permissionsAdmin.filteredByStages') : form.scope.education_types.length ? t('permissionsAdmin.filteredByTypes') : '',
    },
    { key: 'academic_sessions', icon: 'event', tone: 'bg-emerald-500', label: t('permissionsAdmin.academicSessionsLabel'), options: opts.academicSessions, all: opts.academicSessions },
]);

// Unticking a type or stage drops the stages and departments under it.
const prune = () => {
    const stageIds = visibleStages.value.map((s) => s.id);
    form.scope.stages = form.scope.stages.filter((id) => stageIds.includes(id));
    const deptIds = visibleDepartments.value.map((d) => d.id);
    form.scope.departments = form.scope.departments.filter((id) => deptIds.includes(id));
};

const scopeHas = (dimension, id) => form.scope[dimension].includes(id);
const setScope = (dimension, id, on) => {
    const list = form.scope[dimension].filter((i) => i !== id);
    form.scope[dimension] = on ? [...list, id] : list;
    prune();
};
const clearScope = (dimension) => {
    form.scope[dimension] = [];
    prune();
};

const scopeSummary = (dim) => {
    const ids = form.scope[dim.key];
    if (!ids.length) {
        return dim.filteredBy ? `${t('permissionsAdmin.unrestricted')} ${dim.filteredBy}` : t('permissionsAdmin.unrestricted');
    }
    return dim.all
        .filter((o) => ids.includes(o.id))
        .map((o) => (o.stage_name ? `${o.name} (${o.stage_name})` : o.name))
        .join('، ');
};

// ── Module permissions ────────────────────────────────────────────────
const moduleIcons = {
    dashboard: ['dashboard', 'bg-indigo-500'],
    users: ['manage_accounts', 'bg-blue-500'],
    doctors: ['stethoscope', 'bg-teal-500'],
    patients: ['personal_injury', 'bg-rose-500'],
    tasks: ['assignment', 'bg-orange-500'],
    groups: ['groups', 'bg-cyan-600'],
    clinic_chairs: ['chair', 'bg-lime-600'],
    stages: ['stairs', 'bg-violet-500'],
    education_types: ['school', 'bg-amber-500'],
    departments: ['domain', 'bg-sky-500'],
    task_progress: ['trending_up', 'bg-green-600'],
    patient_screening: ['fact_check', 'bg-pink-500'],
    reports: ['bar_chart', 'bg-fuchsia-500'],
    settings: ['settings', 'bg-gray-500'],
};
const iconOf = (module) => moduleIcons[module.key]?.[0] ?? 'shield';
const toneOf = (module) => moduleIcons[module.key]?.[1] ?? 'bg-slate-500';

const key = (module, permission) => `${module}.${permission}`;
const isChecked = (module, permission) => form.grants.includes(key(module, permission));
const setGrant = (module, permission, on) => {
    const k = key(module, permission);
    const rest = form.grants.filter((g) => g !== k);
    form.grants = on ? [...rest, k] : rest;
};

const allPairs = computed(() => props.modules.flatMap((m) => m.permissions.map((p) => key(m.key, p.key))));
const selectAll = () => (form.grants = [...allPairs.value]);
const clearAll = () => (form.grants = []);

const grantedIn = (module) => module.permissions.filter((p) => isChecked(module.key, p.key));
const moduleAll = (module) => grantedIn(module).length === module.permissions.length;
const setModule = (module, on) => {
    const pairs = module.permissions.map((p) => key(module.key, p.key));
    const rest = form.grants.filter((g) => !pairs.includes(g));
    form.grants = on ? [...rest, ...pairs] : rest;
};
const moduleSummary = (module) => {
    const granted = grantedIn(module);
    if (!granted.length) return t('permissionsAdmin.noAccess');
    if (granted.length === module.permissions.length) return t('permissionsAdmin.fullAccess');
    return granted.map((p) => p.label).join('، ');
};

const roleLabel = computed(() =>
    te(`roles.${props.targetUser.role}`) ? t(`roles.${props.targetUser.role}`) : props.targetUser.role,
);
const initial = computed(() => (props.targetUser.full_name || '?').trim().charAt(0));

const submit = () => {
    form.put(route('permissions.update', props.targetUser.id), { preserveScroll: true });
};
</script>

<template>
    <Head :title="t('permissionsAdmin.editTitle', { name: targetUser.full_name })" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-2">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('permissionsAdmin.title') }}</h2>
                <Link :href="route('permissions.index')" class="flex items-center gap-1 text-sm text-indigo-600 hover:underline">
                    {{ t('common.back') }}
                </Link>
            </div>
        </template>

        <div class="py-6 pb-28 sm:py-10 sm:pb-28">
            <div class="mx-auto max-w-3xl space-y-5 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- The account these permissions belong to -->
                <ChatListCard>
                    <div class="flex items-center gap-3 px-4 py-4">
                        <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-indigo-100 text-lg font-bold text-indigo-700">{{ initial }}</span>
                        <div class="min-w-0 flex-1">
                            <div class="truncate font-semibold text-gray-900">{{ targetUser.full_name }}</div>
                            <div class="truncate text-xs text-gray-500">{{ roleLabel }}</div>
                        </div>
                        <div class="text-center">
                            <div class="text-lg font-bold text-indigo-600" dir="ltr">{{ form.grants.length }}/{{ allPairs.length }}</div>
                            <div class="text-[11px] text-gray-500">{{ t('permissionsAdmin.grantedShort') }}</div>
                        </div>
                    </div>
                </ChatListCard>

                <form @submit.prevent="submit" class="space-y-5">
                    <!-- Access scope: which data the account sees at all -->
                    <section>
                        <h3 class="mb-2 px-2 text-xs font-semibold text-indigo-600">{{ t('permissionsAdmin.scopeTitle') }}</h3>
                        <ChatListCard>
                            <SettingsSection
                                v-for="dim in dimensions"
                                :key="dim.key"
                                :open="!!open['scope-' + dim.key]"
                                @update:open="toggleOpen('scope-' + dim.key, $event)"
                                :icon="dim.icon" :tone="dim.tone" :title="dim.label"
                                :summary="scopeSummary(dim)"
                            >
                                <button
                                    type="button"
                                    class="mb-2 flex w-full items-center gap-2 rounded-xl px-3 py-2 text-sm transition"
                                    :class="form.scope[dim.key].length ? 'bg-white text-gray-600 ring-1 ring-gray-200 hover:bg-gray-50' : 'bg-indigo-50 font-semibold text-indigo-700 ring-1 ring-indigo-200'"
                                    @click="clearScope(dim.key)"
                                >
                                    <Icon name="all_inclusive" size="text-[18px]" />
                                    <span class="flex-1 text-start">{{ t('permissionsAdmin.scopeAll') }}</span>
                                    <Icon v-if="!form.scope[dim.key].length" name="check_circle" size="text-[18px]" />
                                </button>
                                <p class="mb-2 px-1 text-xs text-gray-500">{{ dim.filteredBy ? t('permissionsAdmin.scopeHintFiltered', { level: dim.filteredBy }) : t('permissionsAdmin.scopeHint') }}</p>

                                <p v-if="!dim.options.length" class="px-1 py-2 text-xs text-gray-400">{{ t('permissionsAdmin.noOptionsAvailable') }}</p>

                                <template v-if="dim.groups && dim.groups.length > 1">
                                    <div v-for="group in dim.groups" :key="group.title" class="mb-3 last:mb-0">
                                        <div class="mb-1 px-1 text-xs font-semibold text-gray-500">{{ group.title }}</div>
                                        <div class="divide-y divide-gray-100 rounded-xl bg-white px-3 ring-1 ring-gray-100">
                                            <SettingsToggle
                                                v-for="opt in group.options"
                                                :key="opt.id"
                                                :label="opt.name"
                                                :model-value="scopeHas(dim.key, opt.id)"
                                                @update:model-value="setScope(dim.key, opt.id, $event)"
                                            />
                                        </div>
                                    </div>
                                </template>
                                <div v-else-if="dim.options.length" class="divide-y divide-gray-100 rounded-xl bg-white px-3 ring-1 ring-gray-100">
                                    <SettingsToggle
                                        v-for="opt in dim.options"
                                        :key="opt.id"
                                        :label="opt.name"
                                        :model-value="scopeHas(dim.key, opt.id)"
                                        @update:model-value="setScope(dim.key, opt.id, $event)"
                                    />
                                </div>
                            </SettingsSection>
                        </ChatListCard>
                    </section>

                    <!-- What the account may do, module by module -->
                    <section>
                        <div class="mb-2 flex items-center justify-between px-2">
                            <h3 class="text-xs font-semibold text-indigo-600">{{ t('permissionsAdmin.groupPermissions') }}</h3>
                            <div class="flex gap-3 text-xs">
                                <button type="button" class="text-indigo-600 hover:underline" @click="selectAll">{{ t('permissionsAdmin.selectAll') }}</button>
                                <button type="button" class="text-gray-500 hover:underline" @click="clearAll">{{ t('permissionsAdmin.clearAll') }}</button>
                            </div>
                        </div>
                        <ChatListCard>
                            <SettingsSection
                                v-for="module in modules"
                                :key="module.key"
                                :open="!!open['module-' + module.key]"
                                @update:open="toggleOpen('module-' + module.key, $event)"
                                :icon="iconOf(module)" :tone="toneOf(module)" :title="module.name"
                                :summary="moduleSummary(module)"
                            >
                                <div class="divide-y divide-gray-100 rounded-xl bg-white px-3 ring-1 ring-gray-100">
                                    <SettingsToggle
                                        :label="t('permissionsAdmin.allActions')"
                                        :model-value="moduleAll(module)"
                                        @update:model-value="setModule(module, $event)"
                                    />
                                    <SettingsToggle
                                        v-for="permission in module.permissions"
                                        :key="permission.key"
                                        :label="permission.label"
                                        :model-value="isChecked(module.key, permission.key)"
                                        @update:model-value="setGrant(module.key, permission.key, $event)"
                                    />
                                </div>
                            </SettingsSection>
                        </ChatListCard>
                    </section>

                    <div class="fixed inset-x-0 bottom-0 z-30 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur">
                        <div class="mx-auto flex max-w-3xl items-center gap-3">
                            <span class="flex-1 text-xs" :class="form.isDirty ? 'text-amber-600' : 'text-gray-400'">
                                {{ form.isDirty ? t('permissionsAdmin.unsavedChanges') : t('permissionsAdmin.allSaved') }}
                            </span>
                            <button v-if="form.isDirty" type="button" class="rounded-full px-4 py-2 text-sm text-gray-600 hover:bg-gray-100" @click="form.reset()">
                                {{ t('permissionsAdmin.discardChanges') }}
                            </button>
                            <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing || !form.isDirty"><Icon name="save" size="text-[18px]" />{{ t('permissionsAdmin.savePermissions') }}</PrimaryButton>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
