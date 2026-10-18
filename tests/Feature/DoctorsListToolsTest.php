<?php

namespace Tests\Feature;

use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia;
use Tests\TestCase;

/**
 * The doctors list (2026-10-18, by request): rows per page, everyone's
 * cards in one printout, and back/save returning to the same list.
 */
class DoctorsListToolsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        EducationType::create(['id' => 1, 'name' => 'الدراسات الأولية']);
        Stage::create(['id' => 1, 'name' => 'الرابعة', 'education_type_id' => 1]);
        foreach (range(1, 30) as $i) {
            Doctor::create([
                'name' => sprintf('طبيب %02d', $i), 'username' => "d{$i}", 'password' => 'secret',
                'email' => "d{$i}@example.com", 'education_type_id' => 1, 'stage_id' => 1,
            ]);
        }
        $this->actingAs(User::factory()->create(['role' => 'super_admin']));
    }

    public function test_the_list_shows_the_chosen_number_of_rows(): void
    {
        $this->get(route('doctors.index'))->assertInertia(fn (AssertableInertia $p) => $p->has('doctors.data', 15)->where('perPage', '15'));
        $this->get(route('doctors.index', ['per_page' => 25]))->assertInertia(fn (AssertableInertia $p) => $p->has('doctors.data', 25));
        $this->get(route('doctors.index', ['per_page' => 'all']))->assertInertia(fn (AssertableInertia $p) => $p->has('doctors.data', 30)->where('perPage', 'all'));
        // Anything else falls back to 15.
        $this->get(route('doctors.index', ['per_page' => 7]))->assertInertia(fn (AssertableInertia $p) => $p->has('doctors.data', 15));
    }

    public function test_the_cards_print_for_the_filter_or_the_ticked_rows(): void
    {
        $ids = Doctor::orderBy('name')->limit(2)->pluck('id');

        $this->get(route('doctors.cards'))->assertOk()->assertSee('طبيب 30');
        $this->get(route('doctors.cards', ['ids' => $ids->implode(',')]))
            ->assertOk()->assertSee('طبيب 01')->assertDontSee('طبيب 30');
    }

    public function test_saving_returns_to_the_list_it_came_from(): void
    {
        $doctor = Doctor::first();
        $list = route('doctors.index', ['per_page' => 50, 'page' => 1]);

        $this->get(route('doctors.edit', $doctor), ['referer' => $list])
            ->assertInertia(fn (AssertableInertia $p) => $p->where('backUrl', $list));

        $this->put(route('doctors.update', $doctor), [
            'name' => $doctor->name, 'username' => $doctor->username, 'email' => $doctor->email,
            'education_type_id' => 1, 'stage_id' => 1, 'back' => $list,
        ])->assertRedirect($list);

        // Never anywhere but the list.
        $this->put(route('doctors.update', $doctor), [
            'name' => $doctor->name, 'username' => $doctor->username, 'email' => $doctor->email,
            'education_type_id' => 1, 'stage_id' => 1, 'back' => 'https://evil.example/x',
        ])->assertRedirect(route('doctors.index'));
    }
}
