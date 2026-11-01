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
            // Payments and the registration services' settings (2026-10-24,
            // by request): permissions of their own instead of role gates, so
            // they can be given to the accountant or anyone else.
            'payments' => [
                'name' => 'المدفوعات',
                // The lab's and the ticket desk's own payments, with their
                // report (2026-10-26, by request); `view` is all of them.
                'permissions' => [
                    'view' => 'عرض',
                    'create' => 'تسجيل دفعة',
                    'delete' => 'حذف',
                    'export' => 'التقرير والتصدير',
                    'view_lab' => 'عرض وطباعة مدفوعات المختبر فقط',
                    'view_tickets' => 'عرض وطباعة واردات التذاكر فقط',
                ],
            ],
            'register_settings' => [
                'name' => 'إعدادات تسجيل الخدمات وتسعيرها',
                'permissions' => ['view' => 'عرض', 'edit' => 'تعديل الخدمات والأسعار'],
            ],
            // The waiting screen (2026-10-24, by request): its settings and
            // pairing a TV, instead of the general settings and any account.
            'waiting_screen' => [
                'name' => 'شاشة الانتظار',
                'permissions' => ['view' => 'عرض الإعدادات', 'edit' => 'تعديل الإعدادات', 'pair' => 'ربط شاشة'],
            ],
            // Bulk login details page (2026-11-01, by request): its own
            // permission instead of super admins only.
            'bulk_credentials' => [
                'name' => 'بيانات الدخول الجماعية',
                'permissions' => [
                    'view' => 'عرض الصفحة وتنزيل الملفات وطباعة البطاقات',
                    'create' => 'إنشاء التدريسيين وكلمات مرور جديدة للمراحل',
                    'apply' => 'حفظ ملف بيانات الدخول (خادم العيادة)',
                    'delete' => 'حذف الملفات',
                ],
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
