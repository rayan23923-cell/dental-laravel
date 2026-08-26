<?php

namespace Database\Seeders;

use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        User::firstOrCreate(
            ['email' => 'admin@clinic.test'],
            [
                'full_name' => 'System Administrator',
                'username' => 'admin',
                'phone' => null,
                'password' => 'password',
                'role' => 'super_admin',
                'status' => 'active',
            ]
        );

        $primary = EducationType::firstOrCreate(['id' => 4], ['name' => 'primary Education']);
        $higher = EducationType::firstOrCreate(['id' => 5], ['name' => 'Higher Education']);

        $fourth = Stage::firstOrCreate(['id' => 13], ['name' => 'Fourth Stage', 'education_type_id' => $primary->id]);
        Stage::firstOrCreate(['id' => 14], ['name' => 'Fifth Stage', 'education_type_id' => $primary->id]);
        Stage::firstOrCreate(['id' => 16], ['name' => 'First Stage', 'education_type_id' => $higher->id]);
        Stage::firstOrCreate(['id' => 19], ['name' => 'fifth', 'education_type_id' => $primary->id]);

        foreach ([
            'operative dent' => 14,
            'prosthodontics' => $fourth->id,
            'operative' => $fourth->id,
            'surgery' => $fourth->id,
            'perio' => $fourth->id,
            'ortho' => $fourth->id,
            'pediatric' => $fourth->id,
            'prevention' => $fourth->id,
            'oral medicine' => $fourth->id,
        ] as $name => $stageId) {
            Department::firstOrCreate(
                ['name' => $name, 'stage_id' => $stageId],
                ['education_type_id' => $primary->id]
            );
        }
    }
}
