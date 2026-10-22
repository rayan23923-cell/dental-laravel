<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm, usePage } from '@inertiajs/vue3';
import Icon from '@/Components/Icon.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import SettingsSection from '@/Components/ChatList/SettingsSection.vue';
import SettingsToggle from '@/Components/ChatList/SettingsToggle.vue';
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    settings: Object,
    mailConfigured: Boolean,
    mailDriver: String,
    // Palettes from App\Support\ThemePalette.
    themes: { type: Array, default: () => [] },
});

const page = usePage();

const form = useForm({
    clinic_name: props.settings.clinic_name ?? '',
    clinic_description: props.settings.clinic_description ?? '',
    clinic_address: props.settings.clinic_address ?? '',
    clinic_phone: props.settings.clinic_phone ?? '',
    clinic_email: props.settings.clinic_email ?? '',
    clinic_website: props.settings.clinic_website ?? '',
    clinic_working_hours: props.settings.clinic_working_hours ?? '',
    clinic_currency: props.settings.clinic_currency ?? '',
    lab_fee: props.settings.lab_fee ?? '',
    lab_validity_days: props.settings.lab_validity_days ?? '',
    clinic_timezone: props.settings.clinic_timezone ?? 'Asia/Baghdad',
    theme: props.settings.theme ?? 'unit-dark',
    university_name: props.settings.university_name ?? '',
    college_name: props.settings.college_name ?? '',
    enable_notifications: !!props.settings.enable_notifications,
    enable_sms: !!props.settings.enable_sms,
    enable_email: !!props.settings.enable_email,
    groups_enabled: !!(props.settings.groups_enabled ?? true),
    // Forms and task progress switches for the whole system (2026-10-22).
    ...Object.fromEntries(
        ['electronic_forms_enabled', 'paper_forms_enabled', 'task_start_enabled', 'task_finish_enabled', 'task_lists_enabled', 'grade_entry_enabled', 'steps_enabled', 'step_add_enabled'].map((k) => [k, !!(props.settings[k] ?? true)]),
    ),
    clinic_logo: null,
    university_logo: null,
    mail_host: props.settings.mail_host ?? '',
    mail_port: props.settings.mail_port ?? '',
    mail_username: props.settings.mail_username ?? '',
    // Left blank on purpose: the stored password is never sent to the
    // browser, and submitting it blank keeps whatever is stored.
    mail_password: '',
    mail_encryption: props.settings.mail_encryption ?? '',
    mail_from_address: props.settings.mail_from_address ?? '',
    mail_from_name: props.settings.mail_from_name ?? '',
});

const submit = () => {
    form.transform((data) => ({ ...data, _method: 'put' })).post(route('clinic-settings.update'), {
        preserveScroll: true,
    });
};

// Separate form: the test send uses the *saved* settings, so it must not
// carry the (possibly unsaved) values in the main form.
const testForm = useForm({ to: '' });
const sendTest = () => testForm.post(route('clinic-settings.test-email'), { preserveScroll: true });

// Telegram-style list (2026-10-14, by request): every section is a
// collapsed row with a summary; one opens at a time, and a section with a
// validation error opens by itself after saving.
const open = reactive({});
const toggle = (key, value) => {
    for (const k of Object.keys(open)) open[k] = false;
    open[key] = value;
};
const sectionFields = {
    theme: ['theme'],
    basic: ['clinic_name', 'clinic_description', 'clinic_phone', 'clinic_email', 'clinic_logo'],
    contact: ['clinic_address', 'clinic_website', 'clinic_working_hours'],
    university: ['university_name', 'college_name', 'university_logo'],
    system: ['clinic_currency', 'lab_fee', 'lab_validity_days', 'clinic_timezone'],
    mail: ['mail_host', 'mail_port', 'mail_username', 'mail_password', 'mail_encryption', 'mail_from_address', 'mail_from_name'],
};
const hasError = (key) => sectionFields[key]?.some((f) => form.errors[f]);
watch(() => form.errors, (errors) => {
    const first = Object.keys(sectionFields).find((k) => sectionFields[k].some((f) => errors[f]));
    if (first) toggle(first, true);
});

