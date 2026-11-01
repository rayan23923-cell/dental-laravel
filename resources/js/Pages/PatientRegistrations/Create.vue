<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { Head, useForm } from '@inertiajs/vue3';
import axios from 'axios';
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    services: Array,
    currency: String,
    stageNames: { type: Array, default: () => [] },
    // Care cards (2026-11-01): the option shows only when switched on.
    supportCodesEnabled: { type: Boolean, default: false },
});

const form = useForm({
    name: '',
    phone: '',
    service_id: '',
    // Student discount (2026-10-25, by request): not eligible by default;
    // when ticked the server takes the service's price less its percentage.
    discount_eligible: false,
    // Students and employees are both eligible (2026-10-25), at the same
    // percentages; the stage or the workplace is optional.
    discount_type: 'student',
    discount_stage: '',
    discount_workplace: '',
    discount_person_name: '',
    // Care code (2026-11-01, by request): the card's 5 digits make the
    // service and the lab test free; sent only while the option is ticked.
    support_code: '',
});

const supportCare = ref(false);
const codeCheck = ref({ state: null, message: '' });
const toAsciiDigits = (v) => String(v ?? '').replace(/[٠-٩]/g, (d) => '٠١٢٣٤٥٦٧٨٩'.indexOf(d)).replace(/[۰-۹]/g, (d) => '۰۱۲۳۴۵۶۷۸۹'.indexOf(d)).replace(/\D/g, '').slice(0, 5);
watch(supportCare, (on) => {
    // Free care and the discount do not go together.
    if (on) form.discount_eligible = false;
    else form.support_code = '';
    codeCheck.value = { state: null, message: '' };
});
watch(() => form.discount_eligible, (on) => {
    if (on) supportCare.value = false;
});
watch(() => form.support_code, (v) => {
    const clean = toAsciiDigits(v);
    if (clean !== v) form.support_code = clean;
    codeCheck.value = { state: null, message: '' };
    if (clean.length === 5) checkCode();
});
const checkCode = async () => {
    if (form.support_code.length !== 5) return;
    codeCheck.value = { state: 'checking', message: '' };
    try {
        await axios.post(route('support-codes.check'), { code: form.support_code });
        codeCheck.value = { state: 'ok', message: t('patientReg.supportCodeValid') };
    } catch (e) {
        codeCheck.value = { state: 'bad', message: e.response?.data?.errors?.support_code?.[0] ?? e.response?.data?.message ?? '' };
    }
};

// Registration is name + phone + a priced service (2026-10-12). Services
// are picked from a horizontal row of cards (2026-10-18, by request) that
// swipes on touch and drags with the mouse; payment is mandatory and is the service's price,
// recorded by the server, so there is no amount field. A service with no
// price yet cannot be picked.
const serviceFilter = ref('');
const filteredServices = computed(() =>
    serviceFilter.value.trim()
        ? props.services.filter((s) => s.name.includes(serviceFilter.value.trim()))
        : props.services,
);
const selectedService = computed(() => props.services.find((s) => s.id === form.service_id) ?? null);
const formatPrice = (price) => `${Number(price).toLocaleString()} ${props.currency ?? ''}`.trim();
const isPriced = (service) => service.price !== null && service.price !== undefined;
const discountPercent = (service) => Number(service?.student_discount_percent ?? 50);
// Same rounding as App\Support\StudentDiscount::apply().
const amountDue = computed(() => {
    const service = selectedService.value;
    if (!service || !isPriced(service)) return null;
    const price = Number(service.price);
    if (supportCare.value) return 0;
    if (!form.discount_eligible) return price;
    const percent = Math.min(100, Math.max(0, discountPercent(service)));
    return Math.round(price * (100 - percent)) / 100;
});

const pickService = (service) => {
    if (isPriced(service)) form.service_id = service.id;
};

// The card row. Touch swipe is the browser's own scrolling; the mouse
// drags it with pointer events. A drag past a few pixels swallows the
// click that follows, so letting go over a card does not pick it.
const scroller = ref(null);
const rtl = ref(true);
const canBack = ref(false);
const canForward = ref(false);
const dragging = ref(false);
let drag = null;
let suppressClick = false;

const updateArrows = () => {
    const el = scroller.value;
    if (!el) return;
    // In RTL scrollLeft runs from 0 down to negative values.
    const offset = Math.abs(el.scrollLeft);
    canBack.value = offset > 1;
    canForward.value = offset < el.scrollWidth - el.clientWidth - 1;
};

const scrollRow = (towardEnd) => {
    const el = scroller.value;
    if (!el) return;
    const step = el.clientWidth * 0.8 * (towardEnd ? 1 : -1);
    el.scrollBy({ left: rtl.value ? -step : step, behavior: 'smooth' });
};

