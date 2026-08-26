<script setup>
/**
 * Public landing page — replaces the default Laravel/Breeze scaffold.
 * Branding (name/description/logo/working hours/contact) comes straight
 * from the same `ClinicSetting` row every print view and the admin
 * settings screen already use (see `routes/web.php`'s `/` route) — real
 * data for this install, not placeholder copy. Stats are real counts
 * too, not made-up marketing numbers.
 *
 * Bilingual (AR/EN) via a local toggle, not a full i18n system — nothing
 * else in this app has one, and a client-side toggle scoped to this one
 * public page is proportionate to what was asked. Static chrome (nav,
 * section headings, feature copy) fully translates; admin-entered
 * `clinic` fields display as entered (translating database content would
 * be inventing text nobody wrote).
 */
import BrandMark from '@/Components/BrandMark.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link, usePage } from '@inertiajs/vue3';
import { computed, ref } from 'vue';

const props = defineProps({
    clinic: { type: Object, required: true },
    stats: { type: Object, required: true },
});

const page = usePage();

const lang = ref('ar');
const isRtl = computed(() => lang.value === 'ar');
const dir = computed(() => (isRtl.value ? 'rtl' : 'ltr'));

const strings = {
    ar: {
        nav: { login: 'تسجيل الدخول', board: 'شاشة الانتظار' },
        hero: {
            eyebrow: 'مستشفى تعليمي',
            fallbackTitle: 'المستشفى التعليمي لطب الأسنان',
            ctaLogin: 'تسجيل الدخول',
            ctaBoard: 'عرض شاشة الانتظار',
        },
        stats: {
            doctors: 'طبيب مسجّل',
            departments: 'أقسام سريرية',
            stages: 'مراحل دراسية',
            educationTypes: 'أنواع تعليم',
        },
        features: {
            title: 'نظام إدارة متكامل',
            subtitle: 'من استقبال المريض إلى تقييم المهمة السريرية، في مكان واحد.',
            items: [
                { icon: 'how_to_reg', title: 'إدارة المرضى', desc: 'تسجيل المرضى، سجلاتهم، ورموز QR للدفع عند الاستقبال.' },
                { icon: 'event', title: 'المواعيد', desc: 'جدولة المواعيد ومتابعتها لكل مريض ومرحلة.' },
                { icon: 'monitoring', title: 'تقدم المهام', desc: 'متابعة تقدّم الطلاب في المهام السريرية أولاً بأول.' },
                { icon: 'dentistry', title: 'المخططات السنية', desc: 'مخططات أسنان تفاعلية وسجلات سريرية كاملة.' },
                { icon: 'payments', title: 'المدفوعات', desc: 'تسجيل الدفعات وربطها بالمريض أو الموعد.' },
                { icon: 'school', title: 'الهيكل الأكاديمي', desc: 'أنواع تعليم، مراحل، وأقسام قابلة للتخصيص بالكامل.' },
            ],
        },
        about: {
            title: 'معلومات التواصل',
            hours: 'ساعات العمل',
            address: 'العنوان',
            phone: 'الهاتف',
            email: 'البريد الإلكتروني',
            website: 'الموقع الإلكتروني',
        },
        footer: { rights: 'جميع الحقوق محفوظة.' },
        langToggle: 'English',
    },
    en: {
        nav: { login: 'Log in', board: 'Waiting Board' },
        hero: {
            eyebrow: 'Teaching Hospital',
            fallbackTitle: 'Dental Teaching Hospital',
            ctaLogin: 'Log in',
            ctaBoard: 'View Waiting Board',
        },
        stats: {
            doctors: 'Registered Doctors',
            departments: 'Clinical Departments',
            stages: 'Academic Stages',
            educationTypes: 'Education Types',
        },
        features: {
            title: 'A Complete Clinic Management System',
            subtitle: 'From patient check-in to clinical task grading, all in one place.',
            items: [
                { icon: 'how_to_reg', title: 'Patient Management', desc: 'Patient registration, records, and desk payment QR codes.' },
                { icon: 'event', title: 'Appointments', desc: 'Schedule and track appointments per patient and stage.' },
                { icon: 'monitoring', title: 'Task Progress', desc: 'Track student progress on clinical tasks in real time.' },
                { icon: 'dentistry', title: 'Dental Charts', desc: 'Interactive dental charts and full clinical records.' },
                { icon: 'payments', title: 'Payments', desc: 'Record payments linked to a patient or an appointment.' },
                { icon: 'school', title: 'Academic Structure', desc: 'Fully customizable education types, stages, and departments.' },
            ],
        },
        about: {
            title: 'Contact Information',
            hours: 'Working Hours',
            address: 'Address',
            phone: 'Phone',
            email: 'Email',
            website: 'Website',
        },
        footer: { rights: 'All rights reserved.' },
        langToggle: 'العربية',
    },
};

