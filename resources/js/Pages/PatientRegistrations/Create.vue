<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, useForm } from '@inertiajs/vue3';
import { computed, ref } from 'vue';

const props = defineProps({
    days: Array,
    tasks: Array,
});

const form = useForm({
    name: '',
    phone: '',
    register_day_id: '',
    service_id: '',
    task_id: '',
});

// Day-first cascading picker — matches admin/patient_register.php's UX
// (pick a day, the service dropdown filters to that day's services),
// chosen over public_register.php's reversed service-first flow since
// that page is out of scope for this port.
const servicesForSelectedDay = computed(() => {
    const day = props.days.find((d) => d.id === form.register_day_id);
    return day ? day.services : [];
});

// Day-governed diagnosis — same idea as service above, but opt-in per
// day: a day with no configured tasks (`tasks: []`) leaves every task
// selectable, exactly like before this existed. Once a day has ≥1 task
// configured, only those show.
const tasksForSelectedDay = computed(() => {
    const day = props.days.find((d) => d.id === form.register_day_id);
    if (!day || !day.tasks || day.tasks.length === 0) return props.tasks;
    const allowedIds = new Set(day.tasks.map((t) => t.id));
    return props.tasks.filter((t) => allowedIds.has(t.id));
});

const onDayChange = () => {
    if (!servicesForSelectedDay.value.some((s) => s.id === form.service_id)) {
        form.service_id = '';
    }
    if (form.task_id && !tasksForSelectedDay.value.some((t) => t.id === form.task_id)) {
        form.task_id = '';
    }
};

// Text-search filters, same computed-over-props shape as
// Doctors/Create.vue's `filteredStages` — a plain <select> becomes
// unusable once a clinic has dozens of days/services.
const dayFilter = ref('');
const serviceFilter = ref('');

const filteredDays = computed(() =>
    dayFilter.value.trim() ? props.days.filter((d) => d.name.includes(dayFilter.value.trim())) : props.days,
);

const filteredServices = computed(() =>
    serviceFilter.value.trim()
        ? servicesForSelectedDay.value.filter((s) => s.name.includes(serviceFilter.value.trim()))
        : servicesForSelectedDay.value,
);

// "التشخيص" — still optional and still doesn't gate anything *else* on
// this form (see PatientRegistration::task()'s docblock for the
// stage/education-type display), but *which* tasks are offered is now
// narrowed by the selected day, once that day has any configured
// (`tasksForSelectedDay` above).
const taskFilter = ref('');
const filteredTasks = computed(() =>
    taskFilter.value.trim()
        ? tasksForSelectedDay.value.filter((t) => t.title.includes(taskFilter.value.trim()))
        : tasksForSelectedDay.value,
);
const selectedTask = computed(() => props.tasks.find((t) => t.id === form.task_id) ?? null);

const submit = () => {
    form.post(route('patient-registrations.store'));
};
</script>

<template>
    <Head title="Register Patient" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">تسجيل مريض جديد</h2>
                <Link :href="route('patient-registrations.index')" class="text-sm text-indigo-600 hover:underline">السجل &rarr;</Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-2xl sm:px-6 lg:px-8">
                <div class="overflow-hidden bg-white p-6 shadow-sm sm:rounded-lg">
                    <form @submit.prevent="submit" class="space-y-6">
                        <div>
                            <InputLabel for="name" value="اسم المريض" />
                            <TextInput id="name" v-model="form.name" type="text" class="mt-1 block w-full" required autofocus />
                            <InputError class="mt-2" :message="form.errors.name" />
                        </div>

                        <div>
                            <InputLabel for="phone" value="رقم الهاتف" />
                            <TextInput id="phone" v-model="form.phone" type="text" class="mt-1 block w-full" dir="ltr" required />
                            <InputError class="mt-2" :message="form.errors.phone" />
                        </div>

                        <div>
                            <InputLabel for="register_day_id" value="اليوم" />
                            <TextInput
                                v-if="days.length > 6"
                                v-model="dayFilter"
                                type="text"
                                placeholder="تصفية الأيام..."
                                class="mt-1 block w-full"
                            />
                            <select
                                id="register_day_id"
                                v-model="form.register_day_id"
                                @change="onDayChange"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                required
                            >
                                <option value="" disabled>اختر اليوم</option>
                                <option v-for="day in filteredDays" :key="day.id" :value="day.id">{{ day.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.register_day_id" />
                        </div>

                        <div>
                            <InputLabel for="service_id" value="الخدمة" />
                            <TextInput
                                v-if="servicesForSelectedDay.length > 6"
                                v-model="serviceFilter"
                                type="text"
                                placeholder="تصفية الخدمات..."
                                class="mt-1 block w-full"
                            />
                            <select
                                id="service_id"
                                v-model="form.service_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                :disabled="!form.register_day_id"
                                required
                            >
                                <option value="" disabled>{{ form.register_day_id ? 'اختر الخدمة' : 'اختر اليوم أولاً' }}</option>
                                <option v-for="service in filteredServices" :key="service.id" :value="service.id">{{ service.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.service_id" />
                            <p v-if="form.register_day_id && servicesForSelectedDay.length === 0" class="mt-2 text-sm text-amber-600">
                                لا توجد خدمات متاحة في هذا اليوم.
                            </p>
                        </div>

                        <div>
                            <InputLabel for="task_id" value="التشخيص" />
                            <TextInput
                                v-if="tasks.length > 6"
                                v-model="taskFilter"
                                type="text"
                                placeholder="تصفية المهام..."
                                class="mt-1 block w-full"
                            />
                            <select
                                id="task_id"
                                v-model="form.task_id"
                                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                            >
                                <option value="">— بدون —</option>
                                <option v-for="task in filteredTasks" :key="task.id" :value="task.id">{{ task.title }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.task_id" />
                            <p v-if="selectedTask" class="mt-2 text-sm text-gray-500">
                                {{ selectedTask.stage?.name ?? '—' }}
                                <span v-if="selectedTask.stage?.education_type"> · {{ selectedTask.stage.education_type.name }}</span>
                            </p>
                        </div>

                        <div class="flex justify-end">
                            <PrimaryButton :disabled="form.processing">تسجيل</PrimaryButton>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
