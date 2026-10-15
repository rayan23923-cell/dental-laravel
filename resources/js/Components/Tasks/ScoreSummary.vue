<script setup>
import { useI18n } from 'vue-i18n';

/** A doctor's points/percentage on a department (2026-10-14); see App\Support\TaskScoring. */
const { t } = useI18n();
defineProps({ score: { type: Object, required: true } });
</script>

<template>
    <div class="mb-3 rounded-lg bg-white p-3 shadow-sm">
        <div class="mb-2 flex flex-wrap items-center gap-2 text-sm">
            <span class="font-semibold text-gray-800">{{ t('taskScoring.result') }}: <span dir="ltr">{{ score.percent }}%</span></span>
            <span class="rounded-full px-2 py-0.5 text-xs" :class="score.passed ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-700'">
                {{ score.passed ? t('taskScoring.passed') : t('taskScoring.notPassed') }} ({{ t('taskScoring.passAt', { n: score.pass_percent }) }})
            </span>
        </div>
        <div class="h-2 overflow-hidden rounded-full bg-gray-100">
            <div class="h-full rounded-full" :class="score.passed ? 'bg-green-500' : 'bg-amber-500'" :style="{ width: Math.min(100, score.percent) + '%' }"></div>
        </div>
        <table class="mt-2 w-full text-xs">
            <tbody>
                <tr v-for="row in score.tasks" :key="row.task_id" class="border-t border-gray-100">
                    <td class="py-1 text-gray-700">{{ row.title }}</td>
                    <td class="py-1 text-center text-gray-600">{{ row.cases }}/{{ row.required_count }}</td>
                    <td class="py-1 text-center text-gray-600">
                        <template v-if="row.min_points">{{ t('taskScoring.pointsValue', { n: `${row.points}/${row.min_points}` }) }}</template>
                        <template v-else-if="row.points">{{ t('taskScoring.pointsValue', { n: row.points }) }}</template>
                    </td>
                    <td class="py-1 text-center text-gray-500"><template v-if="row.weight !== null">{{ row.weight }}%</template></td>
                    <td class="py-1 text-end font-medium" :class="row.percent >= 100 ? 'text-green-700' : 'text-gray-700'" dir="ltr">{{ row.percent }}%</td>
                </tr>
            </tbody>
        </table>
    </div>
</template>
