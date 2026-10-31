<script setup>
/**
 * Bulk accounts and login emails, super admins only (2026-10-31, by
 * request). On the hosting: create the teachers / reset a stage's
 * passwords, which emails everyone and downloads the login file; on the
 * offline clinic server (no internet): upload that file in the last card
 * to save the same accounts and passwords there.
 * See App\Http\Controllers\BulkCredentialsController.
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, Link } from '@inertiajs/vue3';
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    stages: { type: Array, default: () => [] },
    mailConfigured: { type: Boolean, default: false },
    defaults: { type: Object, default: () => ({}) },
});

const input = 'block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500';
const links = reactive({ login_url: props.defaults.login_url ?? '', alt_url: props.defaults.alt_url ?? '' });
const sendEmail = ref(props.mailConfigured);

const teachersFile = ref(null);
const applyFile = ref(null);
const stageIds = ref([]);
const busy = ref('');
const error = ref('');
const result = ref(null);

const selectedDoctors = computed(() => props.stages.filter((s) => stageIds.value.includes(s.id)).reduce((n, s) => n + s.with_email, 0));

const errorText = (e) => {
    const errors = e?.response?.data?.errors;
    return errors ? Object.values(errors).flat().join(' ') : (e?.response?.data?.message ?? t('bulkCredentials.failed'));
};

const csvCell = (v) => `"${String(v ?? '').replaceAll('"', '""')}"`;
const downloadCredentials = (rows, name) => {
    const cols = ['name', 'email', 'username', 'password', 'account_type'];
    const text = '﻿' + [cols.join(','), ...rows.map((r) => cols.map((c) => csvCell(r[c])).join(','))].join('\r\n');
    const url = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `${name}-${new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-')}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
};

const run = async (kind, url, body, confirmText) => {
    if (confirmText && !window.confirm(confirmText)) return;
    busy.value = kind;
    error.value = '';
    result.value = null;
    try {
        const { data } = await window.axios.post(url, body);
        result.value = { kind, ...data };
        if (data.credentials?.length) downloadCredentials(data.credentials, kind === 'teachers' ? 'teachers-logins' : 'doctors-logins');
    } catch (e) {
        error.value = errorText(e);
    } finally {
        busy.value = '';
    }
};

const withLinks = (fd) => {
    fd.append('login_url', links.login_url);
    fd.append('alt_url', links.alt_url);
    return fd;
};

const importTeachers = () => {
    if (!teachersFile.value) return;
    const fd = withLinks(new FormData());
    fd.append('file', teachersFile.value);
    fd.append('send_email', sendEmail.value ? '1' : '0');
    run('teachers', route('bulk-credentials.teachers'), fd, t('bulkCredentials.teachersConfirm'));
};

const resetDoctors = () => {
    if (!stageIds.value.length) return;
    run(
        'doctors',
        route('bulk-credentials.doctors'),
        { stage_ids: stageIds.value, send_email: sendEmail.value, ...links },
        t('bulkCredentials.doctorsConfirm', { count: selectedDoctors.value }),
    );
};

const applyLogins = () => {
    if (!applyFile.value) return;
    const fd = new FormData();
    fd.append('file', applyFile.value);
    run('apply', route('bulk-credentials.apply'), fd, t('bulkCredentials.applyConfirm'));
};
</script>

<template>
    <Head :title="t('bulkCredentials.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center gap-3">
                <Link :href="route('users.index')" class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200">
                    <Icon name="arrow_forward" class="rtl:block ltr:hidden" />
                    <Icon name="arrow_back" class="ltr:block rtl:hidden" />
                </Link>
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('bulkCredentials.title') }}</h2>
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <p class="text-sm text-gray-600">{{ t('bulkCredentials.intro') }}</p>

                <div v-if="error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700">{{ error }}</div>
                <div v-if="result" class="space-y-2 rounded-xl bg-green-50 p-4 text-sm text-green-800">
                    <p v-if="result.kind === 'apply'">{{ t('bulkCredentials.applyResult', { created: result.created, updated: result.updated }) }}</p>
                    <p v-else>{{ t(sendEmail ? 'bulkCredentials.emailResult' : 'bulkCredentials.fileResult', { count: result.count }) }}</p>
                    <div v-if="result.skipped?.length" class="text-amber-800">
                        <p class="font-medium">{{ t('bulkCredentials.skipped', { count: result.skipped.length }) }}</p>
                        <ul class="list-inside list-disc">
                            <li v-for="s in result.skipped" :key="(s.email ?? s.username) + s.reason">{{ s.name }} ({{ s.email ?? s.username }}): {{ s.reason }}</li>
                        </ul>
                    </div>
                    <div v-if="result.no_email?.length" class="text-amber-800">
                        <p class="font-medium">{{ t('bulkCredentials.noEmail', { count: result.no_email.length }) }}</p>
                        <p>{{ result.no_email.map((d) => d.name).join('، ') }}</p>
                    </div>
                </div>

                <!-- Where the emails point, and how they go out -->
                <section class="space-y-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <h3 class="flex items-center gap-2 font-semibold text-gray-800"><Icon name="link" />{{ t('bulkCredentials.linksTitle') }}</h3>
                    <label class="block text-sm text-gray-700">{{ t('bulkCredentials.loginUrl') }}
                        <input v-model="links.login_url" type="url" dir="ltr" :class="input" class="mt-1" />
                    </label>
                    <label class="block text-sm text-gray-700">{{ t('bulkCredentials.altUrl') }}
                        <input v-model="links.alt_url" type="url" dir="ltr" :class="input" class="mt-1" />
                    </label>
                    <label class="flex items-start gap-2 pt-1 text-sm" :class="{ 'opacity-50': !mailConfigured }">
                        <input v-model="sendEmail" type="checkbox" class="mt-0.5 rounded" :disabled="!mailConfigured" />
                        <span>{{ t('bulkCredentials.sendEmail') }}<span v-if="!mailConfigured" class="block text-xs text-gray-500">{{ t('bulkCredentials.noMail') }}</span></span>
                    </label>
                </section>

                <!-- Teachers -->
                <section class="space-y-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <h3 class="flex items-center gap-2 font-semibold text-gray-800"><Icon name="school" />{{ t('bulkCredentials.teachersTitle') }}</h3>
                    <p class="text-sm text-gray-600">{{ t('bulkCredentials.teachersHelp') }}</p>
                    <input type="file" accept=".csv,.xlsx,.xls" class="block w-full text-sm" @change="teachersFile = $event.target.files[0] ?? null" />
                    <button type="button" class="inline-flex items-center gap-2 rounded-full bg-indigo-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50" :disabled="!teachersFile || !!busy" @click="importTeachers">
                        <Icon name="person_add" />{{ busy === 'teachers' ? t('bulkCredentials.working') : t('bulkCredentials.teachersButton') }}
                    </button>
                </section>

                <!-- Doctors of whole stages -->
                <section class="space-y-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <h3 class="flex items-center gap-2 font-semibold text-gray-800"><Icon name="lock_reset" />{{ t('bulkCredentials.doctorsTitle') }}</h3>
                    <p class="text-sm text-gray-600">{{ t('bulkCredentials.doctorsHelp') }}</p>
                    <div class="space-y-1">
                        <label v-for="s in stages" :key="s.id" class="flex items-center gap-2 text-sm">
                            <input v-model="stageIds" type="checkbox" :value="s.id" class="rounded" />
                            <span>{{ s.name }}<span v-if="s.education_type" class="text-gray-500"> · {{ s.education_type }}</span></span>
                            <span class="ms-auto text-xs text-gray-500">{{ t('bulkCredentials.stageCount', { withEmail: s.with_email, total: s.doctors }) }}</span>
                        </label>
                    </div>
                    <button type="button" class="inline-flex items-center gap-2 rounded-full bg-indigo-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50" :disabled="!stageIds.length || !!busy" @click="resetDoctors">
                        <Icon name="lock_reset" />{{ busy === 'doctors' ? t('bulkCredentials.working') : t('bulkCredentials.doctorsButton', { count: selectedDoctors }) }}
                    </button>
                </section>

                <!-- Offline server: save a login file's accounts and passwords -->
                <section class="space-y-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-gray-100">
                    <h3 class="flex items-center gap-2 font-semibold text-gray-800"><Icon name="upload_file" />{{ t('bulkCredentials.applyTitle') }}</h3>
                    <p class="text-sm text-gray-600">{{ t('bulkCredentials.applyHelp') }}</p>
                    <input type="file" accept=".csv,.xlsx" class="block w-full text-sm" @change="applyFile = $event.target.files[0] ?? null" />
                    <button type="button" class="inline-flex items-center gap-2 rounded-full bg-indigo-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50" :disabled="!applyFile || !!busy" @click="applyLogins">
                        <Icon name="save" />{{ busy === 'apply' ? t('bulkCredentials.working') : t('bulkCredentials.applyButton') }}
                    </button>
                </section>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
