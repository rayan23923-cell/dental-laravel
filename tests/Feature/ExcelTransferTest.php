<?php

namespace Tests\Feature;

use App\Models\CaseSheetType;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\RegisterDay;
use App\Models\Service;
use App\Models\Stage;
use App\Models\Task;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

/**
 * Doctors, services and tasks exported to Excel import back into another
 * system (2026-10-18, by request: moving hosted data to the offline one).
 */
class ExcelTransferTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));
    }

    private function upload(string $content): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'xl').'.xlsx';
        file_put_contents($path, $content);

        return new UploadedFile($path, 'export.xlsx', null, null, true);
    }

    public function test_services_and_their_prices_round_trip(): void
    {
        $saturday = RegisterDay::create(['name' => 'السبت', 'sort_order' => 1]);
        Service::create(['name' => 'حشوة', 'price' => 15000])->days()->sync([$saturday->id]);
        Service::create(['name' => 'قلع', 'price' => 5000]);

        $file = $this->upload($this->get(route('register-services.export'))->assertOk()->streamedContent());
        Service::query()->delete();
        RegisterDay::query()->delete();

        $this->post(route('register-services.import'), ['file' => $file])->assertSessionHas('success');
        $this->assertEquals(15000, Service::where('name', 'حشوة')->value('price'));
        $this->assertSame(['السبت'], Service::where('name', 'حشوة')->first()->days->pluck('name')->all());
        $this->assertCount(2, Service::all());

        // Importing again updates instead of duplicating.
        $this->post(route('register-services.import'), ['file' => $file]);
        $this->assertCount(2, Service::all());
    }

    public function test_tasks_round_trip_into_an_empty_structure(): void
    {
        $type = CaseSheetType::create(['type_code' => 'surgery', 'name_ar' => 'جراحة', 'name_en' => 'Surgery']);
        $et = EducationType::create(['name' => 'الدراسات الأولية']);
        $stage = Stage::create(['name' => 'الرابعة', 'education_type_id' => $et->id]);
        $dept = Department::create(['name' => 'الجراحة', 'stage_id' => $stage->id, 'education_type_id' => $et->id, 'pass_percent' => 60]);
        Task::create([
            'title' => 'قلع بسيط', 'stage_id' => $stage->id, 'department_id' => $dept->id, 'case_sheet_type_id' => $type->id,
            'required_count' => 3, 'grade' => 10, 'notes' => 'ملاحظة', 'is_required' => true,
            'scoring' => ['measure' => 'count', 'checklist' => [['label' => 'تخدير']]],
        ]);

        $file = $this->upload($this->get(route('tasks.export'))->assertOk()->streamedContent());
        Task::withTrashed()->forceDelete();
        Department::query()->delete();
        Stage::query()->delete();
        EducationType::query()->delete();

        $this->post(route('tasks.import'), ['file' => $file])->assertSessionHas('success')->assertSessionMissing('error');
        $task = Task::with('stage.educationType', 'department')->sole();
        $this->assertSame(['قلع بسيط', 'الرابعة', 'الدراسات الأولية', 'الجراحة', 3], [
            $task->title, $task->stage->name, $task->stage->educationType->name, $task->department->name, $task->required_count,
        ]);
        $this->assertEquals(60, $task->department->pass_percent);
        $this->assertSame('تخدير', $task->scoring['checklist'][0]['label']);

        $this->post(route('tasks.import'), ['file' => $file]);
        $this->assertCount(1, Task::all());
    }

    public function test_exported_doctors_import_back_without_passwords(): void
    {
        $et = EducationType::create(['name' => 'الدراسات الأولية']);
        $fourth = Stage::create(['name' => 'الرابعة', 'education_type_id' => $et->id]);
        $fifth = Stage::create(['name' => 'الخامسة', 'education_type_id' => $et->id]);
        Doctor::create(['name' => 'علي حسن', 'username' => '0770', 'password' => 'secret1', 'email' => 'ali@example.com', 'phone' => '0770123', 'education_type_id' => $et->id, 'stage_id' => $fifth->id]);

        $content = $this->get(route('doctors.export'))->assertOk()->streamedContent();
        $this->assertStringNotContainsString(Doctor::first()->password, $content);
        Doctor::withTrashed()->forceDelete();

        $this->post(route('doctors.import'), [
            'file' => $this->upload($content), 'education_type_id' => $et->id, 'stage_id' => $fourth->id, 'default_password' => 'newpass1',
        ])->assertSessionHasNoErrors();

        $doctor = Doctor::sole();
        $this->assertSame(['علي حسن', '0770', 'ali@example.com', '0770123', $fifth->id], [$doctor->name, $doctor->username, $doctor->email, $doctor->phone, $doctor->stage_id]);
    }
}
