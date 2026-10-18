<script setup>
/**
 * The permissions editor (2026-10-14): "نطاق الوصول" and the module
 * permissions as collapsible settings rows with switches. Shared by the
 * permissions page and the add-user form, so both show the same list.
 *
 * It edits `form.grants` ("module.permission" pairs) and `form.scope` (the
 * four scope dimensions as id lists) of the Inertia form it is given.
 * Each module offers only the actions it defines (App\Support\PermissionMatrix).
 * On the top levels (education types, academic sessions) nothing picked
 * means the account sees nothing; "الكل" is its own choice, kept in
 * `form.scope.all_education_types` / `all_academic_sessions` (2026-10-18,
 * by request). The scope cascades: education type, then its stages, then
 * their departments; stages and departments with nothing picked follow the
 * level above.
 */
import Icon from '@/Components/Icon.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import SettingsSection from '@/Components/ChatList/SettingsSection.vue';
import SettingsToggle from '@/Components/ChatList/SettingsToggle.vue';
import { computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    // useForm() with `grants` and `scope` keys; edited in place.
    form: Object,
    modules: Array,
    scopeOptions: Object,
});
const form = props.form;

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
    { key: 'education_types', top: true, icon: 'school', tone: 'bg-amber-500', label: t('permissionsAdmin.educationTypesLabel'), options: opts.educationTypes, all: opts.educationTypes },
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
    { key: 'academic_sessions', top: true, icon: 'event', tone: 'bg-emerald-500', label: t('permissionsAdmin.academicSessionsLabel'), options: opts.academicSessions, all: opts.academicSessions },
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
    if (on && form.scope['all_' + dimension] !== undefined) form.scope['all_' + dimension] = false;
    prune();
};
// "الكل" on a top level toggles; on a lower level it clears the picks so
// the level follows the one above.
const scopeAllOn = (dim) => !form.scope[dim.key].length && (!dim.top || form.scope['all_' + dim.key]);
const clearScope = (dim) => {
    const wasOn = scopeAllOn(dim);
    form.scope[dim.key] = [];
    if (dim.top) form.scope['all_' + dim.key] = !wasOn;
    prune();
};
// Nothing picked on the types and no "الكل": nothing below shows either.
const typesNone = computed(() => !form.scope.education_types.length && !form.scope.all_education_types);

const scopeSummary = (dim) => {
    const ids = form.scope[dim.key];
    if (!ids.length) {
        if (dim.top ? !form.scope['all_' + dim.key] : typesNone.value && !form.scope.stages.length) {
            return t('permissionsAdmin.scopeNone');
        }
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
    stages: ['stairs', 'bg-violet-500'],
    education_types: ['school', 'bg-amber-500'],
    departments: ['domain', 'bg-sky-500'],
    case_sheet_types: ['description', 'bg-slate-600'],
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
</script>

<template>
    <div class="space-y-5">
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
                        :class="!scopeAllOn(dim) ? 'bg-white text-gray-600 ring-1 ring-gray-200 hover:bg-gray-50' : 'bg-indigo-50 font-semibold text-indigo-700 ring-1 ring-indigo-200'"
                        @click="clearScope(dim)"
                    >
                        <Icon name="all_inclusive" size="text-[18px]" />
                        <span class="flex-1 text-start">{{ t('permissionsAdmin.scopeAll') }}</span>
                        <Icon v-if="scopeAllOn(dim)" name="check_circle" size="text-[18px]" />
                    </button>
                    <p class="mb-2 px-1 text-xs text-gray-500">{{ dim.top ? t('permissionsAdmin.scopeHintTop') : dim.filteredBy ? t('permissionsAdmin.scopeHintFiltered', { level: dim.filteredBy }) : t('permissionsAdmin.scopeHint') }}</p>

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
    </div>
</template>
