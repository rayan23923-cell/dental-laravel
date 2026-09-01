<script setup>
/**
 * Instagram-style "الأجهزة النشطة" panel — embedded in both Profile pages
 * (Profile/Edit.vue for staff, Doctor/Profile.vue for doctors). Lists this
 * account's Sanctum tokens (its mobile app logins; see
 * AccountSessionController's docblock for why the web session itself is
 * never one of the rows).
 */
import axios from 'axios';
import { onMounted, ref } from 'vue';
import Icon from '@/Components/Icon.vue';

const sessions = ref([]);
const loading = ref(true);
const busyId = ref(null);
const loggingOutAll = ref(false);

const deviceIcon = (type) => ({
    android: 'phone_android',
    ios: 'phone_iphone',
    windows: 'desktop_windows',
    macos: 'laptop_mac',
    linux: 'terminal',
    web: 'language',
}[type] ?? 'devices_other');

const formatDate = (value) => {
    if (!value) return 'لم يُستخدم بعد';
    return new Date(value).toLocaleString('ar-EG', { dateStyle: 'medium', timeStyle: 'short' });
};

const load = async () => {
    loading.value = true;
    const { data } = await axios.get(route('account.sessions.index'));
    sessions.value = data.data;
    loading.value = false;
};

const endSession = async (session) => {
    if (!confirm(`إنهاء الجلسة على "${session.device_name}"؟`)) return;
    busyId.value = session.id;
    await axios.delete(route('account.sessions.destroy', session.id));
    sessions.value = sessions.value.filter((s) => s.id !== session.id);
    busyId.value = null;
};

const logoutAll = async () => {
    if (!confirm('سيتم تسجيل الخروج من جميع الأجهزة المسجّل الدخول منها. متابعة؟')) return;
    loggingOutAll.value = true;
    await axios.post(route('account.sessions.logout-all'));
    sessions.value = [];
    loggingOutAll.value = false;
};

onMounted(load);
</script>

<template>
    <div class="rounded-lg bg-white p-6 shadow-sm">
        <div class="flex items-center justify-between">
            <h3 class="text-sm font-semibold text-gray-700">الأجهزة النشطة</h3>
            <button
                v-if="sessions.length"
                type="button"
                :disabled="loggingOutAll"
                class="text-sm font-medium text-red-600 hover:text-red-700 disabled:opacity-50"
                @click="logoutAll"
            >
                تسجيل الخروج من جميع الأجهزة
            </button>
        </div>

        <div v-if="loading" class="mt-4 text-sm text-gray-500">جارٍ التحميل...</div>
        <div v-else-if="!sessions.length" class="mt-4 text-sm text-gray-500">لا توجد أجهزة أخرى مسجّلة الدخول حاليًا.</div>

        <ul v-else class="mt-4 divide-y divide-gray-100">
            <li v-for="session in sessions" :key="session.id" class="flex items-center justify-between gap-3 py-3">
                <div class="flex items-center gap-3">
                    <div class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-500">
                        <Icon :name="deviceIcon(session.device_type)" size="text-[22px]" />
                    </div>
                    <div>
                        <div class="text-sm font-medium text-gray-900">{{ session.device_name }}</div>
                        <div class="text-xs text-gray-500">
                            {{ session.location ?? 'الموقع غير معروف' }} · آخر نشاط: {{ formatDate(session.last_used_at) }}
                        </div>
                    </div>
                </div>
                <button
                    type="button"
                    :disabled="busyId === session.id"
                    class="shrink-0 text-sm font-medium text-gray-500 hover:text-red-600 disabled:opacity-50"
                    @click="endSession(session)"
                >
                    إنهاء
                </button>
            </li>
        </ul>
    </div>
</template>
