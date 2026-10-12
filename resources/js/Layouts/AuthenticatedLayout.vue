<script setup>
/**
 * Staff shell.
 *
 * The navigation is modelled on the dental-unit control panel: a raised
 * slab holding a horizontally-scrolling strip of icon+label tiles, with the
 * active tile carrying the accent gradient. Colours come from the theme
 * variables (App\Support\ThemePalette), so the bar follows whichever theme
 * is selected in settings.
 *
 * **The content region deliberately keeps its neutral light background.**
 * Around fifty page components style their own cards, tables and text with
 * fixed Tailwind greys (`bg-white`, `text-gray-800`); repainting the region
 * behind them from a dark theme token would leave dark-on-dark text on any
 * page that writes directly onto the page background. Theming the chrome is
 * safe today, theming every page body is a separate pass.
 */
import { computed, ref } from 'vue';
import BrandMark from '@/Components/BrandMark.vue';
import Dropdown from '@/Components/Dropdown.vue';
import DropdownLink from '@/Components/DropdownLink.vue';
import Icon from '@/Components/Icon.vue';
import { Link, usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

const showingNavigationDropdown = ref(false);
const page = usePage();
const { t } = useI18n();

const isAdmin = computed(() => ['super_admin', 'admin'].includes(page.props.auth.user.role));
// Desk roles (2026-10-12): `reception` (موظف التذاكر) and `lab` (مختبري)
// only reach the ticket desk or the lab, so they see only those links.
const deskRole = computed(() => (['reception', 'lab'].includes(page.props.auth.user.role) ? page.props.auth.user.role : null));

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
 *    charts, clinical records, appointments, payments).
 *  - "admin,super_admin"-only routes (education-types, stages,
 *    departments, academic-sessions, case-sheet-types, groups,
 *    task-progress, activity-logs, permissions, clinic-settings,
 *    register-settings, department-roles, backup) stay behind `isAdmin`.
 */
const clinicalRoutes = [
    'advanced-periodontal-charts', 'complete-denture-records', 'oral-medicine-charts', 'orthodontics-records',
    'periodontal-charts', 'prevention-records', 'prosthodontics-records',
    'surgeries', 'surgery-follow-ups', 'surgery-images', 'surgery-medications',
    'treatment-plans', 'treatment-materials',
];
const isClinicalRecordsActive = computed(
    () => route().current('clinical-records.*') || clinicalRoutes.some((r) => route().current(`${r}.*`))
);

const isPatientsGroupActive = computed(
    () => route().current('patients.*')
        || route().current('patient-registrations.index')
        || route().current('patient-registrations.create')
        || route().current('lab.*')
);

const structureRoutes = [
    'departments', 'stages', 'education-types',
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
        || route().current('activity-logs.*')
        || route().current('backup.*')
);

/**
 * One list drives the desktop strip and the mobile menu, so a module can no
 * longer be added to one and forgotten in the other — which is exactly how
 * the mobile menu ended up missing half the app.
 */
const primaryLinks = computed(() => deskRole.value ? [] : [
    { label: t('nav.home'), icon: 'dashboard', href: route('dashboard'), active: route().current('dashboard') },
    { label: t('nav.doctors'), icon: 'stethoscope', href: route('doctors.index'), active: route().current('doctors.*') },
    { label: t('nav.tasks'), icon: 'assignment', href: route('tasks.index'), active: route().current('tasks.*') },
    ...(isAdmin.value
        ? [{ label: t('nav.taskProgress'), icon: 'monitoring', href: route('task-progress.index'), active: route().current('task-progress.*') }]
        : []),
    { label: t('nav.clinicalRecords'), icon: 'clinical_notes', href: route('clinical-records.index'), active: isClinicalRecordsActive.value },
    { label: t('nav.appointments'), icon: 'event', href: route('appointments.index'), active: route().current('appointments.*') },
    { label: t('nav.payments'), icon: 'payments', href: route('payments.index'), active: route().current('payments.*') },
]);

