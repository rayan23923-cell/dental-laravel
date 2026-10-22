<script setup>
/**
 * One account's permissions, as a settings list like clinic settings and
 * the profile (2026-10-14, by request): an account card on top, then
 * "نطاق الوصول" and "الصلاحيات" as collapsible rows with a coloured icon
 * and a one-line summary, switches instead of checkboxes, and a save bar
 * that stays on screen.
 *
 * The list itself is PermissionsEditor, shared with the add-user form.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import PermissionsEditor from '@/Components/Permissions/PermissionsEditor.vue';
import { Head, Link, useForm, usePage } from '@inertiajs/vue3';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t, te } = useI18n();
const page = usePage();
const props = defineProps({
    targetUser: Object,
    modules: Array,
    granted: Array,
    // Option lists + the account's current selection for each of the four
    // scope dimensions (App\Services\ScopeHelper). `null` on any dimension
    // in `scope` means nothing picked; see the all* flags for "الكل".
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
        // "الكل" on the top levels (2026-10-18).
        all_education_types: props.scope.allEducationTypes,
        all_academic_sessions: props.scope.allAcademicSessions,
    },
});

const allPairs = computed(() => props.modules.flatMap((m) => m.permissions.map((p) => `${m.key}.${p.key}`)));

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
                <Link :href="route('users.edit', targetUser.id)" class="flex items-center gap-1 text-sm text-indigo-600 hover:underline">
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
                    <PermissionsEditor :form="form" :modules="modules" :scope-options="scopeOptions" />

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
