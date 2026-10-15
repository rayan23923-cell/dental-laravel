<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\UserPermission;
use App\Services\PermissionManager;
use App\Support\PermissionMatrix;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * "إدارة النماذج السريرية" is its own permission module, listed in the
 * order the admin works through the setup (2026-10-14, by request).
 */
class CaseSheetTypesPermissionTest extends TestCase
{
    use RefreshDatabase;

    public function test_modules_follow_the_requested_order(): void
    {
        $keys = array_column(PermissionMatrix::forUi(), 'key');
        $wanted = ['education_types', 'stages', 'departments', 'tasks', 'case_sheet_types', 'doctors', 'groups', 'task_progress'];

        $this->assertSame($wanted, array_values(array_intersect($keys, $wanted)));
        $this->assertSame('إدارة أنواع التعليم', PermissionMatrix::modules()['education_types']['name']);
    }

    public function test_the_page_needs_the_module(): void
    {
        $admin = User::factory()->create(['role' => 'admin']);
        $this->actingAs($admin)->get('/case-sheet-types')->assertForbidden();

        UserPermission::create(['user_id' => $admin->id, 'module' => 'case_sheet_types', 'permission' => 'view', 'granted' => true]);
        PermissionManager::forget($admin->id, 'case_sheet_types', 'view');
        $this->actingAs($admin)->get('/case-sheet-types')->assertOk();
    }
}
