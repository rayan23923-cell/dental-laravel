<?php

namespace Tests\Feature;

use Tests\TestCase;

class ErrorPagesTest extends TestCase
{
    public function test_missing_page_shows_our_bilingual_404(): void
    {
        config(['app.debug' => false]);

        $this->get('/no-such-page-xyz', ['Accept-Language' => 'ar'])
            ->assertNotFound()
            ->assertSee('الصفحة غير موجودة')
            ->assertSee('Page not found')
            ->assertSee('<html lang="ar" dir="rtl">', false)
            ->assertSee('goBack()', false)
            ->assertDontSee('Laravel');
    }

    public function test_english_browser_gets_english_first(): void
    {
        config(['app.debug' => false]);

        $this->get('/no-such-page-xyz', ['Accept-Language' => 'en-US'])
            ->assertNotFound()
            ->assertSee('<html lang="en" dir="ltr">', false);
    }

    public function test_wrong_method_shows_our_405(): void
    {
        config(['app.debug' => false]);

        $this->call('DELETE', '/up')->assertStatus(405)->assertSee('طريقة الطلب غير مسموحة');
    }

    public function test_inertia_visit_gets_the_error_component(): void
    {
        config(['app.debug' => false]);

        $this->get('/no-such-page-xyz', ['X-Inertia' => 'true', 'X-Requested-With' => 'XMLHttpRequest'])
            ->assertNotFound()
            ->assertJsonPath('component', 'Error')
            ->assertJsonPath('props.status', 404);
    }
}
