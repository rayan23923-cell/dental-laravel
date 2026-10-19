<?php

namespace Tests\Feature;

use App\Models\CaseSheetType;
use App\Models\Task;
use App\Support\CaseSheetResolver;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * A pediatric task opens the sheet for its kind of work (2026-10-19, by
 * request: an extraction opened the operative sheet).
 */
class PediatricCaseSheetTest extends TestCase
{
    use RefreshDatabase;

    public function test_each_pediatric_task_opens_its_own_kind_of_sheet(): void
    {
        $pediatric = CaseSheetType::firstOrCreate(['type_code' => 'pediatric'], ['name_ar' => 'طب أسنان الأطفال', 'name_en' => 'Pediatric']);
        DB::statement('SET FOREIGN_KEY_CHECKS=0');
        $task = fn (string $title) => Task::create([
            'department_id' => 1, 'case_sheet_type_id' => $pediatric->id, 'stage_id' => 1,
            'title' => $title, 'required_per_doctor' => 1, 'required_count' => 1,
        ]);
        $extraction = $task('Extraction');
        $fluoride = $task('Fluoride');
        $fillings = $task('Fillings');
        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        $this->assertSame('surgeries', CaseSheetResolver::resourceForTask($extraction));
        $this->assertSame('prevention-records', CaseSheetResolver::resourceForTask($fluoride));
        $this->assertSame('dental-charts', CaseSheetResolver::resourceForTask($fillings));
        $this->assertSame('surgery', CaseSheetResolver::pediatricTypeCode('قلع سن لبني'));
    }
}
