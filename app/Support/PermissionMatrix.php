<?php

namespace App\Support;

/**
 * The permission matrix, copied verbatim from the original's authoritative
 * definition in admin/user_permissions_ajax/get_user_permissions.php.
 *
 * The important structural point — and what the earlier port got wrong — is
 * that **each module has its own action set**, not a uniform
 * view/create/edit/delete/export grid. `tasks` has `assign`, `task_progress`
 * has `start`/`finish`/`open_case_sheet`/`view_all`, `reports` has `print`,
 * `dashboard` and `settings` only have view/edit, and so on. Rendering a
 * cartesian product would offer grants the original never had (and hide the
 * ones it does).
 *
 * Module and permission keys are the original's exactly, so rows in
 * `user_permissions` written by either app mean the same thing.
 */
class PermissionMatrix
{
    public static function modules(): array
    {
        return [
            // Listed in the order the admin works through them (2026-10-14,
            // by request): education types → stages → departments → tasks →
            // clinical forms → doctors → groups → task progress.
            'dashboard' => [
                'name' => 'لوحة التحكم',
                // The dashboard's "المهام المطلوبة لكل قسم ومرحلة" section
                // (2026-10-24, by request), shown within the account's scope.
                'permissions' => ['view' => 'عرض', 'edit' => 'تعديل', 'tasks_by_department' => 'المهام المطلوبة لكل قسم ومرحلة'],
            ],
            'users' => [
                'name' => 'إدارة المستخدمين',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف'],
            ],
            // Not in the original's own module list (its education-types
            // page only ever checked 'stages'/'view', and its create/edit/
            // delete AJAX had no permission check at all) — given a real
            // module here rather than replicating that gap, matching how
            // 'stages'/'departments' already exceed the original's actual
            // enforcement in this rebuild.
            'education_types' => [
                'name' => 'إدارة أنواع التعليم',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف'],
            ],
            'stages' => [
                'name' => 'إدارة المراحل',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف'],
            ],
            'departments' => [
                'name' => 'إدارة الأقسام',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف'],
            ],
            'tasks' => [
                'name' => 'إدارة المهام',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف', 'assign' => 'تخصيص'],
            ],
            // Clinical form types (2026-10-14, by request): their own module,
            // ahead of which the page was open to every admin.
            'case_sheet_types' => [
                'name' => 'إدارة النماذج السريرية',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف'],
            ],
            'doctors' => [
                'name' => 'إدارة الأطباء',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف', 'export' => 'تصدير'],
            ],
            'groups' => [
                'name' => 'إدارة المجموعات',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف'],
            ],
            'task_progress' => [
                'name' => 'تقدم المهام',
                'permissions' => [
                    'view' => 'عرض',
                    'view_all' => 'عرض الكل',
                    'export' => 'تصدير',
                    'start' => 'بدء المهمة',
                    'cancel' => 'إلغاء بدء المهمة',
                    // Split out of start/finish/view (2026-10-22, by request).
                    'track_steps' => 'تتبع الخطوات',
                    'add_step' => 'إضافة خطوة',
                    'grade' => 'إضافة الدرجة أو تعديلها',
                    'finish' => 'إنهاء المهمة وإدخال الدرجة',
                    'open_case_sheet' => 'فتح النماذج أو الورقة',
                    'view_grade' => 'مشاهدة الدرجة أو إخفاؤها',
                    'view_status' => 'مشاهدة المعلقة والمكتملة',
                    'supervisor_code' => 'كود المشرف',
                    'form_settings' => 'إعدادات النماذج',
                ],
            ],
            'patients' => [
                'name' => 'إدارة المرضى',
                'permissions' => ['view' => 'عرض', 'create' => 'إنشاء', 'edit' => 'تعديل', 'delete' => 'حذف', 'export' => 'تصدير'],
            ],
            // New for the infectious-disease screening feature (2026-08-26)
            // — not part of the legacy app's module list, same precedent
            // as 'education_types' above.
            'patient_screening' => [
                'name' => 'فحص الأمراض المعدية',
                'permissions' => ['view' => 'عرض', 'confirm' => 'تأكيد النتيجة'],
            ],
            'reports' => [
                'name' => 'التقارير',
                'permissions' => ['view' => 'عرض', 'export' => 'تصدير', 'print' => 'طباعة'],
            ],
            'settings' => [
                'name' => 'الإعدادات',
                'permissions' => ['view' => 'عرض', 'edit' => 'تعديل'],
            ],
            // The app's printer set-up on this device (2026-10-18, by
            // request), so desk accounts like the lab can be given it.
            'printer_settings' => [
                'name' => 'إعدادات الطابعة',
                'permissions' => ['view' => 'فتح الإعدادات'],
            ],
        ];
    }

    /** Flat "module.permission" list of every grant the matrix can express. */
    public static function pairs(): array
    {
        $pairs = [];
        foreach (static::modules() as $module => $definition) {
            foreach (array_keys($definition['permissions']) as $permission) {
                $pairs[] = "{$module}.{$permission}";
            }
        }

        return $pairs;
    }

    /** Shape the UI consumes: an ordered list with keys and labels. */
    public static function forUi(): array
    {
        return collect(static::modules())
            ->map(fn ($definition, $key) => [
                'key' => $key,
                'name' => $definition['name'],
                'permissions' => collect($definition['permissions'])
                    ->map(fn ($label, $permission) => ['key' => $permission, 'label' => $label])
                    ->values()
                    ->all(),
            ])
            ->values()
            ->all();
    }
}
