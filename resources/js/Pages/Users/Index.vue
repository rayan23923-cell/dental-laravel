<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t, te } = useI18n();
const props = defineProps({
    users: Array,
});

const page = usePage();
const search = ref('');
// Role filter (2026-10-14, by request): chips for the roles present, with
// how many users each has; works together with the search.
const roleFilter = ref('');

/**
 * Users management (2026-10-21, by request) — the permissions page's list,
 * with disabled accounts marked; a row opens the user's details.
 */
const ROLE_STYLES = {
    super_admin: { icon: 'verified_user', chip: 'bg-gray-900 text-white', avatar: 'from-gray-700 to-gray-900' },
    admin: { icon: 'shield_person', chip: 'bg-indigo-50 text-indigo-700', avatar: 'from-indigo-500 to-purple-500' },
    editor: { icon: 'edit_note', chip: 'bg-sky-50 text-sky-700', avatar: 'from-sky-500 to-cyan-500' },
    doctor: { icon: 'stethoscope', chip: 'bg-emerald-50 text-emerald-700', avatar: 'from-emerald-500 to-teal-500' },
    accountant: { icon: 'payments', chip: 'bg-amber-50 text-amber-700', avatar: 'from-amber-500 to-orange-500' },
    senior: { icon: 'workspace_premium', chip: 'bg-fuchsia-50 text-fuchsia-700', avatar: 'from-fuchsia-500 to-pink-500' },
    hr: { icon: 'badge', chip: 'bg-rose-50 text-rose-700', avatar: 'from-rose-500 to-red-500' },
    reception: { icon: 'confirmation_number', chip: 'bg-teal-50 text-teal-700', avatar: 'from-teal-500 to-green-500' },
    lab: { icon: 'biotech', chip: 'bg-violet-50 text-violet-700', avatar: 'from-violet-500 to-indigo-500' },
    teacher: { icon: 'school', chip: 'bg-teal-50 text-teal-700', avatar: 'from-teal-500 to-emerald-500' },
};
const FALLBACK = { icon: 'person', chip: 'bg-gray-100 text-gray-700', avatar: 'from-gray-400 to-gray-500' };

const styleFor = (role) => ROLE_STYLES[role] ?? FALLBACK;
const roleLabel = (role) => (te(`roles.${role}`) ? t(`roles.${role}`) : role);
const initial = (user) => (user.full_name || user.username || '?').trim().charAt(0).toUpperCase();

const roleCounts = computed(() => {
    const counts = {};
    for (const u of props.users) counts[u.role] = (counts[u.role] ?? 0) + 1;
    return Object.entries(counts).map(([role, count]) => ({ role, count }));
});

const filtered = computed(() => {
    const q = search.value.trim().toLowerCase();
    return props.users.filter(
        (u) =>
            (!roleFilter.value || u.role === roleFilter.value) &&
            (!q || [u.full_name, u.username, u.email, u.phone, u.role, roleLabel(u.role)].some((v) => (v ?? '').toLowerCase().includes(q))),
    );
});
</script>

