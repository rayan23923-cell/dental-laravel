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
});

const form = useForm({
    name: '',
    phone: '',
    service_id: '',
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
            <div class="mx-auto max-w-2xl px-4 sm:px-6 lg:px-8">
                <div class="overflow-hidden rounded-2xl bg-white p-6 shadow-sm ring-1 ring-gray-100">
                    <form @submit.prevent="submit" class="space-y-6">
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

                        <div v-if="selectedService" class="flex items-center justify-between rounded-xl bg-gray-50 px-4 py-3">
                            <span class="text-sm text-gray-600">{{ t('patientReg.amountDue') }}</span>
                            <span class="text-lg font-bold text-gray-900" dir="ltr">{{ formatPrice(selectedService.price) }}</span>
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
