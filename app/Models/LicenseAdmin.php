<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;

/**
 * An account on the licensing portal (2026-10-17, by request), separate from
 * the clinic's users: it manages universities and their activation codes only.
 * Created with `php artisan licensing:admin`.
 */
class LicenseAdmin extends Authenticatable
{
    protected $fillable = ['name', 'username', 'password'];

    protected $hidden = ['password', 'remember_token'];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'last_login_at' => 'datetime',
        ];
    }
}
