<script setup>
/**
 * Auth shell — Instagram's own login layout (2026-08-30 redesign,
 * replacing the earlier dental-unit-panel look): a plain white/black
 * ground (`bg-white dark:bg-black`, light/dark following the OS
 * preference exactly like the Flutter app's `ThemeMode.system`), one
 * hairline-bordered box with no drop shadow, and the Instagram gradient
 * spent only on the logo mark.
 *
 * Deliberately hardcoded to the `ig-*` tokens (tailwind.config.js) rather
 * than the site's `--c-*` theme-picker variables (`App\Support\ThemePalette`):
 * this is meant to be one fixed, recognisable look for the public
 * login/landing surfaces regardless of which admin theme is active — the
 * same reasoning as the Flutter app's hand-built `InstagramColors`
 * (app_theme.dart) rather than a seeded palette. The rest of the app
 * (dashboard, admin panels) is untouched and still theme-picker driven.
 */
import BrandMark from '@/Components/BrandMark.vue';
import { Link, usePage } from '@inertiajs/vue3';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const page = usePage();
const settings = computed(() => page.props.clinicSettings || {});
const clinicName = computed(() => settings.value.name || t('guest.defaultClinicName'));
const collegeName = computed(() => settings.value.college_name || null);
const universityName = computed(() => settings.value.university_name || null);
// University logo preferred over the clinic's own, same precedence
// Welcome.vue's header already uses.
const logoUrl = computed(() => settings.value.university_logo_url || settings.value.logo_url || null);
const year = new Date().getFullYear();
</script>

<template>
    <div class="flex min-h-screen flex-col items-center justify-center bg-white px-4 py-10 dark:bg-ig-black">
        <div class="w-full max-w-[350px]">
            <div class="rounded-lg border border-ig-border-light bg-white px-10 py-8 dark:border-ig-border-dark dark:bg-ig-black">
                <Link href="/" class="mb-6 flex flex-col items-center text-center">
                    <img v-if="logoUrl" :src="logoUrl" alt="" class="h-16 w-16 rounded-2xl object-contain" />
                    <span v-else class="flex h-16 w-16 items-center justify-center rounded-2xl bg-ig-gradient">
                        <BrandMark :size="34" variant="mono" class="text-white" />
                    </span>
                    <h1 class="mt-3 text-xl font-semibold tracking-tight text-ig-near-black dark:text-ig-off-white">
                        {{ clinicName }}
                    </h1>
                    <p v-if="collegeName" class="mt-0.5 text-xs text-ig-gray">{{ collegeName }}</p>
                    <p v-if="universityName" class="text-xs text-ig-gray">{{ universityName }}</p>
                    <p v-if="!collegeName && !universityName" class="mt-0.5 text-xs text-ig-gray">
                        {{ t('guest.tagline') }}
                    </p>
                </Link>

                <slot />
            </div>

            <p class="mt-5 text-center text-xs text-ig-gray">© {{ year }} {{ clinicName }}</p>
        </div>
    </div>
</template>