const onPointerDown = (e) => {
    if (e.pointerType !== 'mouse' || e.button !== 0) return;
    drag = { id: e.pointerId, x: e.clientX, left: scroller.value.scrollLeft, moved: false };
};
const onPointerMove = (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.x;
    if (!drag.moved && Math.abs(dx) < 6) return;
    if (!drag.moved) {
        drag.moved = true;
        dragging.value = true;
        // Capture only once it is a drag, so a plain click still lands on its card.
        scroller.value.setPointerCapture(e.pointerId);
    }
    scroller.value.scrollLeft = drag.left - dx;
};
const onPointerUp = (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    suppressClick = drag.moved;
    drag = null;
    dragging.value = false;
};
const onClickCapture = (e) => {
    if (!suppressClick) return;
    suppressClick = false;
    e.preventDefault();
    e.stopPropagation();
};

onMounted(() => {
    if (scroller.value) rtl.value = getComputedStyle(scroller.value).direction === 'rtl';
    updateArrows();
});
watch(filteredServices, () => nextTick(updateArrows));

const submit = () => {
    form.transform((data) => ({ ...data, support_code: supportCare.value ? data.support_code : '' }))
        .post(route('patient-registrations.store'));
};
</script>

<template>
    <Head :title="t('nav.registerPatient')" />

    <AuthenticatedLayout>
        <template #header>
            <!-- Chat-list style (2026-10-13, by request): round header button, rounded card/inputs. -->
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('nav.registerPatient') }}</h2>
                <ChatAddButton :label="t('patientReg.registryLink')" icon="list_alt" secondary :href="route('patient-registrations.index')" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <!-- Wide so the service row shows more cards at once (2026-10-18, by request). -->
            <div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
                <div class="overflow-hidden rounded-2xl bg-white p-6 shadow-sm ring-1 ring-gray-100">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div class="grid gap-6 md:grid-cols-2">
                            <div>
                                <InputLabel for="name" :value="t('patientReg.patientName')" />
                                <TextInput id="name" v-model="form.name" type="text" class="mt-1 block w-full rounded-xl" required autofocus />
                                <InputError class="mt-2" :message="form.errors.name" />
                            </div>

                            <div>
                                <InputLabel for="phone" :value="t('profile.phone')" />
                                <TextInput id="phone" v-model="form.phone" type="tel" class="mt-1 block w-full rounded-xl" dir="ltr" required />
                                <InputError class="mt-2" :message="form.errors.phone" />
                            </div>
                        </div>

                        <div>
                            <InputLabel :value="t('patientReg.serviceLabel')" />
                            <TextInput
                                v-if="services.length > 6"
                                v-model="serviceFilter"
                                type="text"
                                :placeholder="t('patientReg.filterServices')"
                                class="mt-1 block w-full rounded-xl"
                            />
                            <!-- One swipeable row; scroll-snap is off while the mouse drags so it does not fight the pointer. -->
                            <div class="relative mt-2">
                                <div
                                    ref="scroller"
                                    role="radiogroup"
                                    :aria-label="t('patientReg.serviceLabel')"
                                    class="flex gap-3 overflow-x-auto overscroll-x-contain px-1 pb-2 pt-1"
                                    :class="dragging ? 'cursor-grabbing select-none' : 'snap-x snap-mandatory'"
                                    @scroll.passive="updateArrows"
                                    @pointerdown="onPointerDown"
                                    @pointermove="onPointerMove"
                                    @pointerup="onPointerUp"
                                    @pointercancel="onPointerUp"
                                    @click.capture="onClickCapture"
                                    @dragstart.prevent
                                >
                                    <button
                                        v-for="service in filteredServices"
                                        :key="service.id"
                                        type="button"
                                        role="radio"
                                        :aria-checked="form.service_id === service.id"
                                        :disabled="!isPriced(service)"
                                        @click="pickService(service)"
                                        class="flex min-h-[5.5rem] w-36 shrink-0 snap-start flex-col items-center justify-center gap-1 rounded-2xl border-2 p-3 text-center transition sm:w-40"
                                        :class="
                                            form.service_id === service.id
                                                ? 'border-indigo-600 bg-indigo-50 ring-2 ring-indigo-200'
                                                : isPriced(service)
                                                  ? 'border-gray-200 bg-white hover:border-indigo-300'
                                                  : 'cursor-not-allowed border-dashed border-gray-200 bg-gray-50 opacity-60'
                                        "
                                    >
                                        <span class="line-clamp-2 font-semibold text-gray-900">{{ service.name }}</span>
                                        <span v-if="isPriced(service)" class="text-sm text-indigo-700" dir="ltr">{{ formatPrice(service.price) }}</span>
                                        <span v-else class="text-xs text-amber-700">{{ t('patientReg.noPriceYet') }}</span>
                                    </button>
                                </div>
                                <!-- Arrows for desktop; touch screens swipe instead. -->
                                <button
                                    v-show="canBack"
                                    type="button"
                                    tabindex="-1"
                                    :title="t('patientReg.scrollServicesBack')"
                                    @click="scrollRow(false)"
                                    class="absolute top-1/2 hidden h-8 w-8 -translate-y-1/2 items-center justify-center rounded-full bg-white text-gray-700 shadow ring-1 ring-gray-200 hover:bg-gray-50 sm:flex"
                                    :class="rtl ? '-right-3' : '-left-3'"
                                >
                                    <Icon :name="rtl ? 'chevron_right' : 'chevron_left'" :label="t('patientReg.scrollServicesBack')" />
                                </button>
                                <button
                                    v-show="canForward"
                                    type="button"
                                    tabindex="-1"
                                    :title="t('patientReg.scrollServicesForward')"
                                    @click="scrollRow(true)"
                                    class="absolute top-1/2 hidden h-8 w-8 -translate-y-1/2 items-center justify-center rounded-full bg-white text-gray-700 shadow ring-1 ring-gray-200 hover:bg-gray-50 sm:flex"
                                    :class="rtl ? '-left-3' : '-right-3'"
                                >
                                    <Icon :name="rtl ? 'chevron_left' : 'chevron_right'" :label="t('patientReg.scrollServicesForward')" />
                                </button>
                            </div>
                            <InputError class="mt-2" :message="form.errors.service_id" />
                            <p v-if="services.length === 0" class="mt-2 text-sm text-amber-600">{{ t('patientReg.noServicesYet') }}</p>
                        </div>

                        <!-- Care card (2026-11-01, by request): neutral wording on purpose. -->
                        <div v-if="supportCodesEnabled" class="space-y-3">
                            <label class="flex cursor-pointer items-center gap-3 rounded-xl border border-gray-200 px-4 py-3" :class="supportCare ? 'border-teal-500 bg-teal-50/60' : ''">
                                <input v-model="supportCare" type="checkbox" class="h-5 w-5 rounded border-gray-300 text-teal-600 focus:ring-teal-500" />
                                <Icon name="volunteer_activism" class="text-teal-700" />
                                <span class="text-sm font-medium text-gray-800">{{ t('patientReg.supportCare') }}</span>
                            </label>
                            <div v-if="supportCare" class="rounded-xl bg-teal-50/60 p-4">
                                <InputLabel for="support_code" :value="t('patientReg.supportCodeLabel')" />
                                <div class="mt-1 flex gap-2">
                                    <TextInput
                                        id="support_code"
                                        v-model="form.support_code"
                                        type="text"
                                        inputmode="numeric"
                                        maxlength="5"
                                        autocomplete="off"
                                        dir="ltr"
                                        placeholder="•••••"
                                        class="block w-40 rounded-xl text-center font-mono text-xl tracking-[0.4em]"
                                        required
                                    />
                                    <button type="button" class="rounded-full border border-teal-600 px-4 text-sm font-semibold text-teal-700 hover:bg-teal-100" @click="checkCode">
                                        {{ t('patientReg.supportCodeCheck') }}
                                    </button>
                                </div>
                                <p class="mt-2 text-xs text-gray-600">{{ t('patientReg.supportCareHint') }}</p>
                                <p v-if="codeCheck.state === 'ok'" class="mt-2 flex items-center gap-1 text-sm font-semibold text-teal-700"><Icon name="check_circle" />{{ codeCheck.message }}</p>
                                <p v-else-if="codeCheck.state === 'bad'" class="mt-2 flex items-center gap-1 text-sm font-semibold text-red-600"><Icon name="error" />{{ codeCheck.message }}</p>
                                <InputError class="mt-2" :message="form.errors.support_code" />
                            </div>
                        </div>

                        <label class="flex cursor-pointer items-center gap-3 rounded-xl border border-gray-200 px-4 py-3">
                            <input v-model="form.discount_eligible" type="checkbox" class="h-5 w-5 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500" />
                            <span class="text-sm font-medium text-gray-800">{{ t('patientReg.discountEligible') }}</span>
                            <span v-if="form.discount_eligible && selectedService" class="ms-auto text-xs text-indigo-700">
                                {{ t('patientReg.discountPercentOff', { percent: discountPercent(selectedService) }) }}
                            </span>
                        </label>
                        <InputError :message="form.errors.discount_eligible" />

                        <div v-if="form.discount_eligible" class="grid gap-4 rounded-xl bg-indigo-50/50 p-4 md:grid-cols-2">
                            <div role="radiogroup" :aria-label="t('patientReg.discountTypeLabel')">
                                <InputLabel :value="t('patientReg.discountTypeLabel')" />
                                <div class="mt-1 flex gap-2">
                                    <button
                                        v-for="type in ['student', 'employee']"
                                        :key="type"
                                        type="button"
                                        role="radio"
                                        :aria-checked="form.discount_type === type"
                                        @click="form.discount_type = type"
                                        class="flex-1 rounded-xl border-2 px-3 py-2 text-sm font-semibold transition"
                                        :class="form.discount_type === type ? 'border-indigo-600 bg-white text-indigo-700' : 'border-gray-200 bg-white text-gray-700 hover:border-indigo-300'"
                                    >
                                        {{ t(type === 'student' ? 'patientReg.discountStudent' : 'patientReg.discountEmployee') }}
                                    </button>
                                </div>
                                <InputError class="mt-2" :message="form.errors.discount_type" />
                            </div>
                            <!-- The student's / employee's name (2026-11-01, by request). -->
                            <div>
                                <InputLabel
                                    for="discount_person_name"
                                    :value="t(form.discount_type === 'employee' ? 'patientReg.discountEmployeeName' : 'patientReg.discountStudentName')"
                                />
                                <TextInput id="discount_person_name" v-model="form.discount_person_name" type="text" class="mt-1 block w-full rounded-xl" />
                                <InputError class="mt-2" :message="form.errors.discount_person_name" />
                            </div>
                            <div v-if="form.discount_type === 'student'">
                                <InputLabel for="discount_stage" :value="t('patientReg.discountStageLabel')" />
                                <select
                                    id="discount_stage"
                                    v-model="form.discount_stage"
                                    class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                >
                                    <option value="">{{ t('patientReg.discountStagePick') }}</option>
                                    <option v-for="name in stageNames" :key="name" :value="name">{{ name }}</option>
                                </select>
                                <InputError class="mt-2" :message="form.errors.discount_stage" />
                            </div>
                            <div v-else>
                                <InputLabel for="discount_workplace" :value="t('patientReg.discountWorkplaceLabel')" />
                                <TextInput id="discount_workplace" v-model="form.discount_workplace" type="text" class="mt-1 block w-full rounded-xl" />
                                <InputError class="mt-2" :message="form.errors.discount_workplace" />
                            </div>
                        </div>

                        <!-- A discounted patient sees the amount, the discount and the
                             amount after it (2026-10-25, by request). -->
                        <div v-if="selectedService && form.discount_eligible && selectedService.price != null" class="space-y-1 rounded-xl bg-gray-50 px-4 py-3 text-sm">
                            <div class="flex items-center justify-between">
                                <span class="text-gray-600">{{ t('patientReg.amountFull') }}</span>
                                <span dir="ltr" class="text-gray-700">{{ formatPrice(selectedService.price) }}</span>
                            </div>
                            <div class="flex items-center justify-between text-indigo-700">
                                <span>{{ t('patientReg.discountRow') }}</span>
                                <span dir="ltr">{{ discountPercent(selectedService) }}%</span>
                            </div>
                            <div class="flex items-center justify-between border-t border-gray-200 pt-1">
                                <span class="text-gray-600">{{ t('patientReg.amountAfterDiscount') }}</span>
                                <span dir="ltr" class="text-lg font-bold text-gray-900">{{ formatPrice(amountDue) }}</span>
                            </div>
                        </div>
                        <div v-else-if="selectedService && supportCare" class="space-y-1 rounded-xl bg-teal-50 px-4 py-3 text-sm">
                            <div class="flex items-center justify-between">
                                <span class="text-gray-600">{{ t('patientReg.amountFull') }}</span>
                                <span dir="ltr" class="text-gray-500 line-through">{{ formatPrice(selectedService.price) }}</span>
                            </div>
                            <div class="flex items-center justify-between border-t border-teal-200 pt-1">
                                <span class="font-semibold text-teal-800">{{ t('patientReg.supportFree') }}</span>
                                <span dir="ltr" class="text-lg font-bold text-teal-800">{{ formatPrice(0) }}</span>
                            </div>
                            <div class="text-xs text-teal-700">{{ t('patientReg.supportLabFree') }}</div>
                        </div>
                        <div v-else-if="selectedService" class="flex items-center justify-between rounded-xl bg-gray-50 px-4 py-3">
                            <span class="text-sm text-gray-600">{{ t('patientReg.amountDue') }}</span>
                            <span dir="ltr" class="text-lg font-bold text-gray-900">{{ formatPrice(amountDue) }}</span>
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton class="rounded-full" :disabled="form.processing || !selectedService || (supportCare && form.support_code.length !== 5)">{{ t('patientReg.submitRegistration') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
