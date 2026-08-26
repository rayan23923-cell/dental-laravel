<script setup>
/**
 * Port of admin/backup.php — manual backup button, daily-auto toggle, and
 * a table of the most recent backups with download links. See
 * App\Http\Controllers\BackupController for what's deliberately different
 * from the original (files aren't in a public folder; the daily backup is
 * a real Laravel schedule, not a page-load side effect).
 */
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import Icon from '@/Components/Icon.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';

const props = defineProps({
    enabled: Boolean,
    lastBackupAt: String,
    files: { type: Array, default: () => [] },
});

const page = usePage();
const creating = ref(false);

const createBackup = () => {
    creating.value = true;
    router.post(route('backup.store'), {}, {
        preserveScroll: true,
        onFinish: () => (creating.value = false),
    });
};

const toggleForm = useForm({ enabled: props.enabled });
const toggleAuto = (checked) => {
    toggleForm.enabled = checked;
    toggleForm.transform((data) => ({ ...data, _method: 'put' })).post(route('backup.toggle-auto'), {
        preserveScroll: true,
    });
};

const bytesToSize = (bytes) => {
    if (!bytes) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`;
};

const formatDate = (unixSeconds) => new Date(unixSeconds * 1000).toLocaleString('ar');
</script>

<template>
    <Head title="النسخ الاحتياطي" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">
                <Icon name="database" class="ml-1" />النسخ الاحتياطي لقاعدة البيانات
            </h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-5xl space-y-6 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
                        <div>
                            <p class="text-sm text-gray-500">
                                {{ lastBackupAt ? `آخر نسخة احتياطية: ${lastBackupAt}` : 'لا يوجد نسخ سابق' }}
                            </p>
                        </div>
                        <label class="flex items-center gap-2 text-sm text-gray-700">
                            <input
                                type="checkbox"
                                :checked="enabled"
                                class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                                @change="toggleAuto($event.target.checked)"
                            />
                            تفعيل النسخ اليومي التلقائي
                        </label>
                    </div>

                    <button
                        type="button"
                        :disabled="creating"
                        class="mb-4 inline-flex items-center rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
                        @click="createBackup"
                    >
                        <Icon :name="creating ? 'progress_activity' : 'download'" class="ml-1" :class="creating ? 'animate-spin' : ''" />
                        {{ creating ? 'جاري الإنشاء...' : 'إنشاء نسخة احتياطية الآن' }}
                    </button>

                    <div class="mb-4 rounded-md bg-sky-50 p-3 text-sm text-sky-800">
                        <Icon name="info" class="ml-1" />
                        يتم تشغيل النسخ اليومي تلقائيًا عبر جدولة لارافل (وليس عند فتح الصفحة فقط)، ويُحفظ كل نسخة في تخزين الخادم الخاص — غير متاح للتحميل المباشر إلا من هذه الصفحة.
                    </div>

                    <div class="overflow-x-auto">
                        <table class="min-w-full divide-y divide-gray-200 text-sm">
                            <thead>
                                <tr class="text-right text-xs font-semibold uppercase tracking-wide text-gray-500">
                                    <th class="px-3 py-2">الملف</th>
                                    <th class="px-3 py-2">الحجم</th>
                                    <th class="px-3 py-2">التاريخ</th>
                                    <th class="px-3 py-2 text-center">تنزيل</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-100">
                                <tr v-if="files.length === 0">
                                    <td colspan="4" class="px-3 py-6 text-center text-gray-400">لا توجد نسخ احتياطية بعد</td>
                                </tr>
                                <tr v-for="f in files" :key="f.name">
                                    <td class="px-3 py-2 font-mono text-xs">{{ f.name }}</td>
                                    <td class="px-3 py-2">{{ bytesToSize(f.size) }}</td>
                                    <td class="px-3 py-2">{{ formatDate(f.mtime) }}</td>
                                    <td class="px-3 py-2 text-center">
                                        <a
                                            :href="route('backup.download', f.name)"
                                            class="inline-flex items-center rounded-md border border-indigo-300 px-2 py-1 text-xs text-indigo-700 hover:bg-indigo-50"
                                        >
                                            <Icon name="cloud_download" class="ml-1" />تحميل
                                        </a>
                                    </td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
