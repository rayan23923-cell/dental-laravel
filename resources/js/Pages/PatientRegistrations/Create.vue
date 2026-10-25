<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import Icon from '@/Components/Icon.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import { Head, useForm } from '@inertiajs/vue3';
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    services: Array,
    currency: String,
    stageNames: { type: Array, default: () => [] },
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
});

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
    form.post(route('patient-registrations.store'));
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
                            <div v-if="form.discount_type === 'student'">
                                <InputLabel for="discount_stage" :value="t('patientReg.discountStageLabel')" />
                                <TextInput id="discount_stage" v-model="form.discount_stage" type="text" list="discount_stage_names" class="mt-1 block w-full rounded-xl" />
                                <datalist id="discount_stage_names">
                                    <option v-for="name in stageNames" :key="name" :value="name" />
                                </datalist>
                                <InputError class="mt-2" :message="form.errors.discount_stage" />
                            </div>
                            <div v-else>
                                <InputLabel for="discount_workplace" :value="t('patientReg.discountWorkplaceLabel')" />
                                <TextInput id="discount_workplace" v-model="form.discount_workplace" type="text" class="mt-1 block w-full rounded-xl" />
                                <InputError class="mt-2" :message="form.errors.discount_workplace" />
                            </div>
                        </div>

                        <div v-if="selectedService" class="flex items-center justify-between rounded-xl bg-gray-50 px-4 py-3">
                            <span class="text-sm text-gray-600">{{ t('patientReg.amountDue') }}</span>
                            <span class="flex items-baseline gap-2" dir="ltr">
                                <span v-if="form.discount_eligible" class="text-sm text-gray-400 line-through">{{ formatPrice(selectedService.price) }}</span>
                                <span class="text-lg font-bold text-gray-900">{{ formatPrice(amountDue) }}</span>
                            </span>
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton class="rounded-full" :disabled="form.processing || !selectedService">{{ t('patientReg.submitRegistration') }}</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