// "إدارة المرضى" — always visible (patients/patient-registrations are
// editor-accessible, same as the flat links above). Restores two routes
// that already existed in the backend but had no navbar entry at all:
// `patients.index` (the plain patient-record list) and
// `patient-registrations.create` (its own page, separate from the index).
const patientsLinks = computed(() => {
    const register = { label: t('nav.registerPatient'), icon: 'person_add', href: route('patient-registrations.create'), active: route().current('patient-registrations.create') };
    const registry = { label: t('nav.patientRegistrations'), icon: 'how_to_reg', href: route('patient-registrations.index'), active: route().current('patient-registrations.index') };
    const lab = { label: t('nav.lab'), icon: 'coronavirus', href: route('lab.index'), active: route().current('lab.*') };
    if (deskRole.value === 'reception') return [register, registry];
    if (deskRole.value === 'lab') return [lab];
    return [
        register,
        registry,
        { label: t('nav.patientsList'), icon: 'list_alt', href: route('patients.index'), active: route().current('patients.*') },
        lab,
    ];
});

// "البيانات الأساسية" — admin-only (matches the original's dropdown of the
// same name); "المجموعات" lives here rather than paired with "الأطباء"
// above because — unlike the original — this app's `groups` routes are
// admin-only while `doctors` is editor-accessible.
const structureLinks = computed(() => [
    { label: t('nav.educationTypes'), icon: 'school', href: route('education-types.index'), active: route().current('education-types.*') },
    { label: t('nav.stages'), icon: 'stairs', href: route('stages.index'), active: route().current('stages.*') },
    { label: t('nav.departments'), icon: 'apartment', href: route('departments.index'), active: route().current('departments.*') },
    { label: t('nav.academicSessions'), icon: 'calendar_month', href: route('academic-sessions.index'), active: route().current('academic-sessions.*') },
    { label: t('nav.groups'), icon: 'groups', href: route('groups.index'), active: route().current('groups.*') },
    { label: t('nav.clinicChairs'), icon: 'chair', href: route('clinic-chairs.index'), active: route().current('clinic-chairs.*') },
    { label: t('nav.caseSheetTypes'), icon: 'description', href: route('case-sheet-types.index'), active: route().current('case-sheet-types.*') },
]);

// "الإعدادات" — admin-only, new grouped dropdown replacing the flat
// `adminLinks` strip. Folds in three routes that existed in the backend
// with no navbar link at all: `clinic-settings.edit` (previously reachable
// only from the account menu), `patient-registrations.settings`, and
// `department-roles.index`.
const settingsLinks = computed(() => [
    { label: t('nav.clinicSettings'), icon: 'settings', href: route('clinic-settings.edit'), active: route().current('clinic-settings.*') },
    { label: t('nav.waitingScreenSettings'), icon: 'tv', href: route('waiting-screen-settings.edit'), active: route().current('waiting-screen-settings.*') },
    { label: t('nav.pairWaitingScreen'), icon: 'qr_code_scanner', href: route('waiting-screen-pairing.create'), active: route().current('waiting-screen-pairing.*') },
    { label: t('nav.registrationSettings'), icon: 'tune', href: route('patient-registrations.settings'), active: route().current('patient-registrations.settings') || route().current('register-days.*') || route().current('register-services.*') },
    { label: t('nav.departmentRoles'), icon: 'badge', href: route('department-roles.index'), active: route().current('department-roles.*') },
    { label: t('nav.permissions'), icon: 'admin_panel_settings', href: route('permissions.index'), active: route().current('permissions.*') },
    { label: t('nav.sendBroadcast'), icon: 'campaign', href: route('admin-broadcast.create'), active: route().current('admin-broadcast.*') },
    { label: t('nav.activityLog'), icon: 'history', href: route('activity-logs.index'), active: route().current('activity-logs.*') },
    { label: t('nav.backup'), icon: 'database', href: route('backup.index'), active: route().current('backup.*') },
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
    <div class="min-h-screen bg-gray-100">
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

                        <template v-if="isAdmin">
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

                    <!-- Account -->
                    <div class="ms-auto hidden shrink-0 items-center sm:flex">
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
                        class="ms-auto inline-flex items-center justify-center rounded-xl bg-surface-2 p-2 text-muted transition hover:text-content sm:hidden"
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

                    <template v-if="isAdmin">
                        <div class="mt-3 px-1 text-xs font-semibold uppercase tracking-wider text-muted">
                            {{ t('nav.structureGroup') }}
                        </div>
                        <div class="mt-1.5 grid grid-cols-2 gap-1.5">
                            <Link v-for="link in structureLinks" :key="link.href" :href="link.href" :class="tileClass(link.active)">
                                <Icon :name="link.icon" size="text-[18px]" />
                                <span class="truncate">{{ link.label }}</span>
                            </Link>
                        </div>

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
