<script setup>
/**
 * Photos of a task's paper case sheet (2026-10-13, by request). Upload
 * from this device, or (staff) ask the paired phone: its scanner page
 * shows a camera button, and every photo it takes is attached here by
 * itself, page after page, until "Done". See TaskInstanceAttachmentController.
 */
import Icon from '@/Components/Icon.vue';
import PhoneScannerLink from '@/Components/PhoneScannerLink.vue';
import { onRemotePhoto, remoteScanner, requestPhonePhoto } from '@/remoteScanner';
import { shrinkImage } from '@/shrinkImage';
import axios from 'axios';
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    instanceId: { type: Number, required: true },
    // 'staff' (task progress, can use the paired phone) or 'doctor' (own cases).
    mode: { type: String, default: 'staff' },
    // Shown on the phone while it is asked for a photo, e.g. "حشوة - د. علي".
    label: { type: String, default: '' },
});
const emit = defineEmits(['changed']);

const { t } = useI18n();
const photos = ref([]);
const loading = ref(true);
const busy = ref(0);
const error = ref('');
const waiting = ref(false);
const fileInput = ref(null);

const staff = computed(() => props.mode === 'staff');
const routes = computed(() =>
    staff.value
        ? { index: 'task-progress.attachments.index', store: 'task-progress.attachments.store', destroy: 'task-progress.attachments.destroy' }
        : { index: 'doctor.task-instances.attachments.index', store: 'doctor.task-instances.attachments.store', destroy: 'doctor.task-instances.attachments.destroy' },
);
const phoneReady = computed(() => !!remoteScanner.pairing?.phone_joined);

const setPhotos = (list) => {
    photos.value = list;
    emit('changed', list.length);
};

const failed = (e) => {
    error.value = e?.response?.data?.errors ? Object.values(e.response.data.errors)[0][0] : e?.response?.data?.message || t('paperPhotos.failed');
};

onMounted(async () => {
    try {
        const { data } = await axios.get(route(routes.value.index, props.instanceId));
        setPhotos(data.data);
    } catch (e) {
        failed(e);
    } finally {
        loading.value = false;
    }
});

const upload = async (body) => {
    busy.value++;
    error.value = '';
    try {
        const { data } = await axios.post(route(routes.value.store, props.instanceId), body);
        setPhotos(data.data);
    } catch (e) {
        failed(e);
    } finally {
        busy.value--;
    }
};

const pickFiles = async (event) => {
    const files = [...(event.target.files ?? [])];
    event.target.value = '';
    for (const file of files) {
        const form = new FormData();
        form.append('photo', await shrinkImage(file));
        await upload(form);
    }
};

const remove = async (photo) => {
    if (!confirm(t('paperPhotos.confirmDelete'))) return;
    error.value = '';
    try {
        const { data } = await axios.delete(route(routes.value.destroy, photo.id));
        setPhotos(data.data);
    } catch (e) {
        failed(e);
    }
};

const askPhone = async () => {
    error.value = '';
    try {
        await requestPhonePhoto(props.label || t('paperPhotos.defaultLabel'));
        waiting.value = true;
    } catch (e) {
        failed(e);
    }
};

const stopPhone = async () => {
    waiting.value = false;
    await requestPhonePhoto('').catch(() => {});
};

// Each photo the phone sends lands here; then the phone is asked for the
// next page until "Done".
onRemotePhoto(async (scanId) => {
    await upload({ scan_id: scanId });
    if (waiting.value) await requestPhonePhoto(props.label || t('paperPhotos.defaultLabel')).catch(() => {});
});

onBeforeUnmount(() => {
    if (waiting.value) requestPhonePhoto('').catch(() => {});
});
</script>

<template>
    <div>
        <div class="flex flex-wrap items-center gap-2">
            <button
                type="button"
                class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700"
                @click="fileInput.click()"
            >
                <Icon name="upload" class="ml-1" />{{ t('paperPhotos.upload') }}
            </button>
            <input ref="fileInput" type="file" accept="image/*" multiple class="hidden" @change="pickFiles" />

            <template v-if="staff">
                <button
                    v-if="!waiting"
                    type="button"
                    :disabled="!phoneReady"
                    class="inline-flex items-center rounded-md bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-gray-300"
                    @click="askPhone"
                >
                    <Icon name="smartphone" class="ml-1" />{{ t('paperPhotos.fromPhone') }}
                </button>
                <PhoneScannerLink v-if="!phoneReady" variant="page" />
            </template>
        </div>

        <p v-if="staff && !phoneReady" class="mt-2 text-xs text-gray-500">{{ t('paperPhotos.pairFirst') }}</p>

        <div v-if="waiting" class="mt-3 flex flex-wrap items-center gap-3 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">
            <span class="relative flex h-3 w-3">
                <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75"></span>
                <span class="relative inline-flex h-3 w-3 rounded-full bg-emerald-500"></span>
            </span>
            <span class="flex-1">{{ t('paperPhotos.waitingPhone') }}</span>
            <button type="button" class="rounded-md bg-white px-3 py-1 text-sm font-medium text-emerald-700 ring-1 ring-emerald-300 hover:bg-emerald-100" @click="stopPhone">
                {{ t('paperPhotos.done') }}
            </button>
        </div>

        <div v-if="error" class="mt-3 rounded-md bg-red-50 p-3 text-sm text-red-700">{{ error }}</div>

        <div class="mt-4">
            <p v-if="loading" class="text-sm text-gray-500">{{ t('paperPhotos.loading') }}</p>
            <p v-else-if="!photos.length && !busy" class="rounded-lg bg-gray-50 p-4 text-center text-sm text-gray-500">{{ t('paperPhotos.none') }}</p>
            <div v-else class="grid grid-cols-2 gap-3 sm:grid-cols-3">
                <div v-for="photo in photos" :key="photo.id" class="group relative overflow-hidden rounded-lg border border-gray-200 bg-gray-50">
                    <a :href="photo.url" target="_blank" rel="noopener">
                        <img :src="photo.url" :alt="t('paperPhotos.title')" class="h-36 w-full object-cover" loading="lazy" />
                    </a>
                    <button
                        type="button"
                        class="absolute left-1 top-1 rounded-full bg-white/90 p-1 text-red-600 shadow hover:bg-white"
                        :title="t('common.delete')"
                        @click="remove(photo)"
                    >
                        <Icon name="delete" />
                    </button>
                </div>
                <div v-if="busy" class="flex h-36 items-center justify-center rounded-lg border border-dashed border-gray-300 text-sm text-gray-500">
                    {{ t('paperPhotos.uploading') }}
                </div>
            </div>
        </div>
    </div>
</template>
