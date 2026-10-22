<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PingTest extends TestCase
{
    use RefreshDatabase;

    public function test_ping_is_public_and_reports_the_database(): void
    {
        $this->getJson('/api/v1/ping')
            ->assertOk()
            ->assertJson(['ok' => true, 'database' => true]);
    }
}
