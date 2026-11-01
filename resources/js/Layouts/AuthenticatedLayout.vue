<script setup>
import { paymentsTitleFor } from '@/paymentsTitle';
/**
 * Staff shell.
 *
 * The navigation is modelled on the dental-unit control panel: a raised
 * slab holding a horizontally-scrolling strip of icon+label tiles, with the
 * active tile carrying the accent gradient. Colours come from the theme
 * variables (App\Support\ThemePalette), so the bar follows whichever theme
 * is selected in settings.
 *
 * Page bodies follow the theme too (2026-10-15): the `themed` class on the
 * root repaints the fixed Tailwind greys pages use (`bg-white`,
 * `text-gray-800`, ...) from the theme tokens — see the end of app.css.
 */
import { computed, ref } from 'vue';
import BrandMark from '@/Components/BrandMark.vue';
import Dropdown from '@/Components/Dropdown.vue';
import DropdownLink from '@/Components/DropdownLink.vue';
import PhoneScannerLink from '@/Components/PhoneScannerLink.vue';
import NotificationBell from '@/Components/NotificationBell.vue';
import Icon from '@/Components/Icon.vue';
import { Link, usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';
import { useStructureLinks } from '@/Composables/useStructureLinks';

const showingNavigationDropdown = ref(false);
const page = usePage();
const { t } = useI18n();

const isAdmin = computed(() => ['super_admin', 'admin'].includes(page.props.auth.user.role));
// Desk roles (2026-10-12): `reception` (موظف التذاكر) and `lab` (مختبري)
// only reach the ticket desk or the lab, so they see only those links.
const deskRole = computed(() => (['reception', 'lab'].includes(page.props.auth.user.role) ? page.props.auth.user.role : null));
const navCan = computed(() => page.props.navCan ?? {});
// The lab's / ticket desk's own payments are named for what they show (2026-10-26).
const paymentsTitle = (scope) => paymentsTitleFor(t, scope);

/**
 * Grouping mirrors the original app's navbar.php dropdowns (إدارة البيانات
 * الأساسية / إدارة الأطباء / إدارة المرضى / الإعدادات) rather than the flat
 * strip this rebuild started with. Group membership follows the *actual*
 * `role:` middleware in routes/web.php, not the original 1:1 — this app's
 * route gates have diverged from the original's in both directions (e.g.
 * `groups` is admin-only here, `tasks` is editor-accessible here), so
 * copying the original's grouping verbatim would have hidden links from
 * roles that can legitimately use them, or shown links that just 403.
 * Two tiers, matching the two role gates actually used:
 *  - "editor,admin,super_admin" routes stay flat or in an always-visible
 *    dropdown (doctors, patients/patient-registrations, tasks, dental
 *    charts, appointments, payments).
 *  - "admin,super_admin"-only routes (education-types, stages,
 *    departments, academic-sessions, case-sheet-types, groups,
 *    task-progress, activity-logs, permissions, clinic-settings,
 *    register-settings, department-roles, backup) stay behind `isAdmin`.
 */
const isPatientsGroupActive = computed(
    () => route().current('patients.*')
        || route().current('patient-registrations.index')
        || route().current('patient-registrations.create')
        || route().current('lab.*')
);

const structureRoutes = [
    'departments', 'stages', 'education-types',
    'doctors', 'tasks', 'task-progress',
    'academic-sessions', 'groups', 'case-sheet-types',
];
const isStructureActive = computed(() => structureRoutes.some((r) => route().current(`${r}.*`)));

const isSettingsGroupActive = computed(
    () => route().current('clinic-settings.*')
        || route().current('waiting-screen-settings.*')
        || route().current('waiting-screen-pairing.*')
        || route().current('patient-registrations.settings')
        || route().current('register-days.*')
        || route().current('register-services.*')
        || route().current('department-roles.*')
        || route().current('permissions.*')
        || route().current('users.*')
        || route().current('activity-logs.*')
        || route().current('backup.*')
);

/**
 * One list drives the desktop strip and the mobile menu, so a module can no
 * longer be added to one and forgotten in the other — which is exactly how
 * the mobile menu ended up missing half the app.
 */
const primaryLinks = computed(() => [
    ...(deskRole.value ? [] : [{ label: t('nav.home'), icon: 'dashboard', href: route('dashboard'), active: route().current('dashboard') }]),
    // Doctors, tasks and task progress moved under "البيانات الأساسية"
    // (2026-10-13, by request) — see structureLinks.
    // Clinical records hidden from the menu (2026-10-13, by request); case
    // sheets are opened from the task they belong to.
    // Appointments hidden from the menu for now (2026-10-13, by request);
    // the page stays reachable at /appointments.
    // Payments and, for a non-admin given it (the accountant), the
    // registration services' settings follow their permissions (2026-10-24),
    // desk roles included.
    ...(navCan.value.payments ? [{ label: paymentsTitle(navCan.value.payments_scope), icon: 'payments', href: route('payments.index'), active: route().current('payments.*') }] : []),
    ...(!isAdmin.value && navCan.value.register_settings ? [{ label: t('nav.registrationSettings'), icon: 'tune', href: route('patient-registrations.settings'), active: route().current('patient-registrations.settings') }] : []),
    ...(!isAdmin.value && navCan.value.waiting_screen ? [{ label: t('nav.waitingScreenSettings'), icon: 'tv', href: route('waiting-screen-settings.edit'), active: route().current('waiting-screen-settings.*') }] : []),
    // Bulk login details follow their own permission (2026-11-01).
    ...(!isAdmin.value && navCan.value.bulk_credentials ? [{ label: t('nav.bulkCredentials'), icon: 'group_add', href: route('bulk-credentials.index'), active: route().current('bulk-credentials.*') }] : []),
    // Care cards follow their own permission (2026-11-01).
    ...(!isAdmin.value && navCan.value.support_codes ? [{ label: t('nav.supportCodes'), icon: 'volunteer_activism', href: route('support-codes.index'), active: route().current('support-codes.*') }] : []),
]);

// "إدارة المرضى" — always visible (patients/patient-registrations are
// editor-accessible, same as the flat links above). Restores two routes
// that already existed in the backend but had no navbar entry at all:
// `patients.index` (the plain patient-record list) and
// `patient-registrations.create` (its own page, separate from the index).
const patientsLinks = computed(() => {
    // The separate "تسجيل مريض" entry was dropped (2026-10-13, by request):
    // the registrations page already registers patients, and two entries
    // confused users. Its create page counts as part of the registry.
    const registry = { label: t('nav.patientRegistrations'), icon: 'how_to_reg', href: route('patient-registrations.index'), active: route().current('patient-registrations.index') || route().current('patient-registrations.create') };
    const lab = { label: t('nav.lab'), icon: 'coronavirus', href: route('lab.index'), active: route().current('lab.*') };
    if (deskRole.value === 'reception') return [registry];
    if (deskRole.value === 'lab') return [lab];
    // "قائمة المرضى" dropped too (2026-10-13, by request): the registry
    // covers it. The page stays reachable at /patients.
    return [registry, lab];
});

// "البيانات الأساسية" — admin-only (matches the original's dropdown of the
// same name); "المجموعات" lives here rather than paired with "الأطباء"
// above because — unlike the original — this app's `groups` routes are
// admin-only while `doctors` is editor-accessible.
// Doctors, tasks and task progress live here too (2026-10-13, by request),
// ordered tasks → academic year → doctors → groups → task progress. Doctors and tasks are
// editor-accessible, so editors see a short version of this group with
// just those two; everything else stays admin-only.
const structureLinks = useStructureLinks();

// "الإعدادات" — admin-only, new grouped dropdown replacing the flat
// `adminLinks` strip. Folds in three routes that existed in the backend
// with no navbar link at all: `clinic-settings.edit` (previously reachable
// only from the account menu) and `patient-registrations.settings`.
// Permissions and `department-roles.index` have no tile of their own
// (2026-10-22, by request): both open from the users page header.
const settingsLinks = computed(() => [
    { label: t('nav.clinicSettings'), icon: 'settings', href: route('clinic-settings.edit'), active: route().current('clinic-settings.*') },
    // The waiting screen follows its own permission (2026-10-24).
    ...(navCan.value.waiting_screen ? [{ label: t('nav.waitingScreenSettings'), icon: 'tv', href: route('waiting-screen-settings.edit'), active: route().current('waiting-screen-settings.*') }] : []),
    ...(navCan.value.waiting_screen_pair ? [{ label: t('nav.pairWaitingScreen'), icon: 'qr_code_scanner', href: route('waiting-screen-pairing.create'), active: route().current('waiting-screen-pairing.*') }] : []),
    ...(navCan.value.register_settings ? [{ label: t('nav.registrationSettings'), icon: 'tune', href: route('patient-registrations.settings'), active: route().current('patient-registrations.settings') || route().current('register-days.*') || route().current('register-services.*') }] : []),
    // Care cards (2026-11-01, by request).
    ...(navCan.value.support_codes ? [{ label: t('nav.supportCodes'), icon: 'volunteer_activism', href: route('support-codes.index'), active: route().current('support-codes.*') }] : []),
    // Users management (2026-10-21, by request). Permissions and department
    // roles left the menu (2026-10-22, by request): both open from here.
    { label: t('nav.users'), icon: 'manage_accounts', href: route('users.index'), active: route().current('users.*') || route().current('permissions.*') || route().current('department-roles.*') },
    // Bulk login details (2026-11-01, by request): its own menu link and permission.
    ...(navCan.value.bulk_credentials ? [{ label: t('nav.bulkCredentials'), icon: 'group_add', href: route('bulk-credentials.index'), active: route().current('bulk-credentials.*') }] : []),
    { label: t('nav.sendBroadcast'), icon: 'campaign', href: route('admin-broadcast.create'), active: route().current('admin-broadcast.*') },
    { label: t('nav.activityLog'), icon: 'history', href: route('activity-logs.index'), active: route().current('activity-logs.*') },
    { label: t('nav.backup'), icon: 'database', href: route('backup.index'), active: route().current('backup.*') },
    // Offline copies' activation codes (2026-10-17): super admins only.
    ...(page.props.auth.user.role === 'super_admin'
        ? [{ label: t('nav.offlineLicenses'), icon: 'key', href: route('offline-licenses.index'), active: route().current('offline-licenses.*') }]
        : []),
]);

// One class list for every nav tile — active tiles take the accent gradient,
// the rest stay quiet until hovered.
const tileClass = (active) => [
    'flex shrink-0 items-center gap-1.5 rounded-xl px-3 py-2 text-sm font-medium transition',
    active
        ? 'bg-gradient-to-br from-accent to-accent-deep text-accent-fg shadow-glow'
        : 'text-muted hover:bg-surface-2 hover:text-content',
];
</script>

<template>
    <div class="themed min-h-screen bg-gray-100">
        <div class="bg-app px-3 pb-3 pt-3 sm:px-6 lg:px-8">
            <nav class="mx-auto max-w-[110rem] rounded-card border border-hairline/70 bg-surface shadow-panel">
                <div class="flex items-center gap-3 px-3 py-2.5 sm:px-4">
                    <!-- Brand -->
                    <Link :href="route('dashboard')" class="flex shrink-0 items-center gap-2.5">
                        <img
                            v-if="page.props.clinicSettings?.logo_url"
                            :src="page.props.clinicSettings.logo_url"
                            alt=""
                            class="h-9 w-9 rounded-xl object-contain"
                        />
                        <BrandMark v-else :size="36" />
                        <span v-if="page.props.clinicSettings?.name" class="hidden text-sm font-semibold text-content lg:inline">
                            {{ page.props.clinicSettings.name }}
                        </span>
                    </Link>

                    <div class="hidden h-8 w-px shrink-0 bg-hairline sm:block"></div>

                    <!-- Tool strip — grouped into the same three clusters as
                         the mobile menu's labelled sections (عام / إدارة
                         المرضى / إدارة), separated by hairline dividers
                         instead of section headings (no room for both a
                         label and every tile on one row). Wraps onto a
                         second line rather than scrolling horizontally: an
                         `overflow-x-auto` strip with a hidden scrollbar (the
                         previous approach) silently clips whatever doesn't
                         fit with no scrollbar or edge cue to show more
                         exists — on anything narrower than a very wide
                         monitor that meant the patients/admin dropdowns
                         were unreachable, not just visually uneven. Wrapping
                         means every tile is always on-screen, same guarantee
                         the mobile grid already gives, just as a second row
                         instead of a labelled section. -->
                    <div class="hidden flex-1 flex-wrap items-center gap-1.5 sm:flex">
                        <Link v-for="link in primaryLinks" :key="link.href" :href="link.href" :class="tileClass(link.active)">
                            <Icon :name="link.icon" size="text-[18px]" />
                            <span class="whitespace-nowrap">{{ link.label }}</span>
                        </Link>

                        <div class="h-6 w-px shrink-0 bg-hairline"></div>

                        <Dropdown align="left" width="56">
                            <template #trigger>
                                <button type="button" :class="tileClass(isPatientsGroupActive)">
                                    <Icon name="how_to_reg" size="text-[18px]" />
                                    <span class="whitespace-nowrap">{{ t('nav.patientsGroup') }}</span>
                                    <Icon name="expand_more" size="text-[16px]" />
                                </button>
                            </template>
                            <template #content>
                                <DropdownLink v-for="link in patientsLinks" :key="link.href" :href="link.href">
                                    {{ link.label }}
                                </DropdownLink>
                            </template>
                        </Dropdown>

                        <template v-if="structureLinks.length">
                            <div class="h-6 w-px shrink-0 bg-hairline"></div>

                            <Dropdown align="left" width="56">
                                <template #trigger>
                                    <button type="button" :class="tileClass(isStructureActive)">
                                        <Icon name="database" size="text-[18px]" />
                                        <span class="whitespace-nowrap">{{ t('nav.structureGroup') }}</span>
                                        <Icon name="expand_more" size="text-[16px]" />
                                    </button>
                                </template>
                                <template #content>
                                    <DropdownLink v-for="link in structureLinks" :key="link.href" :href="link.href">
                                        {{ link.label }}
                                    </DropdownLink>
                                </template>
                            </Dropdown>
                        </template>

                        <template v-if="isAdmin">
                            <Dropdown align="left" width="56">
                                <template #trigger>
                                    <button type="button" :class="tileClass(isSettingsGroupActive)">
                                        <Icon name="settings" size="text-[18px]" />
                                        <span class="whitespace-nowrap">{{ t('nav.settingsGroup') }}</span>
                                        <Icon name="expand_more" size="text-[16px]" />
                                    </button>
                                </template>
                                <template #content>
                                    <DropdownLink v-for="link in settingsLinks" :key="link.href" :href="link.href">
                                        {{ link.label }}
                                    </DropdownLink>
                                </template>
                            </Dropdown>
                        </template>
                    </div>

                    <NotificationBell class="ms-auto shrink-0" />

                    <!-- Account -->
                    <div class="hidden shrink-0 items-center gap-2 sm:flex">
                        <PhoneScannerLink />
                        <Dropdown align="right" width="48">
                            <template #trigger>
                                <button
                                    type="button"
                                    class="flex items-center gap-2 rounded-xl border border-hairline/70 bg-surface-2 px-3 py-2 text-sm font-medium text-content transition hover:border-accent/50"
                                >
                                    <span class="flex h-6 w-6 items-center justify-center rounded-lg bg-gradient-to-br from-accent to-accent-deep text-accent-fg">
                                        <Icon name="person" size="text-[16px]" />
                                    </span>
                                    <span class="max-w-[10rem] truncate">{{ page.props.auth.user.full_name }}</span>
                                    <Icon name="expand_more" size="text-[16px]" class="text-muted" />
                                </button>
                            </template>
                            <template #content>
                                <DropdownLink :href="route('profile.edit')">{{ t('nav.profile') }}</DropdownLink>
                                <DropdownLink :href="route('logout')" method="post" as="button">{{ t('nav.logout') }}</DropdownLink>
                            </template>
                        </Dropdown>
                    </div>

                    <!-- Hamburger -->
                    <button
                        type="button"
                        @click="showingNavigationDropdown = !showingNavigationDropdown"
                        class="inline-flex items-center justify-center rounded-xl bg-surface-2 p-2 text-muted transition hover:text-content sm:hidden"
                        :aria-label="showingNavigationDropdown ? t('nav.closeMenu') : t('nav.openMenu')"
                    >
                        <Icon :name="showingNavigationDropdown ? 'close' : 'menu'" size="text-[22px]" />
                    </button>
                </div>

                <!-- Mobile menu. Built from the same link lists as the desktop
                     strip, so the two can't drift apart again. -->
                <div v-show="showingNavigationDropdown" class="border-t border-hairline/70 px-3 pb-3 pt-2 sm:hidden">
                    <div class="grid grid-cols-2 gap-1.5">
                        <Link v-for="link in primaryLinks" :key="link.href" :href="link.href" :class="tileClass(link.active)">
                            <Icon :name="link.icon" size="text-[18px]" />
                            <span class="truncate">{{ link.label }}</span>
                        </Link>
                    </div>

                    <div class="mt-3 px-1 text-xs font-semibold uppercase tracking-wider text-muted">
                        {{ t('nav.patientsGroup') }}
                    </div>
                    <div class="mt-1.5 grid grid-cols-2 gap-1.5">
                        <Link v-for="link in patientsLinks" :key="link.href" :href="link.href" :class="tileClass(link.active)">
                            <Icon :name="link.icon" size="text-[18px]" />
                            <span class="truncate">{{ link.label }}</span>
                        </Link>
                    </div>

                    <template v-if="structureLinks.length">
                        <div class="mt-3 px-1 text-xs font-semibold uppercase tracking-wider text-muted">
                            {{ t('nav.structureGroup') }}
                        </div>
                        <div class="mt-1.5 grid grid-cols-2 gap-1.5">
                            <Link v-for="link in structureLinks" :key="link.href" :href="link.href" :class="tileClass(link.active)">
                                <Icon :name="link.icon" size="text-[18px]" />
                                <span class="truncate">{{ link.label }}</span>
                            </Link>
                        </div>
                    </template>

                    <template v-if="isAdmin">
                        <div class="mt-3 px-1 text-xs font-semibold uppercase tracking-wider text-muted">
                            {{ t('nav.settingsGroup') }}
                        </div>
                        <div class="mt-1.5 grid grid-cols-2 gap-1.5">
                            <Link v-for="link in settingsLinks" :key="link.href" :href="link.href" :class="tileClass(link.active)">
                                <Icon :name="link.icon" size="text-[18px]" />
                                <span class="truncate">{{ link.label }}</span>
                            </Link>
                        </div>
                    </template>

                    <div class="mt-4 rounded-xl border border-hairline/70 bg-surface-2 p-3">
                        <div class="text-sm font-semibold text-content">{{ page.props.auth.user.full_name }}</div>
                        <div class="text-xs text-muted">{{ page.props.auth.user.email }}</div>

                        <!-- Plain themed links rather than ResponsiveNavLink:
                             that component is fixed `text-gray-600`, which
                             all but disappears on this dark panel. -->
                        <div class="mt-3 space-y-1">
                            <PhoneScannerLink variant="wide" />
                            <Link :href="route('profile.edit')" :class="tileClass(route().current('profile.*'))">
                                <Icon name="account_circle" size="text-[18px]" />{{ t('nav.profile') }}
                            </Link>
                            <Link :href="route('logout')" method="post" as="button" :class="[...tileClass(false), 'w-full']">
                                <Icon name="logout" size="text-[18px]" />{{ t('nav.logout') }}
                            </Link>
                        </div>
                    </div>
                </div>
            </nav>
        </div>

        <!-- Page Heading -->
        <header v-if="$slots.header" class="border-b border-gray-200 bg-white shadow-sm">
            <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
                <slot name="header" />
            </div>
        </header>

        <!-- Page Content -->
        <main>
            <slot />
        </main>
    </div>
</template>