<template>
    <Head :title="t('usersAdmin.indexTitle')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('usersAdmin.indexTitle') }}</h2>
                <div class="flex items-center gap-2">
                    <Link
                        :href="route('permissions.index')"
                        :title="t('nav.permissions')"
                        class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200"
                    >
                        <Icon name="admin_panel_settings" />
                    </Link>
                    <Link
                        :href="route('department-roles.index')"
                        :title="t('permissionsAdmin.departmentRolesShort')"
                        class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200"
                    >
                        <Icon name="account_tree" />
                    </Link>
                    <Link
                        v-if="page.props.auth?.user?.role === 'super_admin'"
                        :href="route('bulk-credentials.index')"
                        :title="t('bulkCredentials.navLink')"
                        class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200"
                    >
                        <Icon name="group_add" />
                    </Link>
                    <Link
                        :href="route('users.create')"
                        :title="t('permissionsAdmin.addUserShort')"
                        class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-pink-500 text-white shadow hover:opacity-90"
                    >
                        <Icon name="person_add" />
                    </Link>
                </div>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- Search -->
                <div class="relative">
                    <Icon name="search" class="pointer-events-none absolute inset-y-0 start-3 my-auto h-6 text-gray-400" />
                    <input
                        v-model="search"
                        type="search"
                        :placeholder="t('usersAdmin.searchPlaceholder')"
                        class="block w-full rounded-full border-0 bg-gray-100 py-2.5 pe-4 ps-11 text-sm text-gray-900 placeholder:text-gray-500 focus:bg-white focus:ring-2 focus:ring-indigo-500"
                    />
                </div>

                <!-- Role filter -->
                <div v-if="roleCounts.length > 1" class="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
                    <button
                        type="button"
                        class="inline-flex shrink-0 items-center gap-1 rounded-full px-3 py-1.5 text-xs font-medium ring-1 transition"
                        :class="roleFilter === '' ? 'bg-indigo-600 text-white ring-indigo-600' : 'bg-white text-gray-700 ring-gray-200 hover:bg-gray-50'"
                        @click="roleFilter = ''"
                    >
                        {{ t('permissionsAdmin.allRoles') }}
                        <span class="opacity-70">{{ users.length }}</span>
                    </button>
                    <button
                        v-for="r in roleCounts"
                        :key="r.role"
                        type="button"
                        class="inline-flex shrink-0 items-center gap-1 rounded-full px-3 py-1.5 text-xs font-medium ring-1 transition"
                        :class="roleFilter === r.role ? 'bg-indigo-600 text-white ring-indigo-600' : [styleFor(r.role).chip, 'ring-transparent hover:opacity-80']"
                        @click="roleFilter = roleFilter === r.role ? '' : r.role"
                    >
                        <Icon :name="styleFor(r.role).icon" size="text-[16px]" />
                        {{ roleLabel(r.role) }}
                        <span class="opacity-70">{{ r.count }}</span>
                    </button>
                </div>

                <!-- User list -->
                <div class="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-gray-100">
                    <Link
                        v-for="user in filtered"
                        :key="user.id"
                        :href="route('users.edit', user.id)"
                        class="flex items-center gap-3 border-b border-gray-100 px-4 py-3 transition last:border-b-0 hover:bg-gray-50 active:bg-gray-100"
                    >
                        <div
                            :class="[styleFor(user.role).avatar, user.status === 'inactive' ? 'opacity-40 grayscale' : '']"
                            class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-gradient-to-br text-lg font-semibold text-white"
                        >
                            {{ initial(user) }}
                        </div>
                        <div class="min-w-0 flex-1">
                            <div class="truncate text-[15px] font-semibold text-gray-900">{{ user.full_name || user.username }}</div>
                            <div class="mt-1 flex items-center gap-2">
                                <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium" :class="styleFor(user.role).chip">
                                    <Icon :name="styleFor(user.role).icon" size="text-[16px]" />
                                    {{ roleLabel(user.role) }}
                                </span>
                                <span v-if="user.status === 'inactive'" class="inline-flex items-center gap-1 rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700">
                                    <Icon name="block" size="text-[14px]" />
                                    {{ t('usersAdmin.inactive') }}
                                </span>
                                <span v-if="user.username" class="truncate text-xs text-gray-400" dir="ltr">@{{ user.username }}</span>
                            </div>
                        </div>
                        <Icon name="chevron_left" class="shrink-0 text-gray-300 ltr:rotate-180" />
                    </Link>

                    <div v-if="filtered.length === 0" class="flex flex-col items-center gap-2 px-4 py-12 text-center text-sm text-gray-500">
                        <Icon name="group_off" size="text-4xl" class="text-gray-300" />
                        {{ t('usersAdmin.empty') }}
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