const join = (...parts) => parts.filter((p) => p !== null && p !== undefined && String(p).trim() !== '').join(' · ');
const summaries = computed(() => ({
    theme: props.themes.find((th) => th.value === form.theme)?.label ?? '',
    basic: join(form.clinic_name, form.clinic_phone),
    contact: join(form.clinic_address, form.clinic_working_hours),
    university: join(form.university_name, form.college_name),
    system: join(form.clinic_currency, form.lab_fee && `${t('clinicSettingsAdmin.labFeeLabel')}: ${form.lab_fee}`),
    mail: props.mailConfigured ? t('clinicSettingsAdmin.mailConfiguredShort') : t('clinicSettingsAdmin.mailNotConfiguredShort'),
    notifications: [
        form.enable_notifications && t('clinicSettingsAdmin.enableNotifications'),
        form.enable_sms && 'SMS',
        form.enable_email && t('clinicSettingsAdmin.emailShort'),
    ].filter(Boolean).join('، ') || t('clinicSettingsAdmin.off'),
}));
</script>

<template>
    <Head :title="t('clinicSettingsAdmin.title')" />

    <AuthenticatedLayout>
        <!-- Settings list (2026-10-14, by request): grouped, collapsible rows
             like Telegram's settings, one save bar for the whole form. -->
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('clinicSettingsAdmin.title') }}</h2>
        </template>

        <div class="py-6 pb-28 sm:py-10 sm:pb-28">
            <div class="mx-auto max-w-3xl space-y-5 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <!-- The test-send reports the transport's real error here; without
                     this the SMTP failure text would be invisible. -->
                <div v-if="page.props.flash?.error" class="rounded-xl bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <form @submit.prevent="submit" class="space-y-5">
                    <section>
                        <h3 class="mb-2 px-2 text-xs font-semibold text-indigo-600">{{ t('clinicSettingsAdmin.groupClinic') }}</h3>
                        <ChatListCard>
                        <SettingsSection
                            :open="!!open.basic" @update:open="toggle('basic', $event)"
                            icon="store" tone="bg-indigo-500" :title="t('clinicSettingsAdmin.basicInfoHeading')"
                            :summary="summaries.basic" :has-error="hasError('basic')"
                        >
                            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                <div class="sm:col-span-2">
                                    <InputLabel for="clinic_name" :value="t('clinicSettingsAdmin.clinicNameLabel')" />
                                    <TextInput id="clinic_name" v-model="form.clinic_name" type="text" class="mt-1 block w-full rounded-xl" required />
                                    <InputError class="mt-2" :message="form.errors.clinic_name" />
                                </div>
                                <div class="sm:col-span-2">
                                    <InputLabel for="clinic_description" :value="t('clinicSettingsAdmin.descriptionLabel')" />
                                    <textarea id="clinic_description" v-model="form.clinic_description" rows="2" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                                </div>
                                <div>
                                    <InputLabel for="clinic_phone" :value="t('clinicSettingsAdmin.phoneLabel')" />
                                    <TextInput id="clinic_phone" v-model="form.clinic_phone" type="text" class="mt-1 block w-full rounded-xl" />
                                </div>
                                <div>
                                    <InputLabel for="clinic_email" :value="t('clinicSettingsAdmin.emailLabel')" />
                                    <TextInput id="clinic_email" v-model="form.clinic_email" type="email" class="mt-1 block w-full rounded-xl" />
                                    <InputError class="mt-2" :message="form.errors.clinic_email" />
                                </div>
                                <div class="sm:col-span-2">
                                    <InputLabel for="clinic_logo" :value="t('clinicSettingsAdmin.clinicLogoLabel')" />
                                    <img v-if="settings.logo_url" :src="settings.logo_url" class="mt-1 mb-2 h-16 w-16 rounded object-contain" />
                                    <input id="clinic_logo" type="file" accept="image/*" class="mt-1 block w-full text-sm text-gray-700" @input="form.clinic_logo = $event.target.files[0]" />
                                    <InputError class="mt-2" :message="form.errors.clinic_logo" />
                                </div>
                            </div>
                        </SettingsSection>
                        <SettingsSection
                            :open="!!open.contact" @update:open="toggle('contact', $event)"
                            icon="contact_phone" tone="bg-sky-500" :title="t('clinicSettingsAdmin.contactInfoHeading')"
                            :summary="summaries.contact" :has-error="hasError('contact')"
                        >
                            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                <div class="sm:col-span-2">
                                    <InputLabel for="clinic_address" :value="t('clinicSettingsAdmin.addressLabel')" />
                                    <textarea id="clinic_address" v-model="form.clinic_address" rows="2" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                                </div>
                                <div>
                                    <InputLabel for="clinic_website" :value="t('clinicSettingsAdmin.websiteLabel')" />
                                    <TextInput id="clinic_website" v-model="form.clinic_website" type="url" class="mt-1 block w-full rounded-xl" placeholder="https://example.com" />
                                    <InputError class="mt-2" :message="form.errors.clinic_website" />
                                </div>
                                <div>
                                    <InputLabel for="clinic_working_hours" :value="t('clinicSettingsAdmin.workingHoursLabel')" />
                                    <TextInput id="clinic_working_hours" v-model="form.clinic_working_hours" type="text" class="mt-1 block w-full rounded-xl" />
                                </div>
                            </div>
                        </SettingsSection>
                        <SettingsSection
                            :open="!!open.university" @update:open="toggle('university', $event)"
                            icon="school" tone="bg-violet-500" :title="t('clinicSettingsAdmin.universityCollegeHeading')"
                            :summary="summaries.university" :has-error="hasError('university')"
                        >
                            <p class="mb-3 text-xs text-gray-400">{{ t('clinicSettingsAdmin.usedInPrintHeadersNote') }}</p>
                            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                <div>
                                    <InputLabel for="university_name" :value="t('clinicSettingsAdmin.universityNameLabel')" />
                                    <TextInput id="university_name" v-model="form.university_name" type="text" class="mt-1 block w-full rounded-xl" />
                                </div>
                                <div>
                                    <InputLabel for="college_name" :value="t('clinicSettingsAdmin.collegeNameLabel')" />
                                    <TextInput id="college_name" v-model="form.college_name" type="text" class="mt-1 block w-full rounded-xl" />
                                </div>
                                <div class="sm:col-span-2">
                                    <InputLabel for="university_logo" :value="t('clinicSettingsAdmin.universityLogoLabel')" />
                                    <img v-if="settings.university_logo_url" :src="settings.university_logo_url" class="mt-1 mb-2 h-16 w-16 rounded object-contain" />
                                    <input id="university_logo" type="file" accept="image/*" class="mt-1 block w-full text-sm text-gray-700" @input="form.university_logo = $event.target.files[0]" />
                                    <InputError class="mt-2" :message="form.errors.university_logo" />
                                </div>
                            </div>
                        </SettingsSection>
                        </ChatListCard>
                    </section>

                    <section>
                        <h3 class="mb-2 px-2 text-xs font-semibold text-indigo-600">{{ t('clinicSettingsAdmin.groupSystem') }}</h3>
                        <ChatListCard>
                        <SettingsSection
                            :open="!!open.system" @update:open="toggle('system', $event)"
                            icon="tune" tone="bg-amber-500" :title="t('clinicSettingsAdmin.systemHeading')"
                            :summary="summaries.system" :has-error="hasError('system')"
                        >
                            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                <div>
                                    <InputLabel for="clinic_currency" :value="t('clinicSettingsAdmin.currencyLabel')" />
                                    <TextInput id="clinic_currency" v-model="form.clinic_currency" type="text" class="mt-1 block w-full rounded-xl" />
                                </div>
                                <div>
                                    <InputLabel for="lab_fee" :value="t('clinicSettingsAdmin.labFeeLabel')" />
                                    <TextInput id="lab_fee" v-model="form.lab_fee" type="text" inputmode="decimal" dir="ltr" class="mt-1 block w-full rounded-xl" />
                                </div>
                                <div>
                                    <InputLabel for="lab_validity_days" :value="t('clinicSettingsAdmin.labValidityLabel')" />
                                    <TextInput id="lab_validity_days" v-model="form.lab_validity_days" type="number" min="0" dir="ltr" class="mt-1 block w-full rounded-xl" />
                                </div>
                                <div>
                                    <InputLabel for="clinic_timezone" :value="t('clinicSettingsAdmin.timezoneLabel')" />
                                    <!-- Iraq listed first and named explicitly —
                                         the bootstrap default (ClinicSetting::current())
                                         names an Iraqi university, but this list
                                         previously showed only bare Gulf city
                                         names with no country attached and
                                         defaulted to Riyadh (Saudi Arabia),
                                         which read as "Iraq isn't an option
                                         here" even though Asia/Baghdad was
                                         technically present, just unlabelled
                                         and last. -->
                                    <select id="clinic_timezone" v-model="form.clinic_timezone" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                        <option value="Asia/Baghdad">{{ t('clinicSettingsAdmin.timezoneIraq') }}</option>
                                        <option value="Asia/Riyadh">{{ t('clinicSettingsAdmin.timezoneSaudi') }}</option>
                                        <option value="Asia/Kuwait">{{ t('clinicSettingsAdmin.timezoneKuwait') }}</option>
                                        <option value="Asia/Qatar">{{ t('clinicSettingsAdmin.timezoneQatar') }}</option>
                                        <option value="Asia/Dubai">{{ t('clinicSettingsAdmin.timezoneDubai') }}</option>
                                    </select>
                                </div>
                            </div>
                        </SettingsSection>
                        <SettingsSection
                            :open="!!open.theme" @update:open="toggle('theme', $event)"
                            icon="palette" tone="bg-fuchsia-500" :title="t('clinicSettingsAdmin.themeHeading')"
                            :summary="summaries.theme" :has-error="hasError('theme')"
                        >
                            <p class="mb-3 text-xs text-gray-500">{{ t('clinicSettingsAdmin.themeDesc') }}</p>
                            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                                <label
                                    v-for="th in themes"
                                    :key="th.value"
                                    class="flex cursor-pointer items-center gap-3 rounded-xl border-2 p-3 transition"
                                    :class="form.theme === th.value
                                        ? 'border-indigo-500 bg-white ring-2 ring-indigo-500/30'
                                        : 'border-gray-200 bg-white hover:border-gray-300'"
                                >
                                    <input v-model="form.theme" type="radio" :value="th.value" class="sr-only" />

                                    <!-- Live swatch: page ground plus accent, the two
                                         colours that actually distinguish the themes. -->
                                    <span
                                        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg ring-1 ring-black/10"
                                        :style="{ backgroundColor: th.swatch[0] }"
                                    >
                                        <span class="h-5 w-5 rounded-full" :style="{ backgroundColor: th.swatch[1] }"></span>
                                    </span>

                                    <span class="min-w-0">
                                        <span class="block truncate text-sm font-medium text-gray-800">{{ th.label }}</span>
                                        <span class="block text-xs text-gray-500">{{ th.description }}</span>
                                    </span>

                                    <Icon v-if="form.theme === th.value" name="check_circle" class="mr-auto text-indigo-600" />
                                </label>
                            </div>
                            <InputError class="mt-2" :message="form.errors.theme" />
                        </SettingsSection>
                            <div class="flex items-center gap-3 border-b border-gray-100 px-4 py-2 last:border-b-0">
                                <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-teal-500 text-white"><Icon name="groups" size="text-[20px]" /></span>
                                <div class="min-w-0 flex-1">
                                    <SettingsToggle v-model="form.groups_enabled" :label="t('clinicSettingsAdmin.groupsEnabled')" :hint="t('clinicSettingsAdmin.groupsNote')" />
                                </div>
                            </div>
                            <!-- Forms and task progress for the whole system (2026-10-22, by request);
                                 each user still needs the matching permission. -->
                            <div class="flex items-start gap-3 border-b border-gray-100 px-4 py-2 last:border-b-0">
                                <span class="mt-2 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-indigo-500 text-white"><Icon name="description" size="text-[20px]" /></span>
                                <div class="min-w-0 flex-1">
                                    <SettingsToggle v-model="form.electronic_forms_enabled" :label="t('formSettings.electronic')" :hint="t('formSettings.electronicHint')" />
                                    <SettingsToggle v-model="form.paper_forms_enabled" :label="t('formSettings.paper')" :hint="t('formSettings.paperHint')" />
                                    <InputError :message="form.errors.paper_forms_enabled" />
                                </div>
                            </div>
                            <div class="flex items-start gap-3 border-b border-gray-100 px-4 py-2 last:border-b-0">
                                <span class="mt-2 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-500 text-white"><Icon name="monitoring" size="text-[20px]" /></span>
                                <div class="min-w-0 flex-1">
                                    <p class="pt-2 text-sm font-medium text-gray-800">{{ t('formSettings.tasksSection') }}</p>
                                    <p class="text-xs text-gray-500">{{ t('formSettings.tasksSectionHint') }}</p>
                                    <SettingsToggle
                                        v-for="key in ['task_start_enabled', 'task_finish_enabled', 'task_lists_enabled', 'steps_enabled', 'grade_entry_enabled', 'step_add_enabled']"
                                        :key="key"
                                        v-model="form[key]"
                                        :label="t('formSettings.' + key)"
                                        :hint="t('formSettings.' + key + 'Hint')"
                                    />
                                </div>
                            </div>
                        </ChatListCard>
                    </section>

                    <section>
                        <h3 class="mb-2 px-2 text-xs font-semibold text-indigo-600">{{ t('clinicSettingsAdmin.groupMessaging') }}</h3>
                        <ChatListCard>
                        <SettingsSection
                            :open="!!open.notifications" @update:open="toggle('notifications', $event)"
                            icon="notifications" tone="bg-rose-500" :title="t('clinicSettingsAdmin.notificationsHeading')"
                            :summary="summaries.notifications" :has-error="hasError('notifications')"
                        >
                            <p class="mb-2 text-xs text-gray-500">{{ t('clinicSettingsAdmin.notificationsRequireBothNote') }}</p>
                            <div class="divide-y divide-gray-100 rounded-xl bg-white px-3 ring-1 ring-gray-100">
                                <SettingsToggle v-model="form.enable_notifications" :label="t('clinicSettingsAdmin.enableNotifications')" />
                                <SettingsToggle v-model="form.enable_sms" :label="t('clinicSettingsAdmin.enableSms')" />
                                <SettingsToggle v-model="form.enable_email" :label="t('clinicSettingsAdmin.enableEmail')" />
                            </div>
                        </SettingsSection>
                        <SettingsSection
                            :open="!!open.mail" @update:open="toggle('mail', $event)"
                            icon="mail" tone="bg-emerald-500" :title="t('clinicSettingsAdmin.mailSectionHeading')"
                            :summary="summaries.mail" :has-error="hasError('mail')"
                        >
                        <div
                            class="rounded-xl p-3 text-xs"
                            :class="mailConfigured ? 'bg-green-50 text-green-800' : 'bg-amber-50 text-amber-800'"
                        >
                            <template v-if="mailConfigured">
                                <Icon name="check_circle" class="ml-1" />{{ t('clinicSettingsAdmin.mailConfiguredMsg') }}
                            </template>
                            <template v-else>
                                <Icon name="warning" class="ml-1" />{{ t('clinicSettingsAdmin.mailNotConfiguredPrefix') }}
                                (<code>{{ mailDriver }}</code>) {{ t('clinicSettingsAdmin.mailNotConfiguredSuffix') }}
                            </template>
                        </div>
                        <p class="mt-2 text-xs text-gray-500">{{ t('clinicSettingsAdmin.mailSectionDesc') }}</p>
                            <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
                                <div>
                                    <InputLabel for="mail_host" :value="t('clinicSettingsAdmin.mailHostLabel')" />
                                    <TextInput id="mail_host" v-model="form.mail_host" type="text" class="mt-1 block w-full rounded-xl" placeholder="smtp.gmail.com" />
                                    <InputError class="mt-2" :message="form.errors.mail_host" />
                                </div>
                                <div>
                                    <InputLabel for="mail_port" :value="t('clinicSettingsAdmin.mailPortLabel')" />
                                    <TextInput id="mail_port" v-model="form.mail_port" type="number" class="mt-1 block w-full rounded-xl" placeholder="587" />
                                    <InputError class="mt-2" :message="form.errors.mail_port" />
                                </div>
                                <div>
                                    <InputLabel for="mail_username" :value="t('clinicSettingsAdmin.mailUsernameLabel')" />
                                    <TextInput id="mail_username" v-model="form.mail_username" type="text" class="mt-1 block w-full rounded-xl" />
                                </div>
                                <div>
                                    <InputLabel for="mail_password" :value="t('clinicSettingsAdmin.mailPasswordLabel')" />
                                    <TextInput
                                        id="mail_password"
                                        v-model="form.mail_password"
                                        type="password"
                                        class="mt-1 block w-full rounded-xl"
                                        :placeholder="settings.mail_password_set ? t('clinicSettingsAdmin.mailPasswordPlaceholder') : ''"
                                    />
                                    <InputError class="mt-2" :message="form.errors.mail_password" />
                                </div>
                                <div>
                                    <InputLabel for="mail_encryption" :value="t('clinicSettingsAdmin.mailEncryptionLabel')" />
                                    <select id="mail_encryption" v-model="form.mail_encryption" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                        <option value="">{{ t('clinicSettingsAdmin.mailEncryptionNone') }}</option>
                                        <option value="tls">TLS</option>
                                        <option value="ssl">SSL</option>
                                    </select>
                                </div>
                                <div>
                                    <InputLabel for="mail_from_address" :value="t('clinicSettingsAdmin.mailFromAddressLabel')" />
                                    <TextInput id="mail_from_address" v-model="form.mail_from_address" type="email" class="mt-1 block w-full rounded-xl" placeholder="clinic@example.com" />
                                    <InputError class="mt-2" :message="form.errors.mail_from_address" />
                                </div>
                                <div>
                                    <InputLabel for="mail_from_name" :value="t('clinicSettingsAdmin.mailFromNameLabel')" />
                                    <TextInput id="mail_from_name" v-model="form.mail_from_name" type="text" class="mt-1 block w-full rounded-xl" :placeholder="settings.clinic_name" />
                                </div>
                            </div>

                            <!-- Gmail helper -->
                            <details class="mt-4 rounded-xl border border-gray-200 p-3 text-xs text-gray-600">
                                <summary class="cursor-pointer font-medium text-gray-700">{{ t('clinicSettingsAdmin.gmailHelperSummary') }}</summary>
                                <div class="mt-2 space-y-2">
                                    <p class="rounded bg-amber-50 p-2 text-amber-800">
                                        <Icon name="warning" class="ml-1" /><strong>{{ t('clinicSettingsAdmin.gmailWarningBold') }}</strong>
                                        {{ t('clinicSettingsAdmin.gmailWarningRest') }}
                                    </p>
                                    <ul class="list-inside list-disc space-y-1">
                                        <li>{{ t('clinicSettingsAdmin.gmailServerLabel') }} <code class="rounded bg-gray-100 px-1">smtp.gmail.com</code></li>
                                        <li>{{ t('clinicSettingsAdmin.gmailPortLabel') }} <code class="rounded bg-gray-100 px-1">587</code> {{ t('clinicSettingsAdmin.gmailWithEncryption') }} <code class="rounded bg-gray-100 px-1">TLS</code>
                                            (أو <code class="rounded bg-gray-100 px-1">465</code> {{ t('clinicSettingsAdmin.gmailWithConnector') }} <code class="rounded bg-gray-100 px-1">SSL</code>)</li>
                                        <li>{{ t('clinicSettingsAdmin.gmailUsernameLabel') }} {{ t('clinicSettingsAdmin.gmailUsernameFullEmail') }} <code class="rounded bg-gray-100 px-1">you@gmail.com</code></li>
                                        <li>{{ t('clinicSettingsAdmin.gmailPasswordLabel') }} {{ t('clinicSettingsAdmin.gmailPasswordAppPassword') }}</li>
                                        <li>{{ t('clinicSettingsAdmin.gmailFromAddressLabel') }} <strong>{{ t('clinicSettingsAdmin.gmailFromAddressBold') }}</strong> {{ t('clinicSettingsAdmin.gmailFromAddressRest') }}</li>
                                    </ul>
                                    <p>{{ t('clinicSettingsAdmin.gmailLimitsNote') }}</p>
                                </div>
                            </details>

                            <!-- Test email -->
                            <div class="mt-4 flex flex-wrap items-end gap-2 border-t border-gray-100 pt-4">
                                <div class="min-w-0 flex-grow">
                                    <InputLabel for="test_to" :value="t('clinicSettingsAdmin.testEmailLabel')" />
                                    <TextInput id="test_to" v-model="testForm.to" type="email" class="mt-1 block w-full rounded-xl" placeholder="you@example.com" />
                                    <InputError class="mt-2" :message="testForm.errors.to" />
                                </div>
                                <button
                                    type="button"
                                    :disabled="testForm.processing || !testForm.to"
                                    @click="sendTest"
                                    class="rounded-full bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-700 disabled:opacity-40"
                                >
                                    {{ testForm.processing ? t('clinicSettingsAdmin.testEmailSending') : t('clinicSettingsAdmin.testEmailSend') }}
                                </button>
                            </div>
                            <p class="mt-1 text-xs text-gray-400">
                                {{ t('clinicSettingsAdmin.testEmailSaveFirstNote') }}
                            </p>
                        </SettingsSection>
                        </ChatListCard>
                    </section>

                    <!-- Sticky save bar: always reachable while a section is open. -->
                    <div class="fixed inset-x-0 bottom-0 z-30 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur">
                        <div class="mx-auto flex max-w-3xl items-center gap-3">
                            <span class="flex-1 text-xs" :class="form.isDirty ? 'text-amber-600' : 'text-gray-400'">
                                {{ form.isDirty ? t('clinicSettingsAdmin.unsavedChanges') : t('clinicSettingsAdmin.allSaved') }}
                            </span>
                            <button v-if="form.isDirty" type="button" class="rounded-full px-4 py-2 text-sm text-gray-600 hover:bg-gray-100" @click="form.reset()">
                                {{ t('clinicSettingsAdmin.discardChanges') }}
                            </button>
                            <PrimaryButton class="gap-1 rounded-full" :disabled="form.processing"><Icon name="save" size="text-[18px]" />{{ t('clinicSettingsAdmin.saveSettings') }}</PrimaryButton>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
