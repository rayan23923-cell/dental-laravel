<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatListRow from '@/Components/ChatList/ChatListRow.vue';
import ChatChip from '@/Components/ChatList/ChatChip.vue';
import ChatAction from '@/Components/ChatList/ChatAction.vue';
import ChatAddButton from '@/Components/ChatList/ChatAddButton.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import { Head, router, useForm, usePage } from '@inertiajs/vue3';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const props = defineProps({
    assignments: Array,
    users: Array,
    departments: Array,
    stages: Array,
});

const page = usePage();

const form = useForm({
    user_id: '',
    department_id: '',
    stage_id: '',
    role_type: 'senior',
    notes: '',
});

// Only the chosen stage's departments, so same-named departments of
// different stages don't show up as duplicates (2026-10-13, by request).
const stageDepartments = computed(() =>
    form.stage_id ? props.departments.filter((d) => d.stage_id === Number(form.stage_id)) : []
);
watch(() => form.stage_id, () => {
    if (!stageDepartments.value.some((d) => d.id === Number(form.department_id))) form.department_id = '';
});

const roleLabel = (type) => (type === 'senior' ? t('departmentRolesAdmin.seniorOption') : type === 'hr' ? t('departmentRolesAdmin.hrOption') : type);

// Chat-list style (2026-10-13, by request): assigning opens a dialog from
// the round "+" in the header instead of an inline form.
const creating = ref(false);
const openCreate = () => {
    form.clearErrors();
    creating.value = true;
};

const assign = () => {
    form.post(route('department-roles.store'), {
        onSuccess: () => {
            form.reset('user_id', 'department_id', 'stage_id', 'notes');
            creating.value = false;
        },
    });
};

const toggle = (assignment) => {
    router.put(route('department-roles.toggle', assignment.id), {}, { preserveScroll: true });
};

const remove = (assignment) => {
    if (confirm(t('departmentRolesAdmin.removeConfirm'))) {
        router.delete(route('department-roles.destroy', assignment.id), { preserveScroll: true });
    }
};
</script>

<template>
    <Head :title="t('departmentRolesAdmin.title')" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between gap-3">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">{{ t('departmentRolesAdmin.title') }}</h2>
                <ChatAddButton :label="t('departmentRolesAdmin.assignRoleHeading')" @click="openCreate" />
            </div>
        </template>

        <div class="py-6 sm:py-10">
            <div class="mx-auto max-w-2xl space-y-4 px-4 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-xl bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <ChatListCard :empty="assignments.length === 0" :empty-text="t('departmentRolesAdmin.emptyList')" empty-icon="badge">
                    <ChatListRow
                        v-for="a in assignments"
                        :key="a.id"
                        :title="a.user?.full_name ?? '—'"
                        :tone="a.status === 'active' ? (a.role_type === 'hr' ? 'sky' : 'indigo') : 'gray'"
                    >
                        <template #meta>
                            <ChatChip :icon="a.role_type === 'hr' ? 'badge' : 'workspace_premium'" :tone="a.role_type === 'hr' ? 'sky' : 'indigo'">{{ roleLabel(a.role_type) }}</ChatChip>
                            <ChatChip v-if="a.department" icon="apartment">{{ a.department.name }}</ChatChip>
                            <ChatChip v-if="a.stage" icon="stairs">{{ a.stage.name }}</ChatChip>
                            <ChatChip :icon="a.status === 'active' ? 'check_circle' : 'block'" :tone="a.status === 'active' ? 'emerald' : 'gray'">
                                {{ a.status === 'active' ? t('caseSheetTypesAdmin.active') : t('caseSheetTypesAdmin.inactive') }}
                            </ChatChip>
                        </template>
                        <template #actions>
                            <ChatAction
                                :icon="a.status === 'active' ? 'toggle_off' : 'toggle_on'"
                                :label="a.status === 'active' ? t('departmentRolesAdmin.deactivate') : t('departmentRolesAdmin.reactivate')"
                                @click="toggle(a)"
                            />
                            <ChatAction icon="delete" :label="t('departmentRolesAdmin.remove')" danger @click="remove(a)" />
                        </template>
                    </ChatListRow>
                </ChatListCard>
            </div>
        </div>

        <Modal :show="creating" @close="creating = false">
            <form @submit.prevent="assign" class="space-y-4 p-6">
                <h2 class="text-lg font-medium text-gray-900">{{ t('departmentRolesAdmin.assignRoleHeading') }}</h2>
                <div>
                    <InputLabel for="dr-user" :value="t('departmentRolesAdmin.userCol')" />
                    <select id="dr-user" v-model="form.user_id" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                        <option value="" disabled>{{ t('departmentRolesAdmin.userPlaceholder') }}</option>
                        <option v-for="u in users" :key="u.id" :value="u.id">{{ u.full_name }}</option>
                    </select>
                    <InputError class="mt-2" :message="form.errors.user_id" />
                </div>
                <div>
                    <InputLabel for="dr-stage" :value="t('doctorsAdmin.stageCol')" />
                    <select id="dr-stage" v-model="form.stage_id" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                        <option value="" disabled>{{ t('doctorsAdmin.stageCol') }}</option>
                        <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="form.errors.stage_id" />
                </div>
                <div>
                    <InputLabel for="dr-department" :value="t('doctorsAdmin.departmentLabel')" />
                    <select id="dr-department" v-model="form.department_id" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100" :disabled="!form.stage_id" required>
                        <option value="" disabled>{{ form.stage_id ? t('tasksAdmin.selectDepartment') : t('tasksAdmin.selectStageFirst') }}</option>
                        <option v-for="d in stageDepartments" :key="d.id" :value="d.id">{{ d.name }}</option>
                    </select>
                    <InputError class="mt-2" :message="form.errors.department_id" />
                </div>
                <div>
                    <InputLabel for="dr-role" :value="t('common.role')" />
                    <select id="dr-role" v-model="form.role_type" class="mt-1 block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                        <option value="senior">{{ t('departmentRolesAdmin.seniorOption') }}</option>
                        <option value="hr">{{ t('departmentRolesAdmin.hrOption') }}</option>
                    </select>
                    <InputError class="mt-2" :message="form.errors.role_type" />
                </div>
                <div class="flex justify-end gap-3 pt-2">
                    <SecondaryButton @click="creating = false">{{ t('common.cancel') }}</SecondaryButton>
                    <PrimaryButton :disabled="form.processing">{{ t('tasksAdmin.assignButton') }}</PrimaryButton>
                </div>
            </form>
        </Modal>
    </AuthenticatedLayout>
</template>
