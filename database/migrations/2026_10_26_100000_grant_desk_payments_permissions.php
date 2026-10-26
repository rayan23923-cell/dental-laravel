<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The lab and the ticket desk see and print their own income (2026-10-26,
 * by request): existing lab accounts get payments.view_lab and ticket-desk
 * (reception) accounts payments.view_tickets, as new ones do from
 * App\Support\RolePresets. An admin can still take them away.
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (['lab' => 'view_lab', 'reception' => 'view_tickets'] as $role => $permission) {
            $has = DB::table('user_permissions')->where('module', 'payments')->where('permission', $permission)->pluck('user_id')->flip();
            $rows = DB::table('users')->where('role', $role)->pluck('id')
                ->reject(fn ($id) => isset($has[$id]))
                ->map(fn ($id) => ['user_id' => $id, 'module' => 'payments', 'permission' => $permission, 'granted' => 1, 'created_at' => now()])
                ->all();
            foreach (array_chunk($rows, 500) as $chunk) {
                DB::table('user_permissions')->insert($chunk);
            }
        }
    }

    public function down(): void
    {
        DB::table('user_permissions')->where('module', 'payments')->whereIn('permission', ['view_lab', 'view_tickets'])->delete();
    }
};
