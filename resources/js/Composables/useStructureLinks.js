import { computed } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { useI18n } from 'vue-i18n';

/**
 * "البيانات الأساسية" — one list for the menu group and the tabs above its
 * pages (2026-10-13, by request: "اجعل التبويبات نفس البيانات الأساسية"),
 * so the two can't drift apart.
 */
export function useStructureLinks() {
    const { t } = useI18n();
    const page = usePage();

    return computed(() => {
        const role = page.props.auth?.user?.role;
        if (['reception', 'lab'].includes(role)) return [];
        const doctors = { key: 'doctors', label: t('nav.doctors'), icon: 'stethoscope', href: route('doctors.index'), active: route().current('doctors.*') };
        const tasks = { key: 'tasks', label: t('nav.tasks'), icon: 'assignment', href: route('tasks.index'), active: route().current('tasks.*') };
        if (!['super_admin', 'admin'].includes(role)) return [tasks, doctors];

        return [
            { key: 'education-types', label: t('nav.educationTypes'), icon: 'school', href: route('education-types.index'), active: route().current('education-types.*') },
            { key: 'stages', label: t('nav.stages'), icon: 'stairs', href: route('stages.index'), active: route().current('stages.*') },
            { key: 'departments', label: t('nav.departments'), icon: 'apartment', href: route('departments.index'), active: route().current('departments.*') },
            tasks,
            { key: 'academic-sessions', label: t('nav.academicSessions'), icon: 'calendar_month', href: route('academic-sessions.index'), active: route().current('academic-sessions.*') },
            doctors,
            // Hidden while groups are turned off in clinic settings.
            ...(page.props.groupsEnabled !== false
                ? [{ key: 'groups', label: t('nav.groups'), icon: 'groups', href: route('groups.index'), active: route().current('groups.*') }]
                : []),
            { key: 'task-progress', label: t('nav.taskProgress'), icon: 'monitoring', href: route('task-progress.index'), active: route().current('task-progress.*') },
            { key: 'case-sheet-types', label: t('nav.caseSheetTypes'), icon: 'description', href: route('case-sheet-types.index'), active: route().current('case-sheet-types.*') },
        ];
    });
}
