<script setup>
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import Modal from '@/Components/Modal.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import { Head, Link } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';

const { t } = useI18n();
defineProps({
    tasks: Array,
});

const showing = ref(null);
</script>

<template>
    <Head :title="t('doctorLayout.pendingTasksQr')" />

    <DoctorLayout>
        <h2 class="text-lg font-semibold text-gray-800"><Icon name="qr_code_2" class="ml-1" />{{ t('doctorLayout.pendingTasksQr') }}</h2>
        <p class="mt-1 text-sm text-gray-500">
            {{ t('tasks.pendingIntro') }}
        </p>

        <div v-if="tasks.length === 0" class="mt-4 rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
            {{ t('tasks.noPendingTasks') }}
        </div>

        <div v-else class="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2 lg:grid-cols-3">
            <div v-for="task in tasks" :key="task.id" class="rounded-lg bg-white p-4 shadow-sm">
                <h4 class="font-semibold text-indigo-700">{{ task.title }}</h4>
                <p class="mt-0.5 text-xs text-gray-500">{{ t('doctorDashboard.department') }}: {{ task.department ?? '—' }}</p>
                <div class="mt-2 flex flex-wrap gap-1 text-xs">
                    <span class="rounded-full bg-sky-100 px-2 py-0.5 text-sky-800">{{ t('dashboard.requiredLabel') }}: {{ task.required_count }}</span>
                    <span v-if="task.grade" class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">{{ t('doctorDashboard.grade') }}: {{ task.grade }}</span>
                </div>
                <p v-if="task.notes" class="mt-2 text-xs text-gray-500">{{ task.notes }}</p>
                <!-- فتح كيس شيت — same pre-instance draft as RequiredTasks.vue's
                     "فتح النموذج" (CaseSheetController::openForTask()): lets the
                     doctor start filling the sheet before the task is even
                     assigned, without needing the QR-scan/screening flow. -->
                <div class="mt-3 grid grid-cols-2 gap-1">
                    <Link
                        :href="route('doctor.case-sheet.for-task', task.id)"
                        class="block rounded-lg bg-indigo-600 px-3 py-2 text-center text-sm font-medium text-white hover:bg-indigo-700"
                    >
                        <Icon name="description" class="ml-1" />{{ t('tasks.openCaseSheet') }}
                    </Link>
                    <button type="button" class="rounded-lg bg-gray-700 px-3 py-2 text-sm font-medium text-white hover:bg-gray-800" @click="showing = task">
                        <Icon name="qr_code_2" class="ml-1" />{{ t('tasks.qrCode') }}
                    </button>
                </div>
            </div>
        </div>

        <Modal :show="showing !== null" @close="showing = null">
            <div class="p-6">
                <h3 class="text-lg font-medium text-gray-900"><Icon name="qr_code_2" class="ml-1" />{{ t('tasks.pendingQrTitle') }}</h3>
                <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <div class="flex items-center justify-center rounded-2xl bg-gray-50 p-4">
                        <img v-if="showing" :src="route('doctor.pending-qr.image', showing.id)" alt="QR" class="h-56 w-56" />
                    </div>
                    <div>
                        <div class="rounded-2xl border border-gray-100 p-4">
                            <h4 class="font-bold text-gray-900">{{ showing?.title }}</h4>
                            <p class="mt-1 text-sm text-gray-500">{{ t('doctorDashboard.department') }}: {{ showing?.department ?? '—' }}</p>
                            <p class="text-sm text-gray-500">{{ t('dashboard.requiredLabel') }}: {{ showing?.required_count }}</p>
                        </div>
                        <div class="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
                            {{ t('tasks.pendingQrCaption') }}
                        </div>
                    </div>
                </div>
                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="showing = null">{{ t('common.close') }}</SecondaryButton>
                </div>
            </div>
        </Modal>
    </DoctorLayout>
</template>
