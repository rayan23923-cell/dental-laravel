<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import StructureTabs from '@/Components/StructureTabs.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, router, useForm, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';

defineProps({
    sessions: Array,
    selectedSessionId: Number,
});

const page = usePage();

const showCreate = ref(false);
const createForm = useForm({ name: '', start_date: '', end_date: '', is_active: true, is_current: false });
const submitCreate = () => {
    createForm.post(route('academic-sessions.store'), {
        onSuccess: () => {
            createForm.reset();
            showCreate.value = false;
        },
    });
};

const editing = ref(null);
const editForm = useForm({ name: '', start_date: '', end_date: '', is_active: true, is_current: false });
const openEdit = (session) => {
    editing.value = session;
    editForm.name = session.name;
    editForm.start_date = session.start_date;
    editForm.end_date = session.end_date;
    editForm.is_active = !!session.is_active;
    editForm.is_current = !!session.is_current;
};
const submitEdit = () => {
    editForm.put(route('academic-sessions.update', editing.value.id), {
        onSuccess: () => (editing.value = null),
    });
};

const setCurrent = (session) => {
    router.put(route('academic-sessions.set-current', session.id));
};

const selectViewing = (session) => {
    router.post(route('academic-sessions.select'), { academic_session_id: session.id });
};

const destroy = (session) => {
    if (confirm(`حذف "${session.name}"؟`)) {
        router.delete(route('academic-sessions.destroy', session.id));
    }
};
</script>

<template>
    <Head title="الأعوام الدراسية" />

    <AuthenticatedLayout>
        <template #header>
            <h2 class="text-xl font-semibold leading-tight text-gray-800">الأعوام الدراسية</h2>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-6xl space-y-4 sm:px-6 lg:px-8">
                <StructureTabs active="academic-sessions" />

                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>
                <div v-if="page.props.flash?.error" class="rounded-md bg-red-50 p-4 text-sm text-red-700">
                    {{ page.props.flash.error }}
                </div>

                <div class="flex justify-end">
                    <PrimaryButton @click="showCreate = true">إضافة عام دراسي</PrimaryButton>
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">الاسم</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">التواريخ</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">المجموعات</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">المهام</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">العام النشط</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">العمليات</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="session in sessions" :key="session.id" :class="session.id === selectedSessionId ? 'bg-indigo-50' : ''">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">
                                    <Link :href="route('academic-sessions.show', session.id)" class="text-indigo-600 hover:underline">
                                        {{ session.name }}
                                    </Link>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ session.start_date }} ← {{ session.end_date }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ session.groups_count }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ session.tasks_count }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm">
                                    <!-- iOS-style toggle — turning a year on makes it current and
                                         (via AcademicSession::booted()'s saving() hook, see
                                         dental_laravel/README.md) automatically turns every other
                                         year off, so there's no separate "off" action: the only way
                                         to turn the current year off is to turn a different one on.
                                         Matches the same control added to the Flutter admin app. -->
                                    <button
                                        type="button"
                                        :disabled="session.is_current"
                                        @click="setCurrent(session)"
                                        :class="[
                                            'relative inline-flex h-6 w-11 flex-shrink-0 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2',
                                            session.is_current ? 'bg-green-500 cursor-default' : 'bg-gray-300 cursor-pointer hover:bg-gray-400',
                                        ]"
                                        :aria-label="session.is_current ? 'العام الدراسي النشط حالياً' : 'اجعله العام الدراسي النشط'"
                                    >
                                        <span
                                            :class="[
                                                'inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform',
                                                session.is_current ? 'translate-x-6' : 'translate-x-1',
                                            ]"
                                        />
                                    </button>
                                </td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm space-x-3">
                                    <button v-if="session.id !== selectedSessionId" @click="selectViewing(session)" class="text-gray-600 hover:text-gray-900">عرض كمحدد</button>
                                    <button @click="openEdit(session)" class="text-indigo-600 hover:text-indigo-900">تعديل</button>
                                    <button v-if="!session.is_current" @click="destroy(session)" class="text-red-600 hover:text-red-900">حذف</button>
                                </td>
                            </tr>
                            <tr v-if="sessions.length === 0">
                                <td colspan="6" class="px-6 py-8 text-center text-sm text-gray-500">لا توجد أعوام دراسية بعد.</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <Modal :show="showCreate" @close="showCreate = false">
            <form @submit.prevent="submitCreate" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">إضافة عام دراسي</h2>
                <div class="mt-4">
                    <InputLabel for="create-name" value="الاسم" />
                    <TextInput id="create-name" v-model="createForm.name" type="text" class="mt-1 block w-full" required autofocus />
                    <InputError class="mt-2" :message="createForm.errors.name" />
                </div>
                <div class="mt-4 grid grid-cols-2 gap-4">
                    <div>
                        <InputLabel for="create-start" value="تاريخ البدء" />
                        <TextInput id="create-start" v-model="createForm.start_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="createForm.errors.start_date" />
                    </div>
                    <div>
                        <InputLabel for="create-end" value="تاريخ الانتهاء" />
                        <TextInput id="create-end" v-model="createForm.end_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="createForm.errors.end_date" />
                    </div>
                </div>
                <div class="mt-4 flex gap-6">
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="createForm.is_active" class="rounded border-gray-300" />
                        مفعّل
                    </label>
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="createForm.is_current" class="rounded border-gray-300" />
                        تعيينه كعام دراسي نشط
                    </label>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="showCreate = false">إلغاء</SecondaryButton>
                    <PrimaryButton :disabled="createForm.processing">حفظ</PrimaryButton>
                </div>
            </form>
        </Modal>

        <Modal :show="editing !== null" @close="editing = null">
            <form @submit.prevent="submitEdit" class="p-6">
                <h2 class="text-lg font-medium text-gray-900">تعديل العام الدراسي</h2>
                <div class="mt-4">
                    <InputLabel for="edit-name" value="الاسم" />
                    <TextInput id="edit-name" v-model="editForm.name" type="text" class="mt-1 block w-full" required />
                    <InputError class="mt-2" :message="editForm.errors.name" />
                </div>
                <div class="mt-4 grid grid-cols-2 gap-4">
                    <div>
                        <InputLabel for="edit-start" value="تاريخ البدء" />
                        <TextInput id="edit-start" v-model="editForm.start_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="editForm.errors.start_date" />
                    </div>
                    <div>
                        <InputLabel for="edit-end" value="تاريخ الانتهاء" />
                        <TextInput id="edit-end" v-model="editForm.end_date" type="date" class="mt-1 block w-full" required />
                        <InputError class="mt-2" :message="editForm.errors.end_date" />
                    </div>
                </div>
                <div class="mt-4 flex gap-6">
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="editForm.is_active" class="rounded border-gray-300" />
                        مفعّل
                    </label>
                    <label class="flex items-center gap-2 text-sm text-gray-700">
                        <input type="checkbox" v-model="editForm.is_current" class="rounded border-gray-300" />
                        تعيينه كعام دراسي نشط
                    </label>
                </div>
                <div class="mt-6 flex justify-end gap-3">
                    <SecondaryButton @click="editing = null">إلغاء</SecondaryButton>
                    <PrimaryButton :disabled="editForm.processing">حفظ</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