const t = computed(() => strings[lang.value]);

const heroTitle = computed(() => {
    if (props.clinic.collegeName) {
        return props.clinic.universityName
            ? `${props.clinic.collegeName} — ${props.clinic.universityName}`
            : props.clinic.collegeName;
    }
    return props.clinic.name || t.value.hero.fallbackTitle;
});

const hasContactInfo = computed(() =>
    Boolean(
        props.clinic.workingHours || props.clinic.address || props.clinic.phone
            || props.clinic.email || props.clinic.website,
    ),
);

const statTiles = computed(() => [
    { value: props.stats.doctors, label: t.value.stats.doctors },
    { value: props.stats.departments, label: t.value.stats.departments },
    { value: props.stats.stages, label: t.value.stats.stages },
    { value: props.stats.educationTypes, label: t.value.stats.educationTypes },
]);

const year = new Date().getFullYear();
</script>

<template>
    <Head :title="clinic.name || 'Dental Clinic'" />

    <div :dir="dir" class="min-h-screen bg-app text-content">
        <!-- Ambient accent wash, matching the auth shell's own decoration. -->
        <div aria-hidden="true" class="pointer-events-none fixed inset-0 overflow-hidden">
            <div class="absolute -start-32 -top-32 h-96 w-96 rounded-full bg-accent/20 blur-3xl"></div>
            <div class="absolute -bottom-40 -end-24 h-[28rem] w-[28rem] rounded-full bg-accent-deep/15 blur-3xl"></div>
        </div>

        <div class="relative">
            <!-- Header -->
            <header class="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-5 sm:px-6 lg:px-8">
                <div class="flex min-w-0 items-center gap-3">
                    <img
                        v-if="clinic.universityLogoUrl || clinic.logoUrl"
                        :src="clinic.universityLogoUrl || clinic.logoUrl"
                        alt=""
                        class="h-11 w-11 shrink-0 rounded-xl object-contain"
                    />
                    <BrandMark v-else :size="44" />
                    <div class="min-w-0">
                        <p class="truncate text-sm font-semibold text-content sm:text-base">
                            {{ clinic.name || t.hero.fallbackTitle }}
                        </p>
                        <p v-if="clinic.collegeName" class="truncate text-xs text-muted">{{ clinic.collegeName }}</p>
                    </div>
                </div>

                <div class="flex shrink-0 items-center gap-2 sm:gap-3">
                    <button
                        type="button"
                        @click="lang = lang === 'ar' ? 'en' : 'ar'"
                        class="flex items-center gap-1.5 rounded-xl border border-hairline/70 bg-surface px-3 py-2 text-sm font-medium text-content transition hover:border-accent/50"
                    >
                        <Icon name="language" size="text-[18px]" />
                        <span class="hidden sm:inline">{{ t.langToggle }}</span>
                    </button>
                    <Link
                        v-if="page.props.canLogin"
                        :href="route('login')"
                        class="flex items-center gap-1.5 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-4 py-2 text-sm font-semibold text-accent-fg shadow-glow transition hover:brightness-110"
                    >
                        <Icon name="login" size="text-[18px]" />
                        {{ t.nav.login }}
                    </Link>
                </div>
            </header>

            <!-- Hero -->
            <section class="mx-auto max-w-5xl px-4 pb-16 pt-8 text-center sm:px-6 sm:pb-24 sm:pt-14 lg:px-8">
                <span class="inline-flex items-center gap-2 rounded-full border border-accent/30 bg-accent/10 px-4 py-1.5 text-xs font-semibold uppercase tracking-wide text-accent">
                    <Icon name="verified" size="text-[16px]" />
                    {{ t.hero.eyebrow }}
                </span>

                <h1 class="mt-6 text-3xl font-bold leading-tight tracking-tight text-content sm:text-5xl">
                    {{ heroTitle }}
                </h1>

                <p v-if="clinic.description" class="mx-auto mt-5 max-w-2xl text-base leading-relaxed text-muted sm:text-lg">
                    {{ clinic.description }}
                </p>

                <div class="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
                    <Link
                        v-if="page.props.canLogin"
                        :href="route('login')"
                        class="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-br from-accent to-accent-deep px-6 py-3.5 font-semibold text-accent-fg shadow-glow transition hover:brightness-110 sm:w-auto"
                    >
                        <Icon name="login" size="text-[20px]" />
                        {{ t.hero.ctaLogin }}
                    </Link>
                    <Link
                        :href="route('tv-board')"
                        class="flex w-full items-center justify-center gap-2 rounded-xl border border-hairline bg-surface px-6 py-3.5 font-semibold text-content transition hover:border-accent/50 hover:bg-surface-2 sm:w-auto"
                    >
                        <Icon name="tv" size="text-[20px]" />
                        {{ t.hero.ctaBoard }}
                    </Link>
                </div>
            </section>

            <!-- Stats -->
            <section class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
                <div class="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
                    <div
                        v-for="tile in statTiles"
                        :key="tile.label"
                        class="rounded-card border border-hairline/70 bg-surface p-5 text-center shadow-panel sm:p-6"
                    >
                        <p class="text-3xl font-bold text-accent sm:text-4xl">{{ tile.value }}</p>
                        <p class="mt-1.5 text-xs text-muted sm:text-sm">{{ tile.label }}</p>
                    </div>
                </div>
            </section>

            <!-- Features -->
            <section class="mx-auto max-w-6xl px-4 py-20 sm:px-6 sm:py-28 lg:px-8">
                <div class="mx-auto max-w-2xl text-center">
                    <h2 class="text-2xl font-bold text-content sm:text-3xl">{{ t.features.title }}</h2>
                    <p class="mt-3 text-muted">{{ t.features.subtitle }}</p>
                </div>

                <div class="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    <div
                        v-for="item in t.features.items"
                        :key="item.title"
                        class="rounded-card border border-hairline/70 bg-surface p-6 shadow-panel transition hover:border-accent/40"
                    >
                        <span class="inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-accent to-accent-deep text-accent-fg shadow-glow">
                            <Icon :name="item.icon" size="text-[22px]" />
                        </span>
                        <h3 class="mt-4 font-semibold text-content">{{ item.title }}</h3>
                        <p class="mt-1.5 text-sm leading-relaxed text-muted">{{ item.desc }}</p>
                    </div>
                </div>
            </section>

            <!-- Contact / about -->
            <section v-if="hasContactInfo" class="mx-auto max-w-4xl px-4 pb-20 sm:px-6 lg:px-8">
                <div class="rounded-card border border-hairline/70 bg-surface p-7 shadow-panel sm:p-10">
                    <h2 class="text-xl font-bold text-content">{{ t.about.title }}</h2>
                    <dl class="mt-6 grid grid-cols-1 gap-5 sm:grid-cols-2">
                        <div v-if="clinic.workingHours" class="flex items-start gap-3">
                            <Icon name="schedule" size="text-[20px]" class="mt-0.5 text-accent" />
                            <div>
                                <dt class="text-xs font-medium uppercase tracking-wide text-muted">{{ t.about.hours }}</dt>
                                <dd class="mt-0.5 text-sm text-content">{{ clinic.workingHours }}</dd>
                            </div>
                        </div>
                        <div v-if="clinic.address" class="flex items-start gap-3">
                            <Icon name="location_on" size="text-[20px]" class="mt-0.5 text-accent" />
                            <div>
                                <dt class="text-xs font-medium uppercase tracking-wide text-muted">{{ t.about.address }}</dt>
                                <dd class="mt-0.5 text-sm text-content">{{ clinic.address }}</dd>
                            </div>
                        </div>
                        <div v-if="clinic.phone" class="flex items-start gap-3">
                            <Icon name="call" size="text-[20px]" class="mt-0.5 text-accent" />
                            <div>
                                <dt class="text-xs font-medium uppercase tracking-wide text-muted">{{ t.about.phone }}</dt>
                                <dd class="mt-0.5 text-sm text-content" dir="ltr" style="unicode-bidi: isolate;">{{ clinic.phone }}</dd>
                            </div>
                        </div>
                        <div v-if="clinic.email" class="flex items-start gap-3">
                            <Icon name="mail" size="text-[20px]" class="mt-0.5 text-accent" />
                            <div>
                                <dt class="text-xs font-medium uppercase tracking-wide text-muted">{{ t.about.email }}</dt>
                                <dd class="mt-0.5 text-sm text-content" dir="ltr" style="unicode-bidi: isolate;">{{ clinic.email }}</dd>
                            </div>
                        </div>
                        <div v-if="clinic.website" class="flex items-start gap-3 sm:col-span-2">
                            <Icon name="language" size="text-[20px]" class="mt-0.5 text-accent" />
                            <div>
                                <dt class="text-xs font-medium uppercase tracking-wide text-muted">{{ t.about.website }}</dt>
                                <dd class="mt-0.5 text-sm text-content" dir="ltr" style="unicode-bidi: isolate;">{{ clinic.website }}</dd>
                            </div>
                        </div>
                    </dl>
                </div>
            </section>

            <!-- Footer -->
            <footer class="border-t border-hairline/70 px-4 py-8 text-center text-xs text-muted sm:px-6 lg:px-8">
                © {{ year }} {{ clinic.name || t.hero.fallbackTitle }} — {{ t.footer.rights }}
            </footer>
        </div>
    </div>
</template>
