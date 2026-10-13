<script setup>
/**
 * Permission matrix — one card per module, each rendering only the actions
 * that module actually defines (see App\Support\PermissionMatrix). The
 * previous version drew a uniform 5-column grid, which both offered grants
 * the original never had and hid the ones it does (tasks.assign,
 * task_progress.start/finish/open_case_sheet, reports.print …).
 *
 * "تحديد الكل" / "إلغاء الكل" mirror the original's selectAllPermissions()
 * controls on its permissions modal.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t, te } = useI18n();
const props = defineProps({
    targetUser: Object,
    modules: Array,
    granted: Array,
    // Option lists + the account's current selection for each of the four
    // scope dimensions (App\Services\ScopeHelper). `null` on any dimension
    // in `scope` means unrestricted — matches ScopeHelper's own "zero rows
    // = sees everything" rule, not "nothing selected".
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

// Whether each dimension currently restricts the account at all — read from
// the *server's* answer (props.scope), not the live form state, so this
// stays accurate even before the admin has touched anything on this page.
const isRestricted = computed(() => ({
    departments: props.scope.departments !== null,
    stages: props.scope.stages !== null,
    education_types: props.scope.educationTypes !== null,
    academic_sessions: props.scope.academicSessions !== null,
}));

const toggleScopeId = (dimension, id) => {
    const list = form.scope[dimension];
    form.scope[dimension] = list.includes(id) ? list.filter((i) => i !== id) : [...list, id];
};

const clearScope = (dimension) => {
    form.scope[dimension] = [];
};

const key = (module, permission) => `${module}.${permission}`;

const isChecked = (module, permission) => form.grants.includes(key(module, permission));

const toggle = (module, permission) => {
    const k = key(module, permission);
    form.grants = form.grants.includes(k) ? form.grants.filter((g) => g !== k) : [...form.grants, k];
};

const allPairs = computed(() =>
    props.modules.flatMap((m) => m.permissions.map((p) => key(m.key, p.key)))
);

const selectAll = () => (form.grants = [...allPairs.value]);
const clearAll = () => (form.grants = []);

const moduleAllChecked = (module) => module.permissions.every((p) => isChecked(module.key, p.key));

const toggleModule = (module) => {
    const pairs = module.permissions.map((p) => key(module.key, p.key));
    form.grants = moduleAllChecked(module)
        ? form.grants.filter((g) => !pairs.includes(g))
        : [...new Set([...form.grants, ...pairs])];
};

const submit = () => {
    form.put(route('permissions.update', props.targetUser.id));
};
</script>

<template>
    <Head :title="t('permissionsAdmin.editTitle', { name: targetUser.full_name })" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex flex-wrap items-center justify-between gap-2">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">
                    {{ t('permissionsAdmin.editTitle', { name: targetUser.full_name }) }}
                    <span class="mr-2 rounded-full bg-gray-100 px-2 py-0.5 text-xs font-normal text-gray-600">{{ te(`roles.${targetUser.role}`) ? t(`roles.${targetUser.role}`) : targetUser.role }}</span>
                </h2>
                <Link :href="route('permissions.index')" class="text-sm text-indigo-600 hover:underline">{{ t('common.back') }}</Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-4 sm:px-6 lg:px-8">
                <div class="flex flex-wrap items-center justify-end gap-2 rounded-lg bg-white p-4 shadow-sm">
                    <!-- Explanatory notes removed (2026-10-13, by request). -->
                    <div class="flex gap-2">
                        <SecondaryButton @click="selectAll">{{ t('permissionsAdmin.selectAll') }}</SecondaryButton>
                        <SecondaryButton @click="clearAll">{{ t('permissionsAdmin.clearAll') }}</SecondaryButton>
                    </div>
                </div>

                <form @submit.prevent="submit" class="space-y-3">
                    <!-- نطاق الوصول — يقيّد أي بيانات يرى هذا الحساب أصلاً
                         (أقسام/مراحل/أنواع تعليم/أعوام دراسية)، بمعزل عن
                         الإجراءات المسموحة أدناه. فارغ = بلا قيد (يرى كل
                         شيء) — نفس قاعدة ScopeHelper. -->
                    <div class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <div class="border-b border-gray-100 bg-gray-50 px-4 py-3">
                            <span class="font-medium text-gray-900">{{ t('permissionsAdmin.scopeTitle') }}</span>
                        </div>

                        <div class="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2 lg:grid-cols-4">
                            <div v-for="dim in [
                                { key: 'departments', label: t('permissionsAdmin.departmentsLabel'), options: scopeOptions.departments },
                                { key: 'stages', label: t('permissionsAdmin.stagesLabel'), options: scopeOptions.stages },
                                { key: 'education_types', label: t('permissionsAdmin.educationTypesLabel'), options: scopeOptions.educationTypes },
                                { key: 'academic_sessions', label: t('permissionsAdmin.academicSessionsLabel'), options: scopeOptions.academicSessions },
                            ]" :key="dim.key">
                                <div class="mb-1.5 flex items-center justify-between">
                                    <span class="text-sm font-medium text-gray-700">{{ dim.label }}</span>
                                    <button
                                        v-if="form.scope[dim.key].length"
                                        type="button"
                                        @click="clearScope(dim.key)"
                                        class="text-xs text-gray-400 hover:text-gray-600"
                                    >
                                        {{ t('permissionsAdmin.removeRestriction') }}
                                    </button>
                                </div>

                                <div
                                    v-if="!form.scope[dim.key].length"
                                    class="rounded-md border border-dashed border-gray-200 px-3 py-2 text-xs text-gray-400"
                                >
                                    <Icon name="all_inclusive" size="text-[14px]" class="ml-1" />{{ t('permissionsAdmin.unrestricted') }}
                                </div>

                                <div class="max-h-40 space-y-1 overflow-y-auto rounded-md border border-gray-200 p-2">
                                    <label
                                        v-for="opt in dim.options"
                                        :key="opt.id"
                                        class="flex items-center gap-2 text-sm text-gray-700"
                                    >
                                        <input
                                            type="checkbox"
                                            :checked="form.scope[dim.key].includes(opt.id)"
                                            @change="toggleScopeId(dim.key, opt.id)"
                                            class="rounded border-gray-300 text-indigo-600 shadow-sm focus:ring-indigo-500"
                                        />
                                        {{ opt.name }}
                                    </label>
                                    <p v-if="!dim.options.length" class="px-1 py-1 text-xs text-gray-400">{{ t('permissionsAdmin.noOptionsAvailable') }}</p>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div v-for="module in modules" :key="module.key" class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <div class="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 bg-gray-50 px-4 py-3">
                            <div>
                                <span class="font-medium text-gray-900">{{ module.name }}</span>
                                <span class="mr-2 text-xs text-gray-400">{{ module.key }}</span>
                            </div>
                            <label class="flex items-center gap-2 text-xs text-gray-600">
                                <input
                                    type="checkbox"
                                    :checked="moduleAllChecked(module)"
                                    @change="toggleModule(module)"
                                    class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                />
                                {{ t('permissionsAdmin.selectAllModuleActions') }}
                            </label>
                        </div>

                        <div class="flex flex-wrap gap-x-6 gap-y-2 p-4">
                            <label
                                v-for="permission in module.permissions"
                                :key="permission.key"
                                class="flex items-center gap-2 text-sm text-gray-700"
                            >
                                <input
                                    type="checkbox"
                                    :checked="isChecked(module.key, permission.key)"
                                    @change="toggle(module.key, permission.key)"
                                    class="rounded border-gray-300 text-indigo-600 shadow-sm focus:ring-indigo-500"
                                />
                                {{ permission.label }}
                                <span class="text-xs text-gray-400">({{ permission.key }})</span>
                            </label>
                        </div>
                    </div>

                    <div class="flex items-center justify-between rounded-lg bg-white p-4 shadow-sm">
                        <span class="text-sm text-gray-500">{{ t('permissionsAdmin.grantedSummary', { granted: form.grants.length, total: allPairs.length }) }}</span>
                        <PrimaryButton :disabled="form.processing">{{ t('permissionsAdmin.savePermissions') }}</PrimaryButton>
                    </div>
                </form>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
