<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, useForm, usePage } from '@inertiajs/vue3';
import Icon from '@/Components/Icon.vue';
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
</script>

<template>
    <Head :title="t('clinicSettingsAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('clinicSettingsAdmin.title') }}</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-6 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <!-- The test-send reports the transport's real error here; without
                     this the SMTP failure text would be invisible. -->
                <div v-if="page.props.flash?.error" class="rounded-md bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <form @submit.prevent="submit" class="space-y-6">
                    <!-- Appearance. Applied app-wide from clinic_settings.theme
                         (App\Support\ThemePalette) — it drives the login screens
                         and the navigation chrome. -->
                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-1 text-sm font-semibold text-gray-700">
                            <Icon name="palette" class="ml-1" />{{ t('clinicSettingsAdmin.themeHeading') }}
                        </h3>
                        <p class="mb-4 text-xs text-gray-500">
                            {{ t('clinicSettingsAdmin.themeDesc') }}
                        </p>

                        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                            <label
                                v-for="th in themes"
                                :key="th.value"
                                class="flex cursor-pointer items-center gap-3 rounded-xl border-2 p-3 transition"
                                :class="form.theme === th.value
                                    ? 'border-indigo-500 bg-indigo-50'
                                    : 'border-gray-200 hover:border-gray-300'"
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
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-700">{{ t('clinicSettingsAdmin.basicInfoHeading') }}</h3>
                        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div class="sm:col-span-2">
                                <InputLabel for="clinic_name" :value="t('clinicSettingsAdmin.clinicNameLabel')" />
                                <TextInput id="clinic_name" v-model="form.clinic_name" type="text" class="mt-1 block w-full" required />
                                <InputError class="mt-2" :message="form.errors.clinic_name" />
                            </div>
                            <div class="sm:col-span-2">
                                <InputLabel for="clinic_description" :value="t('clinicSettingsAdmin.descriptionLabel')" />
                                <textarea id="clinic_description" v-model="form.clinic_description" rows="2" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                            </div>
                            <div>
                                <InputLabel for="clinic_phone" :value="t('clinicSettingsAdmin.phoneLabel')" />
                                <TextInput id="clinic_phone" v-model="form.clinic_phone" type="text" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="clinic_email" :value="t('clinicSettingsAdmin.emailLabel')" />
                                <TextInput id="clinic_email" v-model="form.clinic_email" type="email" class="mt-1 block w-full" />
                                <InputError class="mt-2" :message="form.errors.clinic_email" />
                            </div>
                            <div class="sm:col-span-2">
                                <InputLabel for="clinic_logo" :value="t('clinicSettingsAdmin.clinicLogoLabel')" />
                                <img v-if="settings.logo_url" :src="settings.logo_url" class="mt-1 mb-2 h-16 w-16 rounded object-contain" />
                                <input id="clinic_logo" type="file" accept="image/*" class="mt-1 block w-full text-sm text-gray-700" @input="form.clinic_logo = $event.target.files[0]" />
                                <InputError class="mt-2" :message="form.errors.clinic_logo" />
                            </div>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-700">{{ t('clinicSettingsAdmin.contactInfoHeading') }}</h3>
                        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div class="sm:col-span-2">
                                <InputLabel for="clinic_address" :value="t('clinicSettingsAdmin.addressLabel')" />
                                <textarea id="clinic_address" v-model="form.clinic_address" rows="2" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"></textarea>
                            </div>
                            <div>
                                <InputLabel for="clinic_website" :value="t('clinicSettingsAdmin.websiteLabel')" />
                                <TextInput id="clinic_website" v-model="form.clinic_website" type="url" class="mt-1 block w-full" placeholder="https://example.com" />
                                <InputError class="mt-2" :message="form.errors.clinic_website" />
                            </div>
                            <div>
                                <InputLabel for="clinic_working_hours" :value="t('clinicSettingsAdmin.workingHoursLabel')" />
                                <TextInput id="clinic_working_hours" v-model="form.clinic_working_hours" type="text" class="mt-1 block w-full" />
                            </div>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-700">{{ t('clinicSettingsAdmin.universityCollegeHeading') }}</h3>
                        <p class="mb-4 text-xs text-gray-400">{{ t('clinicSettingsAdmin.usedInPrintHeadersNote') }}</p>
                        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div>
                                <InputLabel for="university_name" :value="t('clinicSettingsAdmin.universityNameLabel')" />
                                <TextInput id="university_name" v-model="form.university_name" type="text" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="college_name" :value="t('clinicSettingsAdmin.collegeNameLabel')" />
                                <TextInput id="college_name" v-model="form.college_name" type="text" class="mt-1 block w-full" />
                            </div>
                            <div class="sm:col-span-2">
                                <InputLabel for="university_logo" :value="t('clinicSettingsAdmin.universityLogoLabel')" />
                                <img v-if="settings.university_logo_url" :src="settings.university_logo_url" class="mt-1 mb-2 h-16 w-16 rounded object-contain" />
                                <input id="university_logo" type="file" accept="image/*" class="mt-1 block w-full text-sm text-gray-700" @input="form.university_logo = $event.target.files[0]" />
                                <InputError class="mt-2" :message="form.errors.university_logo" />
                            </div>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-700">{{ t('clinicSettingsAdmin.systemHeading') }}</h3>
                        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                            <div>
                                <InputLabel for="clinic_currency" :value="t('clinicSettingsAdmin.currencyLabel')" />
                                <TextInput id="clinic_currency" v-model="form.clinic_currency" type="text" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="lab_fee" :value="t('clinicSettingsAdmin.labFeeLabel')" />
                                <TextInput id="lab_fee" v-model="form.lab_fee" type="text" inputmode="decimal" dir="ltr" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="lab_validity_days" :value="t('clinicSettingsAdmin.labValidityLabel')" />
                                <TextInput id="lab_validity_days" v-model="form.lab_validity_days" type="number" min="0" dir="ltr" class="mt-1 block w-full" />
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
                                <select id="clinic_timezone" v-model="form.clinic_timezone" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                    <option value="Asia/Baghdad">{{ t('clinicSettingsAdmin.timezoneIraq') }}</option>
                                    <option value="Asia/Riyadh">{{ t('clinicSettingsAdmin.timezoneSaudi') }}</option>
                                    <option value="Asia/Kuwait">{{ t('clinicSettingsAdmin.timezoneKuwait') }}</option>
                                    <option value="Asia/Qatar">{{ t('clinicSettingsAdmin.timezoneQatar') }}</option>
                                    <option value="Asia/Dubai">{{ t('clinicSettingsAdmin.timezoneDubai') }}</option>
                                </select>
                            </div>
                        </div>
                    </div>

                    <!-- Email (SMTP) -->
                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="text-sm font-semibold text-gray-700">{{ t('clinicSettingsAdmin.mailSectionHeading') }}</h3>
                        <p class="mt-1 text-xs text-gray-500">
                            {{ t('clinicSettingsAdmin.mailSectionDesc') }}
                        </p>

                        <div
                            class="mt-3 rounded-md p-3 text-xs"
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

                        <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div>
                                <InputLabel for="mail_host" :value="t('clinicSettingsAdmin.mailHostLabel')" />
                                <TextInput id="mail_host" v-model="form.mail_host" type="text" class="mt-1 block w-full" placeholder="smtp.gmail.com" />
                                <InputError class="mt-2" :message="form.errors.mail_host" />
                            </div>
                            <div>
                                <InputLabel for="mail_port" :value="t('clinicSettingsAdmin.mailPortLabel')" />
                                <TextInput id="mail_port" v-model="form.mail_port" type="number" class="mt-1 block w-full" placeholder="587" />
                                <InputError class="mt-2" :message="form.errors.mail_port" />
                            </div>
                            <div>
                                <InputLabel for="mail_username" :value="t('clinicSettingsAdmin.mailUsernameLabel')" />
                                <TextInput id="mail_username" v-model="form.mail_username" type="text" class="mt-1 block w-full" />
                            </div>
                            <div>
                                <InputLabel for="mail_password" :value="t('clinicSettingsAdmin.mailPasswordLabel')" />
                                <TextInput
                                    id="mail_password"
                                    v-model="form.mail_password"
                                    type="password"
                                    class="mt-1 block w-full"
                                    :placeholder="settings.mail_password_set ? t('clinicSettingsAdmin.mailPasswordPlaceholder') : ''"
                                />
                                <InputError class="mt-2" :message="form.errors.mail_password" />
                            </div>
                            <div>
                                <InputLabel for="mail_encryption" :value="t('clinicSettingsAdmin.mailEncryptionLabel')" />
                                <select id="mail_encryption" v-model="form.mail_encryption" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                                    <option value="">{{ t('clinicSettingsAdmin.mailEncryptionNone') }}</option>
                                    <option value="tls">TLS</option>
                                    <option value="ssl">SSL</option>
                                </select>
                            </div>
                            <div>
                                <InputLabel for="mail_from_address" :value="t('clinicSettingsAdmin.mailFromAddressLabel')" />
                                <TextInput id="mail_from_address" v-model="form.mail_from_address" type="email" class="mt-1 block w-full" placeholder="clinic@example.com" />
                                <InputError class="mt-2" :message="form.errors.mail_from_address" />
                            </div>
                            <div>
                                <InputLabel for="mail_from_name" :value="t('clinicSettingsAdmin.mailFromNameLabel')" />
                                <TextInput id="mail_from_name" v-model="form.mail_from_name" type="text" class="mt-1 block w-full" :placeholder="settings.clinic_name" />
                            </div>
                        </div>

                        <!-- Gmail helper -->
                        <details class="mt-4 rounded-md border border-gray-200 p-3 text-xs text-gray-600">
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
                                <TextInput id="test_to" v-model="testForm.to" type="email" class="mt-1 block w-full" placeholder="you@example.com" />
                                <InputError class="mt-2" :message="testForm.errors.to" />
                            </div>
                            <button
                                type="button"
                                :disabled="testForm.processing || !testForm.to"
                                @click="sendTest"
                                class="rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-700 disabled:opacity-40"
                            >
                                {{ testForm.processing ? t('clinicSettingsAdmin.testEmailSending') : t('clinicSettingsAdmin.testEmailSend') }}
                            </button>
                        </div>
                        <p class="mt-1 text-xs text-gray-400">
                            {{ t('clinicSettingsAdmin.testEmailSaveFirstNote') }}
                        </p>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-4 text-sm font-semibold text-gray-700">{{ t('clinicSettingsAdmin.notificationsHeading') }}</h3>
                        <p class="mb-3 text-xs text-gray-500">
                            {{ t('clinicSettingsAdmin.notificationsRequireBothNote') }}
                        </p>
                        <div class="flex flex-wrap gap-6">
                            <label class="flex items-center gap-2 text-sm text-gray-700">
                                <input type="checkbox" v-model="form.enable_notifications" class="rounded border-gray-300" />
                                {{ t('clinicSettingsAdmin.enableNotifications') }}
                            </label>
                            <label class="flex items-center gap-2 text-sm text-gray-700">
                                <input type="checkbox" v-model="form.enable_sms" class="rounded border-gray-300" />
                                {{ t('clinicSettingsAdmin.enableSms') }}
                            </label>
                            <label class="flex items-center gap-2 text-sm text-gray-700">
                                <input type="checkbox" v-model="form.enable_email" class="rounded border-gray-300" />
                                {{ t('clinicSettingsAdmin.enableEmail') }}
                            </label>
                        </div>
                    </div>

                    <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                        <h3 class="mb-2 text-sm font-semibold text-gray-700">{{ t('clinicSettingsAdmin.groupsHeading') }}</h3>
                        <label class="flex items-center gap-2 text-sm text-gray-700">
                            <input type="checkbox" v-model="form.groups_enabled" class="rounded border-gray-300" />
                            {{ t('clinicSettingsAdmin.groupsEnabled') }}
                        </label>
                        <p class="mt-2 text-xs text-gray-500">{{ t('clinicSettingsAdmin.groupsNote') }}</p>
                    </div>

                    <div class="flex justify-end">
                        <PrimaryButton :disabled="form.processing">{{ t('clinicSettingsAdmin.saveSettings') }}</PrimaryButton>
                    </div>
                </form>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
