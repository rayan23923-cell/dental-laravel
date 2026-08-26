<?php

namespace Database\Seeders;

use App\Models\CaseSheetType;
use Illuminate\Database\Seeder;

/**
 * The case-sheet types the original app ships with — the list its own
 * open_case_sheet.php switches on, and the one visible on the live site's
 * "إدارة النماذج السريرية" screen.
 *
 * The imported schema arrived with only the `operative` row, so tasks could
 * not be typed as anything else and the dispatcher had nothing to route.
 * Idempotent: matches on `type_code`, so re-running never duplicates and
 * never overwrites a name an admin has edited.
 */
class CaseSheetTypeSeeder extends Seeder
{
    public function run(): void
    {
        $types = [
            ['type_code' => 'operative', 'name_ar' => 'المخطط السني', 'name_en' => 'Operative', 'icon' => 'tooth', 'color' => 'primary'],
            ['type_code' => 'partial_denture', 'name_ar' => 'الطقم الجزئي', 'name_en' => 'Partial Denture', 'icon' => 'teeth', 'color' => 'info'],
            ['type_code' => 'complete_denture', 'name_ar' => 'الطقم الكامل', 'name_en' => 'Complete Denture', 'icon' => 'teeth', 'color' => 'success'],
            ['type_code' => 'surgery', 'name_ar' => 'العمليات الجراحية', 'name_en' => 'Surgery', 'icon' => 'procedures', 'color' => 'danger'],
            ['type_code' => 'periodontal', 'name_ar' => 'المخطط اللثوي', 'name_en' => 'Periodontal', 'icon' => 'teeth-open', 'color' => 'warning'],
            ['type_code' => 'prosthodontics', 'name_ar' => 'التعويضات السنية', 'name_en' => 'Prosthodontics', 'icon' => 'tooth', 'color' => 'secondary'],
            ['type_code' => 'orthodontics', 'name_ar' => 'تقويم الأسنان', 'name_en' => 'Orthodontics', 'icon' => 'teeth', 'color' => 'primary'],
            ['type_code' => 'prevention', 'name_ar' => 'الوقاية', 'name_en' => 'Prevention', 'icon' => 'shield-alt', 'color' => 'success'],
            ['type_code' => 'oral_medicine', 'name_ar' => 'طب الفم', 'name_en' => 'Oral Medicine', 'icon' => 'file-medical', 'color' => 'info'],
        ];

        foreach ($types as $index => $type) {
            CaseSheetType::firstOrCreate(
                ['type_code' => $type['type_code']],
                [...$type, 'is_active' => true, 'display_order' => $index + 1]
            );
        }
    }
}
