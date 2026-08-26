<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import { Head, Link, router, usePage } from '@inertiajs/vue3';
import { ref } from 'vue';

const props = defineProps({
    payments: Object,
    filters: { type: Object, default: () => ({}) },
});

const page = usePage();

// Lets a person's whole payment history — appointment- or
// registration-sourced alike — surface in one search, regardless of
// which of the two a given payment settled.
const search = ref(props.filters.search ?? '');
const applySearch = () => {
    router.get(route('payments.index'), { search: search.value || undefined }, { preserveState: true, replace: true });
};

const personName = (payment) => payment.patient_registration?.name ?? payment.appointment?.full_name ?? '—';

const destroy = (payment) => {
    if (confirm(`Delete this payment of ${payment.amount}?`)) {
        router.delete(route('payments.destroy', payment.id));
    }
};
</script>

<template>
    <Head title="Payments" />

    <AuthenticatedLayout>
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">Payments</h2>
                <Link :href="route('payments.create')">
                    <PrimaryButton>Record Payment</PrimaryButton>
                </Link>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-4xl space-y-4 sm:px-6 lg:px-8">
                <div
                    v-if="page.props.flash?.success"
                    class="rounded-md bg-green-50 p-4 text-sm text-green-700"
                >
                    {{ page.props.flash.success }}
                </div>

                <div class="flex gap-2 rounded-lg bg-white p-4 shadow-sm">
                    <input
                        v-model="search"
                        @keyup.enter="applySearch"
                        type="text"
                        placeholder="ابحث عن شخص لعرض كل مدفوعاته..."
                        class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    />
                    <button
                        @click="applySearch"
                        type="button"
                        class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700"
                    >
                        بحث
                    </button>
                </div>

                <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
                    <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                            <tr>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">الشخص</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">المصدر</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Amount</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Paid By</th>
                                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Paid At</th>
                                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 bg-white">
                            <tr v-for="payment in payments.data" :key="payment.id">
                                <td class="whitespace-nowrap px-6 py-4 text-sm font-medium text-gray-900">{{ personName(payment) }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ payment.patient_registration ? 'تسجيل مريض' : 'موعد' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ payment.amount }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ payment.paid_by ?? '—' }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-500">{{ new Date(payment.paid_at).toLocaleString() }}</td>
                                <td class="whitespace-nowrap px-6 py-4 text-right text-sm">
                                    <button @click="destroy(payment)" class="text-red-600 hover:text-red-900">Delete</button>
                                </td>
                            </tr>
                            <tr v-if="payments.data.length === 0">
                                <td colspan="6" class="px-6 py-8 text-center text-sm text-gray-500">No payments yet.</td>
                            </tr>
                        </tbody>
                    </table>

                    <div class="flex justify-between border-t border-gray-200 p-4">
                        <Link
                            v-for="link in payments.links"
                            :key="link.label"
                            :href="link.url ?? ''"
                            v-html="link.label"
                            class="mx-1 rounded px-3 py-1 text-sm"
                            :class="{
                                'bg-indigo-600 text-white': link.active,
                                'text-gray-400 pointer-events-none': !link.url,
                                'text-gray-700 hover:bg-gray-100': link.url && !link.active,
                            }"
                        />
                    </div>
                </div>
            </div>
        </div>
    </AuthenticatedLayout>
</template>
