<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * "Senior" / "HR" role assignments scoped to a department + stage.
 *
 * The source schema has two redundant status columns — `is_active`
 * (tinyint) and `status` (enum active/inactive) — and the original PHP app
 * writes only `status` on assign/toggle while some of its own read paths
 * filter on `is_active` and others on `status`, so deactivating a role via
 * the admin UI silently failed to revoke it on pages that checked the
 * other column (confirmed via codebase research, not guessed). This model
 * treats `status` as the single source of truth and keeps `is_active` in
 * sync on every write, so both columns agree going forward — fixing the
 * bug without a schema migration.
 */
class DepartmentRoleAssignment extends Model
{
    public const ROLE_TYPES = ['senior', 'hr'];

    protected $fillable = [
        'user_id',
        'department_id',
        'stage_id',
        'role_type',
        'assigned_by',
        'assigned_at',
        'status',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'assigned_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::saving(function (self $assignment) {
            $assignment->is_active = $assignment->status === 'active';
        });
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function assignedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_by');
    }

    public function activityLogs(): HasMany
    {
        return $this->hasMany(DepartmentRoleActivityLog::class, 'role_assignment_id');
    }

    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }
}
