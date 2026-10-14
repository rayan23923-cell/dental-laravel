<script setup>
/**
 * Doctor-area shell — port of dental_clinics2/doctor/doctor_navbar.php:
 * the same four nav items in the same order and wording, the clinic
 * logo + name brand, the academic-session switcher, and the avatar dropdown
 * (الملف الشخصي / تسجيل الخروج).
 *
 * Restyled to match the staff shell and the dental-unit panel it is modelled
 * on: a raised slab of icon+label tiles with the active tile carrying the
 * accent gradient, all driven by the theme selected in settings
 * (App\Support\ThemePalette) rather than the previous fixed indigo→purple
 * gradient.
 *
 * Not ported: the "admin viewing as doctor" branch of that navbar — the
 * impersonation feature it belongs to is orphaned in the original (only
 * linked from the retired admin_navbar.php), see README.
 */
import { Link, router, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BrandMark from '@/Components/BrandMark.vue';
import Icon from '@/Components/Icon.vue';
import NotificationBell from '@/Components/NotificationBell.vue';

const { t } = useI18n();
const page = usePage();
const open = ref(false);
const menuOpen = ref(false);

const doctor = computed(() => page.props.auth?.doctor ?? {});
const clinic = computed(() => page.props.clinicSettings ?? {});
const sessions = computed(() => page.props.academicSessions ?? []);
const selectedSession = computed(() => page.props.selectedAcademicSessionId ?? '');

/**
 * `icon` holds the Material Symbols ligature name.
 *
 * It previously held a *string of component markup*
 * (`'<Icon name="home" class="ml-1" />'`) rendered through `{{ item.icon }}`,
 * which Vue escapes — so every nav item printed that tag as visible text
 * instead of an icon. Left over from the emoji→Material Symbols pass, which
 * rewrote the emoji inside this JS string as if it were template markup.
 */
const NAV = computed(() => [
    { route: 'doctor.dashboard', label: t('nav.home'), icon: 'home' },
    { route: 'doctor.required-tasks', label: t('doctorLayout.requiredTasks'), icon: 'assignment' },
    { route: 'doctor.pending-qr', label: t('doctorLayout.pendingTasksQr'), icon: 'qr_code_2' },
    { route: 'doctor.progress', label: t('doctorLayout.progress'), icon: 'trending_up' },
]);

const switchSession = (event) => {
    const id = event.target.value;
    if (!id) return;
    router.post(route('doctor.session.select'), { academic_session_id: id }, { preserveScroll: true });
};

const tileClass = (active) => [
    'flex shrink-0 items-center gap-2 rounded-xl px-3.5 py-2 text-sm font-medium transition',
    active
        ? 'bg-gradient-to-br from-accent to-accent-deep text-accent-fg shadow-glow'
        : 'text-muted hover:bg-surface-2 hover:text-content',
];
</script>

<template>
    <div class="min-h-screen bg-gray-100" dir="rtl">
        <div class="bg-app px-3 pb-3 pt-3 sm:px-6 lg:px-8">
            <nav class="mx-auto max-w-7xl rounded-card border border-hairline/70 bg-surface shadow-panel">
                <div class="flex items-center gap-3 px-3 py-2.5 sm:px-4">
                    <!-- Brand -->
                    <Link :href="route('doctor.dashboard')" class="flex shrink-0 items-center gap-2.5">
                        <img v-if="clinic.logo_url" :src="clinic.logo_url" alt="" class="h-9 w-9 rounded-xl object-contain" />
                        <BrandMark v-else :size="36" />
                        <span class="hidden text-sm font-semibold text-content md:inline">
                            {{ t('doctorLayout.title') }} — {{ clinic.name ?? t('doctorLayout.clinicFallback') }}
                        </span>
                    </Link>

                    <div class="hidden h-8 w-px shrink-0 bg-hairline lg:block"></div>

                    <!-- Nav strip -->
                    <div class="hide-scrollbar hidden flex-1 items-center gap-1 overflow-x-auto lg:flex">
                        <Link
                            v-for="item in NAV"
                            :key="item.route"
                            :href="route(item.route)"
                            :class="tileClass(route().current(item.route))"
                        >
                            <Icon :name="item.icon" size="text-[18px]" />
                            <span class="whitespace-nowrap">{{ item.label }}</span>
                        </Link>
                    </div>

                    <div class="ms-auto flex items-center gap-2">
                        <NotificationBell doctor />
                        <!-- Academic session switcher -->
                        <select
                            v-if="sessions.length"
                            :value="selectedSession"
                            @change="switchSession"
                            class="hidden rounded-xl border border-hairline bg-surface-2 px-2 py-1.5 text-xs text-content focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/40 sm:block"
                        >
                            <option v-for="s in sessions" :key="s.id" :value="s.id">
                                {{ s.name }}{{ s.is_current ? ` [${t('doctorLayout.current')}]` : '' }}
                            </option>
                        </select>

                        <!-- Avatar dropdown -->
                        <div class="relative">
                            <button
                                type="button"
                                @click="open = !open"
                                class="flex items-center gap-2 rounded-xl border border-hairline/70 bg-surface-2 px-2.5 py-1.5 text-content transition hover:border-accent/50"
                            >
                                <img
                                    v-if="doctor.profile_image"
                                    :src="`/storage/${doctor.profile_image}`"
                                    alt=""
                                    class="h-7 w-7 rounded-lg object-cover"
                                />
                                <span
                                    v-else
                                    class="flex h-7 w-7 items-center justify-center rounded-lg bg-gradient-to-br from-accent to-accent-deep text-accent-fg"
                                >
                                    <Icon name="person" size="text-[16px]" />
                                </span>
                                <span class="hidden text-right md:block">
                                    <span class="block text-sm font-semibold leading-tight">{{ doctor.name ?? t('doctorLayout.doctorFallback') }}</span>
                                    <span class="block text-[11px] leading-tight text-muted">{{ t('doctorLayout.doctorAccount') }}</span>
                                </span>
                                <Icon name="expand_more" size="text-[16px]" class="text-muted" />
                            </button>

                            <div
                                v-if="open"
                                class="absolute left-0 z-50 mt-2 w-52 overflow-hidden rounded-xl border border-hairline/70 bg-surface py-1.5 shadow-panel"
                                @click="open = false"
                            >
                                <Link
                                    :href="route('doctor.profile.edit')"
                                    class="flex items-center gap-2 px-4 py-2 text-sm text-content transition hover:bg-surface-2"
                                >
                                    <Icon name="edit" size="text-[18px]" />{{ t('nav.profile') }}
                                </Link>
                                <hr class="my-1 border-hairline/70" />
                                <Link
                                    :href="route('doctor.logout')"
                                    method="post"
                                    as="button"
                                    class="flex w-full items-center gap-2 px-4 py-2 text-right text-sm text-red-400 transition hover:bg-surface-2"
                                >
                                    <Icon name="logout" size="text-[18px]" />{{ t('nav.logout') }}
                                </Link>
                            </div>
                        </div>

                        <!-- Mobile toggle -->
                        <button
                            type="button"
                            @click="menuOpen = !menuOpen"
                            class="rounded-xl bg-surface-2 p-2 text-muted transition hover:text-content lg:hidden"
                            :aria-label="menuOpen ? t('nav.closeMenu') : t('nav.openMenu')"
                        >
                            <Icon :name="menuOpen ? 'close' : 'menu'" size="text-[22px]" />
                        </button>
                    </div>
                </div>

                <!-- Mobile nav -->
                <div v-show="menuOpen" class="border-t border-hairline/70 px-3 pb-3 pt-2 lg:hidden">
                    <div class="space-y-1.5">
                        <Link
                            v-for="item in NAV"
                            :key="item.route"
                            :href="route(item.route)"
                            :class="tileClass(route().current(item.route))"
                        >
                            <Icon :name="item.icon" size="text-[18px]" />
                            <span>{{ item.label }}</span>
                        </Link>
                    </div>

                    <select
                        v-if="sessions.length"
                        :value="selectedSession"
                        @change="switchSession"
                        class="mt-3 block w-full rounded-xl border border-hairline bg-surface-2 px-3 py-2 text-xs text-content sm:hidden"
                    >
                        <option v-for="s in sessions" :key="s.id" :value="s.id">
                            {{ s.name }}{{ s.is_current ? ` [${t('doctorLayout.current')}]` : '' }}
                        </option>
                    </select>
                </div>
            </nav>
        </div>

        <header v-if="$slots.header" class="border-b border-gray-200 bg-white shadow-sm">
            <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
                <slot name="header" />
            </div>
        </header>

        <main class="mx-auto max-w-7xl px-4 py-6 pb-12 sm:px-6 lg:px-8">
            <div v-if="page.props.flash?.success" class="mb-4 rounded-md bg-green-50 p-4 text-sm text-green-700">
                {{ page.props.flash.success }}
            </div>
            <div v-if="page.props.flash?.error" class="mb-4 rounded-md bg-red-50 p-4 text-sm text-red-700">
                {{ page.props.flash.error }}
            </div>
            <slot />
        </main>
    </div>
</template>

<style scoped>
.hide-scrollbar {
    scrollbar-width: none;
}
.hide-scrollbar::-webkit-scrollbar {
    display: none;
}
</style>
