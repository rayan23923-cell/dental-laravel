<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The waiting screen became its own permission (2026-10-24, by request).
 * Every account keeps what it could do before: its settings went with
 * settings.view / settings.edit, and pairing a TV was open to all staff.
 */
return new class extends Migration
{
    public function up(): void
    {
        $holders = fn (string $permission) => DB::table('user_permissions')
            ->where('module', 'settings')->where('permission', $permission)->where('granted', true)
            ->pluck('user_id');

        $this->grant($holders('view'), 'view');
        $this->grant($holders('edit'), 'edit');
        $this->grant(DB::table('users')->pluck('id'), 'pair');
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'waiting_screen')->delete();
    }

    private function grant($userIds, string $permission): void
    {
        $existing = DB::table('user_permissions')
            ->where('module', 'waiting_screen')->where('permission', $permission)
            ->pluck('user_id')->flip();

        $rows = collect($userIds)->unique()
            ->reject(fn ($id) => isset($existing[$id]))
            ->map(fn ($id) => ['user_id' => $id, 'module' => 'waiting_screen', 'permission' => $permission, 'granted' => 1, 'created_at' => now()])
            ->values()->all();

        foreach (array_chunk($rows, 500) as $chunk) {
            DB::table('user_permissions')->insert($chunk);
        }
    }
};
