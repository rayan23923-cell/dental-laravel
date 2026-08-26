<script setup>
/**
 * Auth shell, modelled on the dental-unit control panel: a near-black
 * ground, one raised card with a generous corner radius, and the accent
 * colour used only where the eye should land.
 *
 * Every colour comes from the theme variables (App\Support\ThemePalette),
 * so the same markup serves the light theme without a second stylesheet.
 */
import BrandMark from '@/Components/BrandMark.vue';
import { Link, usePage } from '@inertiajs/vue3';
import { computed } from 'vue';

const page = usePage();
const clinicName = computed(() => page.props.clinicSettings?.name || 'Dental Clinic');
const logoUrl = computed(() => page.props.clinicSettings?.logo_url || null);
const year = new Date().getFullYear();
</script>

<template>
    <div class="relative flex min-h-screen flex-col items-center justify-center overflow-hidden bg-app px-4 py-10">
        <!-- Ambient accent wash. Decorative only, and kept well behind the
             card so it never competes with the form. -->
        <div aria-hidden="true" class="pointer-events-none absolute inset-0">
            <div class="absolute -left-32 -top-32 h-96 w-96 rounded-full bg-accent/20 blur-3xl"></div>
            <div class="absolute -bottom-40 -right-24 h-[28rem] w-[28rem] rounded-full bg-accent-deep/15 blur-3xl"></div>
        </div>

        <div class="relative w-full max-w-md">
            <div class="mb-7 flex flex-col items-center text-center">
                <Link href="/" class="mb-4 inline-flex items-center justify-center">
                    <img v-if="logoUrl" :src="logoUrl" alt="" class="h-16 w-16 rounded-2xl object-contain" />
                    <BrandMark v-else :size="64" />
                </Link>
                <h1 class="text-2xl font-semibold tracking-tight text-content">{{ clinicName }}</h1>
                <p class="mt-1 text-sm text-muted">نظام إدارة العيادة التعليمية</p>
            </div>

            <div class="rounded-card border border-hairline/70 bg-surface p-7 shadow-panel">
                <slot />
            </div>

            <p class="mt-6 text-center text-xs text-muted">© {{ year }} {{ clinicName }}</p>
        </div>
    </div>
</template>
