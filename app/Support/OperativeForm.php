<?php

namespace App\Support;

/**
 * Operative / المخطط السني — the case sheet behind the `operative` type
 * code, stored in `dental_charts`. Port of
 * dental_clinics2/doctor/operative.php (+ dental_chart.php).
 *
 * This is the sheet the earlier port was missing as a *case sheet*: the
 * table and a tooth picker existed, but as a standalone generic form rather
 * than the sectioned clinical sheet the original opens from a task.
 */
class OperativeForm
{
    public static function sections(): array
    {
        return [
            [
                'title' => 'معلومات المريض',
                'fields' => [
                    // `dental_charts.patient_id` is a varchar holding the
                    // patient's *name* in the original, not an FK.
                    ['key' => 'patient_id', 'label' => 'اسم المريض', 'type' => 'text', 'required' => true, 'width' => 'half'],
                    ['key' => 'patient_phone', 'label' => 'رقم الهاتف', 'type' => 'text'],
                    ['key' => 'visit_date', 'label' => 'تاريخ الزيارة', 'type' => 'date'],
                    ['key' => 'patient_age', 'label' => 'العمر', 'type' => 'number'],
                    ['key' => 'patient_sex', 'label' => 'الجنس', 'type' => 'select', 'options' => [
                        ['value' => 'male', 'label' => 'ذكر'],
                        ['value' => 'female', 'label' => 'أنثى'],
                    ]],
                    ['key' => 'patient_address', 'label' => 'العنوان', 'type' => 'text'],
                    ['key' => 'patient_occupation', 'label' => 'العمل', 'type' => 'text'],
                ],
            ],
            [
                'title' => 'الشكوى والتاريخ',
                'fields' => [
                    ['key' => 'chief_complaint', 'label' => 'الشكوى الرئيسية', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'history_of_complaint', 'label' => 'تاريخ الشكوى', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'الفحص السريري',
                'fields' => [
                    ['key' => 'oral_hygiene', 'label' => 'صحة الفم', 'type' => 'textarea', 'width' => 'half'],
                    ['key' => 'periodontal_condition', 'label' => 'حالة اللثة', 'type' => 'textarea', 'width' => 'half'],
                ],
            ],
            [
                'title' => 'المخطط السني',
                'note' => 'اضغط على أي سن لتسجيل حالته وحالة كل سطح فيه.',
                'fields' => [
                    // The real per-tooth odontogram — 32 teeth, five
                    // surfaces each (or three root canals once a tooth is
                    // marked non_vital), colour-coded exactly as the
                    // original's operative.php. See Components/
                    // ToothOdontogram.vue for the full status/colour
                    // vocabulary, read directly from the original's own CSS
                    // and JS rather than guessed.
                    ['key' => 'tooth_data', 'label' => 'المخطط السني', 'type' => 'dental_chart', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'قوائم سريعة',
                'note' => 'اختر الأسنان من الشبكة لكل حالة — ملخص نصي إلى جانب المخطط أعلاه.',
                'fields' => [
                    ['key' => 'non_vital_teeth', 'label' => 'أسنان غير حيوية', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'missing_teeth', 'label' => 'أسنان مفقودة', 'type' => 'teeth', 'width' => 'full'],
                    ['key' => 'crown_bridge_teeth', 'label' => 'تيجان / جسور', 'type' => 'teeth', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'علاج عصب الأسنان',
                'fields' => [
                    // The whole Endodontics card, including its iOS-style
                    // enable toggle — see Components/EndodonticsSection.vue
                    // for the field-by-field port and what's deliberately
                    // not included (image galleries, a drawn signature).
                    ['key' => 'endodontics_data', 'label' => 'علاج عصب الأسنان', 'type' => 'endodontics', 'width' => 'full'],
                ],
            ],
            [
                'title' => 'خطة العلاج والاعتماد',
                'fields' => [
                    ['key' => 'treatment_plan_notes', 'label' => 'ملاحظات خطة العلاج', 'type' => 'textarea', 'width' => 'full'],
                    ['key' => 'treatment_plan_date', 'label' => 'تاريخ خطة العلاج', 'type' => 'date'],
                    ['key' => 'senior_doctor_name', 'label' => 'الطبيب المشرف', 'type' => 'text'],
                    ['key' => 'senior_signature', 'label' => 'توقيع المشرف', 'type' => 'text', 'width' => 'half'],
                    ['key' => 'notes', 'label' => 'ملاحظات إضافية', 'type' => 'textarea', 'width' => 'full'],
                ],
            ],
        ];
    }
}
