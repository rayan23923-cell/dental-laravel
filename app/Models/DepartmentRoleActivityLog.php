<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DepartmentRoleActivityLog extends Model
{
    // Real table name is singular ("log", not Eloquent's default guessed
    // plural "logs") — matches the source schema, not a naming convention
    // choice made here.
    protected $table = 'department_role_activity_log';

    public $timestamps = false;

    protected $fillable = [
        'role_assignment_id',
        'action',
        'performed_by',
        'details',
        'ip_address',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
        ];
    }

    public function assignment(): BelongsTo
    {
        return $this->belongsTo(DepartmentRoleAssignment::class, 'role_assignment_id');
    }

    public function performedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'performed_by');
    }
}
