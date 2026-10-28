<?php

namespace Tests\Feature;

use App\Models\AccountDeletionRequest;
use App\Models\ClinicSetting;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** The public pages and the deletion request the app stores ask for (2026-10-28). */
class StorePagesTest extends TestCase
{
    use RefreshDatabase;

    public function test_the_public_pages_open_without_signing_in(): void
    {
        $this->get('/privacy-policy')->assertOk()->assertSee('سياسة الخصوصية')->assertSee('Face ID');
        $this->get('/support')->assertOk()->assertSee('الدعم والتواصل');
        $this->get('/terms')->assertOk()->assertSee('شروط الاستخدام');
        $this->get('/delete-account')->assertOk()->assertSee('إرسال طلب الحذف');
    }

    public function test_the_public_form_records_the_request_and_tells_the_admins(): void
    {
        ClinicSetting::current()->update(['enable_notifications' => true]);
        $admin = User::factory()->create(['role' => 'admin']);

        $this->post('/delete-account', ['identifier' => 'student7', 'reason' => 'تخرجت'])
            ->assertRedirect('/delete-account');

        $this->assertDatabaseHas('account_deletion_requests', ['identifier' => 'student7', 'source' => 'web', 'status' => 'pending']);
        $this->assertSame(1, $admin->notifications()->count());
        $this->get('/delete-account')->assertSee('وصل طلبك');
    }

    public function test_the_public_form_needs_an_identifier(): void
    {
        $this->post('/delete-account', [])->assertSessionHasErrors('identifier');
        $this->assertSame(0, AccountDeletionRequest::count());
    }

    public function test_a_signed_in_account_asks_for_its_own_deletion_from_the_app(): void
    {
        $staff = User::factory()->create(['role' => 'reception', 'username' => 'desk1']);
        Sanctum::actingAs($staff);

        $this->postJson('/api/v1/me/deletion-request', ['reason' => 'لم أعد أعمل هنا'])->assertCreated();

        $this->assertDatabaseHas('account_deletion_requests', [
            'account_type' => 'staff', 'account_id' => $staff->id, 'identifier' => 'desk1', 'source' => 'app',
        ]);
    }

    public function test_the_app_request_needs_a_signed_in_account(): void
    {
        $this->postJson('/api/v1/me/deletion-request')->assertUnauthorized();
    }
}
