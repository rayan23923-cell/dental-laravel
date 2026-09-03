<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Group extends Model
{
    protected $table = 'groups';

    public $timestamps = false;

    protected $fillable = [
        'name',
        'stage_id',
        'academic_session_id',
    ];

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function academicSession(): BelongsTo
    {
        return $this->belongsTo(AcademicSession::class);
    }

    public function slots(): HasMany
    {
        return $this->hasMany(GroupSlot::class);
    }

    public function doctors(): BelongsToMany
    {
        return $this->belongsToMany(Doctor::class, 'doctor_group_members')->withPivot('added_at');
    }

    public function patients(): HasMany
    {
        return $this->hasMany(Patient::class);
    }

    public function chairs(): HasMany
    {
        return $this->hasMany(ClinicChair::class);
    }
}
